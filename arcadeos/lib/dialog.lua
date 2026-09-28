-- Windows 1.0-style dialog boxes drawn inside the calling app's window.
-- Each dialog snapshots the window and restores it when dismissed.
local ui = arcadeos.lib("ui")

local dialog = {}

local function snapshot()
    local t = term.current()
    local w, h = t.getSize()
    local snap = { lines = {}, cx = 0, cy = 0 }
    snap.cx, snap.cy = t.getCursorPos()
    snap.fg, snap.bg = t.getTextColor(), t.getBackgroundColor()
    snap.blink = t.getCursorBlink and t.getCursorBlink() or false
    if t.getLine then
        for y = 1, h do snap.lines[y] = { t.getLine(y) } end
    end
    return snap
end

local function restore(snap)
    local t = term.current()
    for y, line in ipairs(snap.lines) do
        t.setCursorPos(1, y)
        t.blit(line[1], line[2], line[3])
    end
    t.setTextColor(snap.fg)
    t.setBackgroundColor(snap.bg)
    t.setCursorPos(snap.cx, snap.cy)
    t.setCursorBlink(snap.blink)
end

-- Generic dialog: spec = { title, text, buttons, field = default|nil, list = items|nil, listHeight }
-- Returns buttonIndex, fieldText, listItem. Escape returns the last button.
local function run(spec)
    local R = ui.roles()
    local snap = snapshot()
    local t = term.current()
    local W, H = t.getSize()
    local buttons = spec.buttons or { "OK" }

    local bw = 0
    for _, b in ipairs(buttons) do bw = bw + #b + 3 end
    local w = math.min(W, math.max(22, #spec.title + 4, bw + 3, spec.width or 0))
    local lines = ui.wrap(spec.text or "", w - 4)
    if spec.text == nil or spec.text == "" then lines = {} end
    local listH = 0
    if spec.list then listH = math.max(3, math.min(spec.listHeight or 6, H - #lines - 7)) end
    local h = 3 + #lines + (spec.field and 2 or 0) + (spec.list and listH + 1 or 0) + 1
    h = math.min(h, H)
    local x = math.floor((W - w) / 2) + 1
    local y = math.max(1, math.floor((H - h) / 2) + 1)

    local fieldY = y + 1 + #lines + 1
    local listY = fieldY + (spec.field and 2 or 0)
    local field = spec.field and ui.field(spec.field)
    local list = spec.list and ui.list(spec.list)
    if field then field:place(x + 2, fieldY, w - 4) end
    if list then list:place(x + 2, listY, w - 4, listH) end
    local focus = field and "field" or (list and "list" or "buttons")
    local sel = 1
    local rects = {}

    local nLines = #lines
    local function draw()
        lines = ui.wrap(spec.text or "", w - 4)
        ui.fill(x, y, w, h, R.window)
        ui.fill(x, y, w, 1, R.titleActive)
        ui.center(y, spec.title, R.titleActiveText, R.titleActive, x, w)
        for i = 1, nLines do ui.text(x + 2, y + 1 + i, lines[i] or "", R.text, R.window, w - 4) end
        if list then list:draw() end
        local bx = x + math.floor((w - bw) / 2) + 1
        for i, b in ipairs(buttons) do
            rects[i] = ui.button(bx, y + h - 2, b, i == sel)
            bx = bx + #b + 3
        end
        t.setCursorBlink(false)
        if field then field:draw(focus == "field") end
    end

    local result
    while not result do
        draw()
        local ev = { os.pullEvent() }
        local name = ev[1]
        if name == "key" and ev[2] == keys.tab then
            local order = {}
            if field then order[#order + 1] = "field" end
            if list then order[#order + 1] = "list" end
            order[#order + 1] = "buttons"
            for i, f in ipairs(order) do
                if f == focus then focus = order[i % #order + 1]; break end
            end
        elseif name == "key" and ev[2] == keys.escape then
            result = #buttons
        elseif name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            local hitButton
            for i, r in ipairs(rects) do if ui.inRect(r, mx, my) then hitButton = i end end
            if hitButton then
                result = hitButton
            elseif field and my == fieldY then
                focus = "field"
                field:handle(name, ev[2], mx, my)
            elseif list and ui.inRect(list, mx, my) then
                focus = "list"
                local what, item = list:handle(name, ev[2], mx, my)
                if spec.onList then
                    if spec.onList(what, item, list, field) then result = 1 end
                elseif what == "activate" then
                    result = 1
                end
            end
        elseif name == "mouse_scroll" and list then
            list:handle(name, ev[2], ev[3], ev[4])
        elseif focus == "field" and (name == "char" or name == "key" or name == "paste") then
            local what = field:handle(name, ev[2])
            if what == "enter" then result = 1 end
        elseif focus == "list" and name == "key" then
            local what, item = list:handle(name, ev[2])
            if spec.onList then
                if spec.onList(what, item, list, field) then result = 1 end
            elseif what == "activate" then
                result = 1
            end
        elseif focus == "buttons" and name == "key" then
            if ev[2] == keys.left then sel = (sel - 2) % #buttons + 1
            elseif ev[2] == keys.right then sel = sel % #buttons + 1
            elseif ev[2] == keys.enter or ev[2] == keys.space then result = sel end
        elseif name == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) then
            result = sel
        elseif name == "term_resize" then
            restore(snap)
            return run(spec)
        end
        if spec.check and result then
            local ok = spec.check(result, field and field.text, list and list:selected(), list, field)
            if ok == false then result = nil end
        end
    end
    restore(snap)
    return result, field and field.text, list and list:selected()
end
dialog.run = run

function dialog.message(title, text, buttons)
    return (run({ title = title, text = text, buttons = buttons or { "OK" } }))
end

function dialog.alert(title, text)
    run({ title = title, text = text, buttons = { "OK" } })
end

function dialog.confirm(title, text, yes, no)
    return run({ title = title, text = text, buttons = { yes or "OK", no or "Cancel" } }) == 1
end

-- Returns "yes", "no" or "cancel".
function dialog.yesNoCancel(title, text)
    local i = run({ title = title, text = text, buttons = { "Yes", "No", "Cancel" } })
    return ({ "yes", "no", "cancel" })[i]
end

function dialog.prompt(title, label, default)
    local i, text = run({ title = title, text = label, field = default or "", buttons = { "OK", "Cancel" } })
    if i == 1 then return text end
    return nil
end

--------------------------------------------------------------------------
-- File Open / Save As

local function listDir(dir, filter)
    local items = {}
    if dir ~= "" then items[#items + 1] = { label = "..", value = "..", dir = true } end
    local ok, names = pcall(fs.list, "/" .. dir)
    if not ok then names = {} end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, n in ipairs(names) do
        if fs.isDir(fs.combine(dir, n)) then items[#items + 1] = { label = "[" .. n .. "]", value = n, dir = true } end
    end
    for _, n in ipairs(names) do
        local p = fs.combine(dir, n)
        if not fs.isDir(p) and (not filter or n:match(filter)) then
            items[#items + 1] = { label = n, value = n }
        end
    end
    return items
end

local function filePicker(title, opts, save)
    opts = opts or {}
    local dir = fs.combine(opts.dir or "home", "")
    local chosen
    local spec
    spec = {
        title = title, width = 30, listHeight = 7,
        text = "/" .. dir,
        field = opts.name or "",
        list = listDir(dir, opts.filter),
        buttons = { save and "Save" or "Open", "Cancel" },
    }
    spec.onList = function(what, item, list, field)
        if not item then return end
        if item.dir and what == "activate" then
            dir = item.value == ".." and fs.getDir(dir) or fs.combine(dir, item.value)
            if dir == ".." then dir = "" end
            list:setItems(listDir(dir, opts.filter))
            spec.text = "/" .. dir
        elseif not item.dir then
            field:set(item.value)
            if what == "activate" then chosen = true; return true end
        end
    end
    spec.check = function(result, text, _, list, field)
        if result ~= 1 then return true end
        if chosen then return true end
        if not text or text == "" then return false end
        local path = text:sub(1, 1) == "/" and fs.combine(text, "") or fs.combine(dir, text)
        if fs.isDir(path) then
            dir = path
            list:setItems(listDir(dir, opts.filter))
            spec.text = "/" .. dir
            field:set("")
            return false
        end
        if not save and not fs.exists(path) then return false end
        return true
    end
    while true do
        chosen = nil
        local i, text = run(spec)
        if i ~= 1 then return nil end
        if text and text ~= "" then
            local path = text:sub(1, 1) == "/" and fs.combine(text, "") or fs.combine(dir, text)
            if fs.isDir(path) then
                dir = path
                spec.list = listDir(dir, opts.filter)
                spec.text = "/" .. dir
                spec.field = ""
            else
                if save and opts.ext and not path:match("%.[^/]+$") then path = path .. "." .. opts.ext end
                if save and fs.exists(path) and not dialog.confirm(title, fs.getName(path) .. " already exists. Replace it?") then
                    spec.field = text
                else
                    return "/" .. path
                end
            end
        end
    end
end

-- opts: { dir = "home", filter = "%.txt$" }
function dialog.openFile(opts) return filePicker("Open", opts, false) end

-- opts: { dir = "home", name = "untitled.txt", ext = "txt" }
function dialog.saveFile(opts) return filePicker("Save As", opts, true) end

return dialog
