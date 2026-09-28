-- Reversi, as shipped with Windows 1.0. You are black and move first.
local ui = arcadeos.lib("ui")
local canvas = arcadeos.lib("canvas")
local R = ui.roles()

local EMPTY, YOU, CPU = 0, 1, 2
local WEIGHT = {
    { 100, -20, 10, 5, 5, 10, -20, 100 },
    { -20, -50, -2, -2, -2, -2, -50, -20 },
    { 10, -2, -1, -1, -1, -1, -2, 10 },
    { 5, -2, -1, -1, -1, -1, -2, 5 },
    { 5, -2, -1, -1, -1, -1, -2, 5 },
    { 10, -2, -1, -1, -1, -1, -2, 10 },
    { -20, -50, -2, -2, -2, -2, -50, -20 },
    { 100, -20, 10, 5, 5, 10, -20, 100 },
}
local DIRS = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } }

local board, turn, status, hint, over
local skill = arcadeos.getSetting("reversi.skill", "expert")
local cursor = { 4, 4 }
local showCursor = false
local geo

local function newGame()
    board = {}
    for r = 1, 8 do board[r] = { 0, 0, 0, 0, 0, 0, 0, 0 } end
    board[4][4], board[5][5] = CPU, CPU
    board[4][5], board[5][4] = YOU, YOU
    turn, status, hint, over = YOU, "Your move", nil, false
end

local function flips(b, r, c, who)
    if b[r][c] ~= EMPTY then return nil end
    local other = 3 - who
    local out = {}
    for _, d in ipairs(DIRS) do
        local rr, cc, line = r + d[1], c + d[2], {}
        while rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 and b[rr][cc] == other do
            line[#line + 1] = { rr, cc }
            rr, cc = rr + d[1], cc + d[2]
        end
        if #line > 0 and rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 and b[rr][cc] == who then
            for _, p in ipairs(line) do out[#out + 1] = p end
        end
    end
    return #out > 0 and out or nil
end

local function moves(b, who)
    local list = {}
    for r = 1, 8 do
        for c = 1, 8 do
            local f = flips(b, r, c, who)
            if f then list[#list + 1] = { r = r, c = c, flips = f } end
        end
    end
    return list
end

local function play(b, m, who)
    b[m.r][m.c] = who
    for _, p in ipairs(m.flips) do b[p[1]][p[2]] = who end
end

local function copy(b)
    local n = {}
    for r = 1, 8 do n[r] = { table.unpack(b[r]) } end
    return n
end

local function count()
    local y, c = 0, 0
    for r = 1, 8 do for col = 1, 8 do
        if board[r][col] == YOU then y = y + 1 elseif board[r][col] == CPU then c = c + 1 end
    end end
    return y, c
end

local function choose(who)
    local list = moves(board, who)
    if #list == 0 then return nil end
    if skill == "beginner" then return list[math.random(#list)] end
    local best, bestScore
    for _, m in ipairs(list) do
        local b = copy(board)
        play(b, m, who)
        local reply = 0
        for _, o in ipairs(moves(b, 3 - who)) do reply = math.max(reply, WEIGHT[o.r][o.c] + #o.flips) end
        local score = WEIGHT[m.r][m.c] + #m.flips - reply * 0.5 + math.random() * 0.1
        if not bestScore or score > bestScore then best, bestScore = m, score end
    end
    return best
end

local function finishIfOver()
    if #moves(board, YOU) == 0 and #moves(board, CPU) == 0 then
        local y, c = count()
        over = true
        status = y > c and ("You win " .. y .. "-" .. c) or (y < c and ("You lose " .. y .. "-" .. c) or "Tie game")
        return true
    end
end

local function geometry()
    local w, h = term.getSize()
    local sw, sh = 2, 1
    if w >= 24 and h - 1 >= 16 then sw, sh = 3, 2 end
    local bw, bh = 8 * sw, 8 * sh
    return { sw = sw, sh = sh, x = math.floor((w - bw) / 2) + 1, y = math.max(1, math.floor((h - 1 - bh) / 2) + 1),
        w = w, h = h, fits = bh <= h - 1 and bw <= w }
end

local function draw()
    geo = geometry()
    local w, h = geo.w, geo.h
    ui.fill(1, 1, w, h, R.window)
    term.setCursorBlink(false)
    if not geo.fits then
        ui.center(math.ceil(h / 2), "Enlarge window", R.text, R.window)
        return
    end
    local legal = {}
    if turn == YOU and not over then
        for _, m in ipairs(moves(board, YOU)) do legal[m.r * 10 + m.c] = true end
    end
    local cv = canvas.new(8 * geo.sw, 8 * geo.sh)
    local spw, sph = geo.sw * 2, geo.sh * 3
    for r = 1, 8 do
        for c = 1, 8 do
            local ox, oy = (c - 1) * spw, (r - 1) * sph
            -- Off-center by half a subpixel so discs get a one-pixel gutter on the right and bottom.
            local cx, cy = ox + math.floor(spw / 2), oy + math.floor(sph / 2)
            local v = board[r][c]
            if showCursor and cursor[1] == r and cursor[2] == c then
                for i = 1, spw do cv:set(ox + i, oy + 1, colors.lime); cv:set(ox + i, oy + sph, colors.lime) end
                for i = 1, sph do cv:set(ox + 1, oy + i, colors.lime); cv:set(ox + spw, oy + i, colors.lime) end
            end
            if v ~= EMPTY then
                cv:disc(cx, cy, math.min(spw, sph) / 2 - 0.7, v == YOU and colors.black or colors.white)
            elseif hint and hint.r == r and hint.c == c then
                cv:circle(cx, cy, math.min(spw, sph) / 2 - 0.8, colors.yellow)
            elseif legal[r * 10 + c] then
                cv:disc(cx, cy, 0.7, colors.yellow)
            end
        end
    end
    cv:draw(geo.x, geo.y, colors.green)
    local y, c = count()
    ui.text(1, h, ui.pad((" You %d  CC %d  %s"):format(y, c, status), w), R.selectText, R.scrollThumb)
end

local function afterMove()
    hint = nil
    if finishIfOver() then return end
    if turn == YOU then
        turn = CPU
        if #moves(board, CPU) == 0 then
            turn, status = YOU, "CC passes. Your move"
        else
            status = "Thinking..."
        end
    else
        turn = YOU
        if #moves(board, YOU) == 0 then
            turn, status = CPU, "You must pass"
        else
            status = "Your move"
        end
    end
end

local function tryPlayer(r, c)
    if over or turn ~= YOU then return end
    local f = flips(board, r, c, YOU)
    if not f then return end
    play(board, { r = r, c = c, flips = f }, YOU)
    afterMove()
end

local function setMenus()
    arcadeos.setMenus({
        { label = "Game", items = {
            { id = "new", label = "New Game" }, { id = "hint", label = "Hint" },
            "-", { id = "exit", label = "Exit" } } },
        { label = "Skill", items = {
            { id = "beginner", label = "Beginner", checked = skill == "beginner" },
            { id = "expert", label = "Expert", checked = skill == "expert" } } },
    })
end

newGame()
setMenus()
local cpuTimer
while true do
    if turn == CPU and not over and not cpuTimer then cpuTimer = os.startTimer(0.5) end
    draw()
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "timer" and ev[2] == cpuTimer then
        cpuTimer = nil
        local m = choose(CPU)
        if m then play(board, m, CPU) end
        afterMove()
    elseif name == "mouse_click" and geo and geo.fits then
        showCursor = false
        local c = math.floor((ev[3] - geo.x) / geo.sw) + 1
        local r = math.floor((ev[4] - geo.y) / geo.sh) + 1
        if r >= 1 and r <= 8 and c >= 1 and c <= 8 then tryPlayer(r, c) end
    elseif name == "key" then
        local k = ev[2]
        if k == keys.up then cursor[1] = math.max(1, cursor[1] - 1); showCursor = true
        elseif k == keys.down then cursor[1] = math.min(8, cursor[1] + 1); showCursor = true
        elseif k == keys.left then cursor[2] = math.max(1, cursor[2] - 1); showCursor = true
        elseif k == keys.right then cursor[2] = math.min(8, cursor[2] + 1); showCursor = true
        elseif k == keys.enter or k == keys.space then tryPlayer(cursor[1], cursor[2]) end
    elseif name == "arcadeos_menu" then
        local id = ev[2]
        if id == "new" then newGame()
        elseif id == "hint" and turn == YOU then hint = choose(YOU)
        elseif id == "exit" then return
        elseif id == "beginner" or id == "expert" then
            skill = id
            arcadeos.setSetting("reversi.skill", id)
            setMenus()
        end
    end
end
