-- Paint: edits paintutils .nfp images. Left button paints the primary color,
-- right button the secondary. Tools: pencil, line, rectangle, filled box, fill, eraser.
local ui = arcadeos.lib("ui")
local dialog = arcadeos.lib("dialog")
local R = ui.roles()

local TOOLS = {
    { id = "pencil", label = "Pencil", key = keys.p },
    { id = "line", label = "Line", key = keys.l },
    { id = "rect", label = "Rectangle", key = keys.r },
    { id = "box", label = "Filled Box", key = keys.b },
    { id = "fill", label = "Fill", key = keys.f },
    { id = "eraser", label = "Eraser", key = keys.e },
}

local args = { ... }
local img = {}
local path
local dirty = false
local tool = "pencil"
local primary, secondary = colors.black, colors.white
local drag -- { x0, y0, x1, y1, color }

local function setTitle()
    arcadeos.setTitle("Paint - " .. (path and fs.getName(path) or "(untitled)"))
end

local function canvasSize()
    local w, h = term.getSize()
    return w, h - 1
end

local function px(x, y) return img[y] and img[y][x] end
local function setPx(x, y, c)
    local cw, ch = canvasSize()
    if x < 1 or y < 1 or x > cw or y > ch then return end
    img[y] = img[y] or {}
    img[y][x] = c
    dirty = true
end

local function linePoints(x0, y0, x1, y1)
    local pts = {}
    local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
    for i = 0, steps do
        pts[#pts + 1] = { math.floor(x0 + (x1 - x0) * i / steps + 0.5), math.floor(y0 + (y1 - y0) * i / steps + 0.5) }
    end
    return pts
end

local function shapePoints(d)
    if tool == "line" then return linePoints(d.x0, d.y0, d.x1, d.y1) end
    local pts = {}
    local xa, xb = math.min(d.x0, d.x1), math.max(d.x0, d.x1)
    local ya, yb = math.min(d.y0, d.y1), math.max(d.y0, d.y1)
    for y = ya, yb do
        for x = xa, xb do
            if tool == "box" or y == ya or y == yb or x == xa or x == xb then pts[#pts + 1] = { x, y } end
        end
    end
    return pts
end

local function flood(x, y, c)
    local target = px(x, y)
    if target == c then return end
    local cw, ch = canvasSize()
    local stack = { { x, y } }
    while #stack > 0 do
        local p = table.remove(stack)
        local qx, qy = p[1], p[2]
        if qx >= 1 and qy >= 1 and qx <= cw and qy <= ch and px(qx, qy) == target then
            setPx(qx, qy, c)
            stack[#stack + 1] = { qx + 1, qy }
            stack[#stack + 1] = { qx - 1, qy }
            stack[#stack + 1] = { qx, qy + 1 }
            stack[#stack + 1] = { qx, qy - 1 }
        end
    end
end

local function draw()
    local w, h = term.getSize()
    local cw, ch = canvasSize()
    local preview = {}
    if drag then
        for _, p in ipairs(shapePoints(drag)) do preview[p[2] * 1000 + p[1]] = drag.color end
    end
    term.setCursorBlink(false)
    for y = 1, ch do
        local text, fg, bg = {}, {}, {}
        for x = 1, cw do
            local c = preview[y * 1000 + x]
            if c == nil then c = px(x, y) end
            if c then
                text[x], bg[x] = " ", colors.toBlit(c)
            else
                text[x], bg[x] = " ", "0"
            end
            fg[x] = "f"
        end
        term.setCursorPos(1, y)
        term.blit(table.concat(text), table.concat(fg), table.concat(bg))
    end
    -- Palette and status line.
    ui.fill(1, h, w, 1, R.scroll)
    local x = 1
    for i = 0, 15 do
        local c = 2 ^ i
        local mark = (c == primary and c == secondary) and "*" or (c == primary and "1" or (c == secondary and "2" or " "))
        local markFg = (c == colors.black or c == colors.blue or c == colors.gray) and colors.white or colors.black
        ui.text(x, h, mark, markFg, c)
        x = x + 1
    end
    local toolName
    for _, t in ipairs(TOOLS) do if t.id == tool then toolName = t.label end end
    ui.text(x + 1, h, ui.pad(toolName, w - x - 1), R.text, R.scroll)
end

local function load(p)
    local image = paintutils.loadImage(p)
    if not image then
        dialog.alert("Paint", "Cannot open " .. p)
        return
    end
    img = {}
    for y, row in ipairs(image) do
        for x, c in pairs(row) do
            if c and c > 0 then img[y] = img[y] or {}; img[y][x] = c end
        end
    end
    path, dirty = p, false
    setTitle()
end

local function write(p)
    local out = {}
    local maxY = 0
    for y in pairs(img) do maxY = math.max(maxY, y) end
    for y = 1, maxY do
        local row, maxX = {}, 0
        for x in pairs(img[y] or {}) do maxX = math.max(maxX, x) end
        for x = 1, maxX do
            local c = px(x, y)
            row[x] = c and colors.toBlit(c) or " "
        end
        out[y] = table.concat(row)
    end
    local h = fs.open(p, "w")
    if not h then dialog.alert("Paint", "Cannot save " .. p); return false end
    h.write(table.concat(out, "\n"))
    h.close()
    path, dirty = p, false
    setTitle()
    return true
end

local function saveAs()
    local p = dialog.saveFile({ dir = path and fs.getDir(path) or "home", name = path and fs.getName(path) or "", ext = "nfp" })
    return p and write(p) or false
end

local function save() if path then return write(path) end return saveAs() end

local function confirmDiscard()
    if not dirty then return true end
    local r = dialog.yesNoCancel("Paint", "Save changes to " .. (path and fs.getName(path) or "(untitled)") .. "?")
    if r == "yes" then return save() end
    return r == "no"
end

local function setMenus()
    local toolItems = {}
    for _, t in ipairs(TOOLS) do toolItems[#toolItems + 1] = { id = "tool:" .. t.id, label = t.label, checked = tool == t.id } end
    arcadeos.setMenus({
        { label = "File", items = {
            { id = "new", label = "New" }, { id = "open", label = "Open..." },
            { id = "save", label = "Save" }, { id = "saveas", label = "Save As..." },
            "-", { id = "exit", label = "Exit" },
        } },
        { label = "Tools", items = toolItems },
    })
end

local function onMenu(id)
    if id == "new" then
        if confirmDiscard() then img, path, dirty = {}, nil, false; setTitle() end
    elseif id == "open" then
        if confirmDiscard() then
            local p = dialog.openFile({ dir = path and fs.getDir(path) or "home", filter = "%.nfp$" })
            if p then load(p) end
        end
    elseif id == "save" then save()
    elseif id == "saveas" then saveAs()
    elseif id == "exit" then
        if confirmDiscard() then return true end
    elseif id:sub(1, 5) == "tool:" then
        tool = id:sub(6)
        setMenus()
    end
end

setMenus()
if args[1] and fs.exists(args[1]) then load(args[1]) else path = args[1]; setTitle() end

while true do
    draw()
    local ev = { os.pullEventRaw() }
    local name = ev[1]
    local _, h = term.getSize()
    if name == "terminate" then
        if confirmDiscard() then return end
    elseif name == "arcadeos_menu" then
        if onMenu(ev[2]) then return end
    elseif name == "key" then
        for _, t in ipairs(TOOLS) do
            if ev[2] == t.key then tool = t.id; setMenus() end
        end
    elseif name == "mouse_click" and ev[4] == h then
        local i = ev[3] - 1
        if i >= 0 and i <= 15 then
            if ev[2] == 2 then secondary = 2 ^ i else primary = 2 ^ i end
        end
    elseif name == "mouse_click" or name == "mouse_drag" then
        local color = ev[2] == 2 and secondary or primary
        local x, y = ev[3], ev[4]
        if y < h then
            if tool == "pencil" then setPx(x, y, color)
            elseif tool == "eraser" then setPx(x, y, nil)
            elseif tool == "fill" and name == "mouse_click" then flood(x, y, color)
            elseif tool == "line" or tool == "rect" or tool == "box" then
                if name == "mouse_click" then drag = { x0 = x, y0 = y, x1 = x, y1 = y, color = color }
                elseif drag then drag.x1, drag.y1 = x, math.min(y, h - 1) end
            end
        end
    elseif name == "mouse_up" and drag then
        for _, p in ipairs(shapePoints(drag)) do setPx(p[1], p[2], drag.color) end
        drag = nil
    end
end
