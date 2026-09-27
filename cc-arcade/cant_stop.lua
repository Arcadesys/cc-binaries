-- cant_stop.lua
-- A push-your-luck dice game for the Arcade OS

local w, h = term.getSize()
local cx, cy = math.floor(w / 2), math.floor(h / 2)

-- 3-Button Config
local input = require("input")
local audio = require("audio")

local function refreshSize()
    w, h = term.getSize()
    cx, cy = math.floor(w / 2), math.floor(h / 2)
end

--------------------------------------------------------------------------------
-- UI PRIMITIVES (direct draw)
--------------------------------------------------------------------------------

local HAS_BLIT = type(term.blit) == "function" and type(colors) == "table" and type(colors.toBlit) == "function"

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function toBlit(c)
    if not HAS_BLIT then return "0" end
    return colors.toBlit(c)
end

local function fillRect(x, y, width, height, bg, fg, ch)
    if width <= 0 or height <= 0 then return end
    ch = ch or " "
    bg = bg or colors.black
    fg = fg or colors.white

    if HAS_BLIT then
        local text = string.rep(ch, width)
        local fgs = string.rep(toBlit(fg), width)
        local bgs = string.rep(toBlit(bg), width)
        for row = 0, height - 1 do
            term.setCursorPos(x, y + row)
            term.blit(text, fgs, bgs)
        end
    else
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        for row = 0, height - 1 do
            term.setCursorPos(x, y + row)
            term.write(string.rep(ch, width))
        end
    end
end

local function writeAt(x, y, text, fg, bg)
    if not text or #text == 0 then return end
    term.setCursorPos(x, y)
    if HAS_BLIT and fg and bg then
        term.blit(text, string.rep(toBlit(fg), #text), string.rep(toBlit(bg), #text))
        return
    end
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end

local function centerText(x, y, width, text, fg, bg)
    local tx = x + math.floor((width - #text) / 2)
    writeAt(tx, y, text, fg, bg)
end

local function frameRect(x, y, width, height, borderBg, innerBg)
    if width <= 1 or height <= 1 then return end
    borderBg = borderBg or colors.gray
    innerBg = innerBg or colors.black
    fillRect(x, y, width, 1, borderBg)
    fillRect(x, y + height - 1, width, 1, borderBg)
    fillRect(x, y + 1, 1, height - 2, borderBg)
    fillRect(x + width - 1, y + 1, 1, height - 2, borderBg)
    fillRect(x + 1, y + 1, width - 2, height - 2, innerBg)
end

local function drawTitleBar(title, rightText)
    local w2, _ = term.getSize()
    fillRect(1, 1, w2, 1, colors.blue)
    writeAt(2, 1, title, colors.yellow, colors.blue)
    if rightText then
        writeAt(math.max(1, w2 - #rightText), 1, rightText, colors.white, colors.blue)
    end
end

local function drawButtonBar(leftText, centerTextLabel, rightText)
    local w2, h2 = term.getSize()
    local colW = math.floor(w2 / 3)
    local leftW = colW
    local midW = colW
    local rightW = w2 - (colW * 2)

    local function fit(text, width)
        text = text or ""
        if width <= 0 then return "" end
        if #text > width then
            return text:sub(1, width)
        end
        return text
    end

    fillRect(1, h2, leftW, 1, colors.red)
    fillRect(leftW + 1, h2, midW, 1, colors.yellow)
    fillRect(leftW + midW + 1, h2, rightW, 1, colors.blue)

    centerText(1, h2, leftW, fit(leftText, leftW), colors.white, colors.red)
    centerText(leftW + 1, h2, midW, fit(centerTextLabel, midW), colors.black, colors.yellow)
    centerText(leftW + midW + 1, h2, rightW, fit(rightText, rightW), colors.white, colors.blue)
end

local function isDedicatedCantStopMachine()
    if not fs.exists(".arcade_config") then return false end
    local f = fs.open(".arcade_config", "r")
    if not f then return false end
    local cmd = (f.readAll() or "")
    f.close()
    cmd = cmd:gsub("%s+", "")
    return cmd == "cant_stop"
end

local DEDICATED = isDedicatedCantStopMachine()

local function nowMillis()
    if type(os.epoch) == "function" then
        return os.epoch("utc")
    end
    return math.floor((os.clock() or 0) * 1000)
end

local function waitKey(tickInterval)
    local resizeTimer = os.startTimer(0.5)
    local tickTimer = nil
    if tickInterval and tickInterval > 0 then
        tickTimer = os.startTimer(tickInterval)
    end
    while true do
        local e, p1 = os.pullEvent()
        local button = input.getButton(e, p1)
        if button then
            if e == "redstone" then sleep(0.2) end
            return button
        end

        -- Poll size changes (and also react to CC's resize event)
        if e == "term_resize" then
            refreshSize()
            return "RESIZE"
        elseif e == "timer" and tickTimer and p1 == tickTimer then
            return "TICK"
        elseif e == "timer" and p1 == resizeTimer then
            local oldW, oldH = w, h
            refreshSize()
            resizeTimer = os.startTimer(0.5)
            if w ~= oldW or h ~= oldH then
                return "RESIZE"
            end
        end

        -- Keyboard exit (spawn-friendly / dev-friendly)
        if e == "key" and keys.getName(p1) == "backspace" then
            return "EXIT"
        elseif e == "char" and tostring(p1):lower() == "e" then
            return "EXIT"
        elseif e == "terminate" then
            return "EXIT"
        end
    end
end

--------------------------------------------------------------------------------
-- GAME LOGIC
--------------------------------------------------------------------------------

local COL_LENGTHS = {
    [2]=3, [3]=5, [4]=7, [5]=9, [6]=11,
    [7]=13,
    [8]=11, [9]=9, [10]=7, [11]=5, [12]=3
}

local board = {} -- [col] = {p1=0, p2=0, owner=nil}
for i=2,12 do board[i] = {p1=0, p2=0, owner=nil} end

local currentPlayer = 1
local tempMarkers = {} -- [col] = current_step
local runnersUsed = 0
local MAX_RUNNERS = 3

local function rollDice()
    local d = {}
    for i=1,4 do table.insert(d, math.random(1,6)) end
    return d
end

local function getPairings(dice)
    -- 3 ways to pair 4 dice: (1+2, 3+4), (1+3, 2+4), (1+4, 2+3)
    local pairs = {
        { {dice[1], dice[2]}, {dice[3], dice[4]} },
        { {dice[1], dice[3]}, {dice[2], dice[4]} },
        { {dice[1], dice[4]}, {dice[2], dice[3]} }
    }
    -- Calculate sums
    local options = {}
    for _, p in ipairs(pairs) do
        local s1 = p[1][1] + p[1][2]
        local s2 = p[2][1] + p[2][2]
        table.insert(options, {s1, s2})
    end
    return options
end

local function canAdvance(col)
    if board[col].owner then return false end
    if runnersUsed >= MAX_RUNNERS and not tempMarkers[col] then
        -- Check if we have a base marker here? No, runners must be placed.
        -- If we have a base marker but no runner, we need a runner to advance.
        return false
    end
    -- Check if already at top
    local current = tempMarkers[col] or (currentPlayer == 1 and board[col].p1 or board[col].p2)
    if current >= COL_LENGTHS[col] then return false end
    return true
end

local function isValidOption(opt)
    -- An option is valid if at least one of the sums can be played
    return canAdvance(opt[1]) or canAdvance(opt[2])
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local function drawText(x, y, text, fg, bg)
    writeAt(x, y, text, fg, bg)
end

local function drawBoard(showTemp)
    -- Legacy 2p renderer (kept for compatibility, but uses the new primitives)
    local w2, h2 = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawTitleBar("CAN'T STOP", "P" .. tostring(currentPlayer) .. " TURN")

    local top = 3
    local bottom = h2 - 3
    local availH = bottom - top + 1
    local availW = w2 - 2
    local colCount = 11
    local gap = 1
    local colW = clamp(math.floor((availW - (colCount - 1)) / colCount), 3, 5)
    while colW > 3 and (2 + colCount * (colW + gap) - gap) > w2 do
        colW = colW - 1
    end
    local startX = 2

    for col = 2, 12 do
        local idx = col - 2
        local x = startX + idx * (colW + gap)
        local len = COL_LENGTHS[col]
        local owner = board[col].owner

        local ownerBg = colors.lightGray
        local ownerFg = colors.black
        if owner == 1 then ownerBg = colors.blue; ownerFg = colors.white
        elseif owner == 2 then ownerBg = colors.red; ownerFg = colors.white end

        frameRect(x, top, colW, availH, colors.gray, colors.black)
        fillRect(x + 1, top + 1, colW - 2, 1, ownerBg)
        centerText(x + 1, top + 1, colW - 2, tostring(col), ownerFg, ownerBg)

        local trackTop = top + 3
        local trackBottom = bottom - 1
        for step = 1, len do
            local y = trackBottom - (step - 1)
            if y >= trackTop and y <= trackBottom then
                fillRect(x + 1, y, colW - 2, 1, colors.gray, colors.black, " ")
            end
        end

        local p1 = board[col].p1
        local p2 = board[col].p2
        local temp = tempMarkers[col]
        local function drawMarker(step, fg, bg, ch)
            local y = trackBottom - (step - 1)
            if y < trackTop or y > trackBottom then return end
            local mx = x + math.floor(colW / 2)
            writeAt(mx, y, ch or " ", fg or colors.white, bg or colors.white)
        end

        if showTemp and temp and temp >= 1 then
            local tBg = (currentPlayer == 1) and colors.cyan or colors.orange
            drawMarker(temp, colors.black, tBg, " ")
        end
        if p1 and p1 >= 1 then drawMarker(p1, colors.black, colors.blue, " ") end
        if p2 and p2 >= 1 then
            if p1 == p2 and p1 >= 1 then
                drawMarker(p2, colors.white, colors.magenta, " ")
            else
                drawMarker(p2, colors.black, colors.red, " ")
            end
        end
    end

    fillRect(1, h2 - 2, w2, 1, colors.black)
    writeAt(2, h2 - 2, "[L/C/R] Choose  |  [E]/[Backspace] Exit", colors.gray, colors.black)
end



local function drawActionMenu()
    local w2, h2 = term.getSize()
    fillRect(1, h2 - 2, w2, 1, colors.black)
    writeAt(2, h2 - 2, "Action:", colors.white, colors.black)
    drawButtonBar("Roll Again", "Stop (Save)", "View Board")
end

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------

local function returnToMenu()
    term.setBackgroundColor(colors.black)
    term.clear()
    if fs.exists("menu.lua") then shell.run("menu.lua") end
end

local function runOneGame()
    -- returns true if player requested EXIT
    local numPlayers = 1

    local function runAttractModeNewGame()
        while true do
            refreshSize()
            local w2, h2 = term.getSize()
            local cx2, cy2 = math.floor(w2 / 2), math.floor(h2 / 2)

            term.setBackgroundColor(colors.black)
            term.clear()
            drawTitleBar("CAN'T STOP", "DEMO")

            frameRect(cx2 - 16, cy2 - 4, 33, 9, colors.gray, colors.black)
            centerText(cx2 - 16, cy2 - 4, 33, " ATTRACTION MODE ", colors.yellow, colors.gray)
            centerText(cx2 - 16, cy2 - 2, 33, "Rolling dice...", colors.white, colors.black)

            local dice = rollDice()
            local d = tostring(dice[1]) .. "  " .. tostring(dice[2]) .. "  " .. tostring(dice[3]) .. "  " .. tostring(dice[4])
            centerText(cx2 - 16, cy2, 33, d, colors.lime, colors.black)

            local opts = getPairings(dice)
            local o1 = tostring(opts[1][1]) .. "+" .. tostring(opts[1][2])
            local o2 = tostring(opts[2][1]) .. "+" .. tostring(opts[2][2])
            local o3 = tostring(opts[3][1]) .. "+" .. tostring(opts[3][2])
            centerText(cx2 - 16, cy2 + 2, 33, "Options: " .. o1 .. " | " .. o2 .. " | " .. o3, colors.gray, colors.black)
            centerText(cx2 - 16, cy2 + 4, 33, "Press any button to play", colors.lightGray, colors.black)

            audio.playShuffle()
            local key = waitKey(0.25)
            if key == "RESIZE" then
                -- keep looping
            elseif key ~= "TICK" then
                return key
            end
        end
    end

    while true do
        refreshSize()
        local w2, h2 = term.getSize()
        local cx2, cy2 = math.floor(w2 / 2), math.floor(h2 / 2)
        term.setBackgroundColor(colors.black)
        term.clear()
        drawTitleBar("CAN'T STOP", nil)

        frameRect(cx2 - 16, cy2 - 4, 33, 9, colors.gray, colors.black)
        centerText(cx2 - 16, cy2 - 4, 33, " NEW GAME ", colors.yellow, colors.gray)
        centerText(cx2 - 16, cy2 - 1, 33, "Players: " .. tostring(numPlayers), colors.white, colors.black)
        centerText(cx2 - 16, cy2 + 1, 33, "[L] -    [C] Start    [R] +", colors.gray, colors.black)
        centerText(cx2 - 16, cy2 + 3, 33, "[E]/[Backspace] Exit", colors.gray, colors.black)

        local key = waitKey(8)
        if key == "TICK" then
            key = runAttractModeNewGame()
        end
        if key == "RESIZE" then
            -- redraw immediately with new size
            goto continue_player_select
        end
        if key == "EXIT" then
            return true
        end
        if key == "LEFT" and numPlayers > 1 then numPlayers = numPlayers - 1 end
        if key == "RIGHT" and numPlayers < 3 then numPlayers = numPlayers + 1 end
        if key == "CENTER" then break end

        ::continue_player_select::
    end

    -- Initialize Board for N players
    for i = 2, 12 do
        board[i] = { positions = {}, owner = nil }
        for p = 1, numPlayers do
            board[i].positions[p] = 0
        end
    end

    local currentPlayer = 1

    local function drawBoardN(showTemp, dice, options, isValidOpt, modeLabel)
        local w2, h2 = term.getSize()
        term.setBackgroundColor(colors.black)
        term.clear()

        local pColorName = "Blue"
        if currentPlayer == 2 then pColorName = "Red" elseif currentPlayer == 3 then pColorName = "Green" end
        drawTitleBar("CAN'T STOP", "P" .. tostring(currentPlayer) .. " " .. pColorName)

        -- Dice strip
        fillRect(1, 2, w2, 1, colors.black)
        if dice then
            writeAt(2, 2, "Dice:", colors.gray, colors.black)
            local x = 8
            for i = 1, 4 do
                if x + 3 > w2 then break end
                local d = tostring(dice[i] or "-")
                frameRect(x, 2, 4, 1, colors.gray, colors.black)
                centerText(x, 2, 4, d, colors.white, colors.black)
                x = x + 5
            end
        end
        if modeLabel then
            writeAt(math.max(1, w2 - #modeLabel - 1), 2, modeLabel, colors.yellow, colors.black)
        end

        -- Board geometry
        local top = 3
        local bottom = h2 - 4
        local availH = bottom - top + 1
        local availW = w2 - 2
        local colCount = 11
        local gap = 1
        local colW = clamp(math.floor((availW - (colCount - 1)) / colCount), 3, 6)
        while colW > 3 and (2 + colCount * (colW + gap) - gap) > w2 do
            colW = colW - 1
        end
        local startX = 2

        local playerBg = {
            [1] = colors.blue,
            [2] = colors.red,
            [3] = colors.green,
        }

        local function flashPlayerColor(players)
            if not players or #players == 0 then return colors.magenta end
            local sec = math.floor(nowMillis() / 1000)
            local idx = (sec % #players) + 1
            return playerBg[players[idx]] or colors.magenta
        end

        for col = 2, 12 do
            local idx = col - 2
            local x = startX + idx * (colW + gap)
            local len = COL_LENGTHS[col]
            local owner = board[col].owner

            local headerBg = colors.gray
            local headerFg = colors.black
            if owner and playerBg[owner] then
                headerBg = playerBg[owner]
                headerFg = colors.white
            end

            frameRect(x, top, colW, availH, colors.gray, colors.black)
            fillRect(x + 1, top + 1, colW - 2, 1, headerBg)
            centerText(x + 1, top + 1, colW - 2, tostring(col), headerFg, headerBg)

            local trackTop = top + 3
            local trackBottom = bottom

            -- draw empty track cells
            for step = 1, len do
                local y = trackBottom - (step - 1)
                if y >= trackTop and y <= trackBottom then
                    fillRect(x + 1, y, colW - 2, 1, colors.lightGray, colors.black, " ")
                end
            end

            -- gather occupants per step
            local stepOccupants = {}
            for p = 1, numPlayers do
                local step = board[col].positions[p]
                if step and step > 0 then
                    stepOccupants[step] = stepOccupants[step] or {}
                    table.insert(stepOccupants[step], p)
                end
            end

            local function drawChip(step, fg, bg, ch)
                if not step or step <= 0 then return end
                local y = trackBottom - (step - 1)
                if y < trackTop or y > trackBottom then return end
                local mx = x + math.floor(colW / 2)
                writeAt(mx, y, ch or " ", fg, bg)
            end

            -- base markers
            for step, players in pairs(stepOccupants) do
                if #players > 1 then
                    drawChip(step, colors.black, flashPlayerColor(players), " ")
                else
                    local p = players[1]
                    drawChip(step, colors.black, playerBg[p] or colors.white, " ")
                end
            end

            -- temp marker (draw last so it pops)
            if showTemp then
                local t = tempMarkers[col]
                if t and t > 0 then
                    local tBg = (currentPlayer == 1) and colors.cyan or (currentPlayer == 2 and colors.orange or colors.lime)
                    drawChip(t, colors.black, tBg, " ")
                end
            end
        end

        -- (Pick options are rendered in the bottom 3-button bar during CHOOSE)
    end

    while true do
        tempMarkers = {}
        runnersUsed = 0
        local turnOver = false

        while not turnOver do
            audio.playShuffle()
            local dice = rollDice()
            local options = getPairings(dice)

            local function canAdvanceN(col)
                if board[col].owner then return false end
                if runnersUsed >= MAX_RUNNERS and not tempMarkers[col] then return false end
                local current = tempMarkers[col] or board[col].positions[currentPlayer]
                if current >= COL_LENGTHS[col] then return false end
                return true
            end

            local function isValidOptionN(opt)
                return canAdvanceN(opt[1]) or canAdvanceN(opt[2])
            end

            local canMove = false
            for _, opt in ipairs(options) do
                if isValidOptionN(opt) then canMove = true break end
            end

            if not canMove then
                local w2, h2 = term.getSize()
                drawBoardN(true, dice, nil, nil, "BUST")
                fillRect(1, h2 - 2, w2, 1, colors.black)
                writeAt(2, h2 - 2, "BUST! No valid moves.", colors.red, colors.black)
                audio.playLose()
                sleep(2)
                turnOver = true
            else
                local chosen = nil
                while not chosen do
                    drawBoardN(true, dice, nil, nil, "CHOOSE")

                    local function choiceLabel(i)
                        local opt = options[i]
                        if not opt then return tostring(i) .. ":--" end
                        local valid = isValidOptionN(opt)
                        if not valid then
                            return tostring(i) .. ":X"
                        end
                        return tostring(i) .. ":" .. tostring(opt[1]) .. "&" .. tostring(opt[2])
                    end

                    drawButtonBar(choiceLabel(1), choiceLabel(2), choiceLabel(3))

                    local key = waitKey(1.0)
                    if key == "RESIZE" then
                        -- loop will redraw
                        goto continue_choose
                    end
                    if key == "TICK" then
                        goto continue_choose
                    end
                    if key == "EXIT" then
                        return true
                    end

                    local selIdx = 0
                    if key == "LEFT" then selIdx = 1
                    elseif key == "CENTER" then selIdx = 2
                    elseif key == "RIGHT" then selIdx = 3 end

                    if selIdx > 0 and selIdx <= #options and isValidOptionN(options[selIdx]) then
                        chosen = options[selIdx]
                    end

                    ::continue_choose::
                end

                local function advance(col)
                    if not canAdvanceN(col) then return end
                    if not tempMarkers[col] then
                        runnersUsed = runnersUsed + 1
                        local start = board[col].positions[currentPlayer]
                        tempMarkers[col] = start + 1
                    else
                        tempMarkers[col] = tempMarkers[col] + 1
                    end
                end

                advance(chosen[1])
                advance(chosen[2])
                audio.playChip()

                local actionChosen = false
                while not actionChosen do
                    drawBoardN(true, dice, nil, nil, "ACTION")
                    drawActionMenu()

                    local key = waitKey(1.0)
                    if key == "RESIZE" then
                        goto continue_action
                    end
                    if key == "TICK" then
                        goto continue_action
                    end
                    if key == "EXIT" then
                        return true
                    end

                    if key == "LEFT" then
                        actionChosen = true
                    elseif key == "CENTER" then
                        for col, step in pairs(tempMarkers) do
                            board[col].positions[currentPlayer] = step
                            if step >= COL_LENGTHS[col] then
                                board[col].owner = currentPlayer
                                audio.playWin()
                            end
                        end
                        turnOver = true
                        actionChosen = true
                        audio.playConfirm()
                    elseif key == "RIGHT" then
                        -- View Board: no-op (redraw loop)
                    end

                    ::continue_action::
                end
            end
        end

        local owned = 0
        for col = 2, 12 do
            if board[col].owner == currentPlayer then owned = owned + 1 end
        end

        if owned >= 3 then
            local w2, h2 = term.getSize()
            term.setBackgroundColor(colors.black)
            term.clear()
            drawTitleBar("CAN'T STOP", "WIN")
            frameRect(math.floor(w2 / 2) - 14, math.floor(h2 / 2) - 2, 29, 5, colors.gray, colors.black)
            centerText(math.floor(w2 / 2) - 14, math.floor(h2 / 2) - 1, 29, "PLAYER " .. tostring(currentPlayer), colors.lime, colors.black)
            centerText(math.floor(w2 / 2) - 14, math.floor(h2 / 2) + 1, 29, "WINS!", colors.lime, colors.black)
            audio.playWin()
            sleep(2)
            return false
        end

        currentPlayer = (currentPlayer % numPlayers) + 1
    end
end

local function main()
    -- Free play (no credits / no casino hooks)
    while true do
        local exitRequested = runOneGame()
        if not DEDICATED then
            returnToMenu()
            return
        end
        -- Dedicated spawn machine: always restart instead of showing casino UI.
        if exitRequested then
            sleep(0.1)
        end
    end
end

main()
