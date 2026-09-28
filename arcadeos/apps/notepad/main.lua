-- Notepad: plain text editor.
local ui = arcadeos.lib("ui")
local dialog = arcadeos.lib("dialog")
local R = ui.roles()

local args = { ... }
local path
local lines = { "" }
local cx, cy = 1, 1
local sx, sy = 0, 0
local dirty = false
local ctrl = false
local lastFind

local function setTitle()
    arcadeos.setTitle("Notepad - " .. (path and fs.getName(path) or "(untitled)"))
end

local function load(p)
    local h = fs.open(p, "r")
    if not h then
        dialog.alert("Notepad", "Cannot open " .. p)
        return false
    end
    local text = h.readAll() or ""
    h.close()
    lines = {}
    for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if #lines == 0 then lines = { "" } end
    if #lines > 1 and lines[#lines] == "" and text:sub(-1) == "\n" then lines[#lines] = nil end
    path, dirty, cx, cy, sx, sy = p, false, 1, 1, 0, 0
    setTitle()
    return true
end

local function write(p)
    local h = fs.open(p, "w")
    if not h then
        dialog.alert("Notepad", "Cannot save " .. p)
        return false
    end
    h.write(table.concat(lines, "\n"))
    h.close()
    path, dirty = p, false
    setTitle()
    return true
end

local function saveAs()
    local p = dialog.saveFile({ dir = path and fs.getDir(path) or "home", name = path and fs.getName(path) or "", ext = "txt" })
    return p and write(p) or false
end

local function save()
    if path then return write(path) end
    return saveAs()
end

-- Returns true if it's OK to discard the current document.
local function confirmDiscard()
    if not dirty then return true end
    local r = dialog.yesNoCancel("Notepad", "Save changes to " .. (path and fs.getName(path) or "(untitled)") .. "?")
    if r == "yes" then return save() end
    return r == "no"
end

local function clampCursor()
    cy = math.max(1, math.min(cy, #lines))
    cx = math.max(1, math.min(cx, #lines[cy] + 1))
end

local function insert(text)
    local first = true
    for part in (text .. "\n"):gmatch("(.-)\n") do
        if not first then
            local line = lines[cy]
            lines[cy] = line:sub(1, cx - 1)
            table.insert(lines, cy + 1, line:sub(cx))
            cy, cx = cy + 1, 1
        end
        local line = lines[cy]
        lines[cy] = line:sub(1, cx - 1) .. part .. line:sub(cx)
        cx = cx + #part
        first = false
    end
    dirty = true
end

local function draw()
    local w, h = term.getSize()
    local tw = w - 1
    if cx - 1 < sx then sx = cx - 1 end
    if cx - 1 >= sx + tw then sx = cx - tw end
    if cy - 1 < sy then sy = cy - 1 end
    if cy - 1 >= sy + h then sy = cy - h end
    term.setCursorBlink(false)
    for row = 1, h do
        local line = lines[sy + row]
        ui.text(1, row, ui.pad(line and line:sub(sx + 1, sx + tw) or "", tw), R.text, R.window)
    end
    ui.scrollbar(w, 1, h, sy + 1, #lines + h - 1, h)
    term.setCursorPos(cx - sx, cy - sy)
    term.setTextColor(R.text)
    term.setCursorBlink(true)
end

local function find(again)
    if not again or not lastFind then
        lastFind = dialog.prompt("Find", "Find what:", lastFind or "")
        if not lastFind or lastFind == "" then return end
    end
    local needle = lastFind:lower()
    for i = 0, #lines do
        local y = (cy - 1 + i) % #lines + 1
        local from = (i == 0) and cx + 1 or 1
        local s = lines[y]:lower():find(needle, from, true)
        if s then cy, cx = y, s; return end
    end
    dialog.alert("Find", "Cannot find \"" .. lastFind .. "\"")
end

local function quit()
    if confirmDiscard() then error("__notepad_exit", 0) end
end

local function onMenu(id)
    if id == "new" then
        if confirmDiscard() then lines, path, dirty, cx, cy = { "" }, nil, false, 1, 1; setTitle() end
    elseif id == "open" then
        if confirmDiscard() then
            local p = dialog.openFile({ dir = path and fs.getDir(path) or "home" })
            if p then load(p) end
        end
    elseif id == "save" then save()
    elseif id == "saveas" then saveAs()
    elseif id == "exit" then quit()
    elseif id == "cut" then
        arcadeos.setClipboard(lines[cy] .. "\n")
        if #lines > 1 then table.remove(lines, cy) else lines[1] = "" end
        cx = 1
        dirty = true
    elseif id == "copy" then arcadeos.setClipboard(lines[cy] .. "\n")
    elseif id == "paste" then
        local clip = arcadeos.getClipboard()
        if clip then insert(clip) end
    elseif id == "time" then
        insert(textutils.formatTime(os.time("local"), false) .. " " .. os.date("%Y-%m-%d"))
    elseif id == "find" then find(false)
    elseif id == "findnext" then find(true)
    end
    clampCursor()
end

arcadeos.setMenus({
    { label = "File", items = {
        { id = "new", label = "New" }, { id = "open", label = "Open..." },
        { id = "save", label = "Save" }, { id = "saveas", label = "Save As..." },
        "-", { id = "exit", label = "Exit" },
    } },
    { label = "Edit", items = {
        { id = "cut", label = "Cut Line" }, { id = "copy", label = "Copy Line" }, { id = "paste", label = "Paste" },
        "-", { id = "time", label = "Time/Date" },
    } },
    { label = "Search", items = {
        { id = "find", label = "Find..." }, { id = "findnext", label = "Find Next" },
    } },
})

if args[1] and fs.exists(args[1]) then load(args[1]) else
    if args[1] then path = args[1] end
    setTitle()
end

local function handle(ev)
    local name = ev[1]
    if name == "arcadeos_menu" then
        onMenu(ev[2])
    elseif name == "terminate" then
        quit()
    elseif name == "char" then
        insert(ev[2])
    elseif name == "paste" then
        insert(ev[2])
    elseif name == "key_up" and (ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl) then
        ctrl = false
    elseif name == "key" then
        local k = ev[2]
        local _, h = term.getSize()
        if k == keys.leftCtrl or k == keys.rightCtrl then ctrl = true
        elseif ctrl and k == keys.s then save()
        elseif ctrl and k == keys.o then onMenu("open")
        elseif ctrl and k == keys.n then onMenu("new")
        elseif ctrl and k == keys.f then onMenu("find")
        elseif k == keys.f3 then onMenu("findnext")
        elseif k == keys.f5 then onMenu("time")
        elseif k == keys.enter or k == keys.numPadEnter then insert("\n")
        elseif k == keys.tab then insert("  ")
        elseif k == keys.backspace then
            if cx > 1 then
                lines[cy] = lines[cy]:sub(1, cx - 2) .. lines[cy]:sub(cx)
                cx = cx - 1
                dirty = true
            elseif cy > 1 then
                cx = #lines[cy - 1] + 1
                lines[cy - 1] = lines[cy - 1] .. table.remove(lines, cy)
                cy = cy - 1
                dirty = true
            end
        elseif k == keys.delete then
            if cx <= #lines[cy] then
                lines[cy] = lines[cy]:sub(1, cx - 1) .. lines[cy]:sub(cx + 1)
                dirty = true
            elseif cy < #lines then
                lines[cy] = lines[cy] .. table.remove(lines, cy + 1)
                dirty = true
            end
        elseif k == keys.left then
            if cx > 1 then cx = cx - 1 elseif cy > 1 then cy = cy - 1; cx = #lines[cy] + 1 end
        elseif k == keys.right then
            if cx <= #lines[cy] then cx = cx + 1 elseif cy < #lines then cy = cy + 1; cx = 1 end
        elseif k == keys.up then cy = cy - 1
        elseif k == keys.down then cy = cy + 1
        elseif k == keys.home then cx = 1
        elseif k == keys["end"] then cx = #lines[cy] + 1
        elseif k == keys.pageUp then cy = cy - (h - 1)
        elseif k == keys.pageDown then cy = cy + (h - 1)
        end
        clampCursor()
    elseif name == "mouse_click" then
        local w, h = term.getSize()
        if ev[3] == w then
            local nt = ui.scrollClick(w, 1, h, sy + 1, #lines + h - 1, h, ev[3], ev[4])
            if nt then sy = nt - 1; cy = math.max(sy + 1, math.min(cy, sy + h)) end
        else
            cy = sy + ev[4]
            cx = sx + ev[3]
        end
        clampCursor()
    elseif name == "mouse_scroll" then
        local _, h = term.getSize()
        sy = math.max(0, math.min(#lines - 1, sy + ev[2] * 3))
        cy = math.max(sy + 1, math.min(cy, sy + h))
        clampCursor()
    end
end

local ok, err = pcall(function()
    while true do
        draw()
        handle({ os.pullEventRaw() })
    end
end)
if not ok and err ~= "__notepad_exit" then error(err, 0) end
