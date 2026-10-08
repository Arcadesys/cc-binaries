-- turtleos/lib/ui.lua
-- Small drawing kit sized for the 39x13 turtle screen. Uses colour on
-- advanced turtles and greys on basic ones.

local ui = {}

local colour = term.isColour and term.isColour()

ui.theme = colour and {
    bg = colors.black, fg = colors.white, dim = colors.lightGray,
    barBg = colors.green, barFg = colors.white,
    selBg = colors.lime, selFg = colors.black,
    accent = colors.yellow, good = colors.lime, bad = colors.red,
} or {
    bg = colors.black, fg = colors.white, dim = colors.lightGray,
    barBg = colors.gray, barFg = colors.white,
    selBg = colors.white, selFg = colors.black,
    accent = colors.white, good = colors.white, bad = colors.white,
}

local T = ui.theme

function ui.size()
    return term.getSize()
end

function ui.clear()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    term.setCursorPos(1, 1)
end

-- Text clipped or padded to width w.
function ui.fit(text, w)
    text = tostring(text)
    if #text > w then return text:sub(1, math.max(0, w - 1)) .. "~" end
    return text .. string.rep(" ", w - #text)
end

function ui.write(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
end

-- Full-width bar with left and right text.
function ui.bar(y, left, right)
    local w = ui.size()
    right = right or ""
    local line = ui.fit(" " .. left, w - #right - 1) .. right .. " "
    ui.write(1, y, line:sub(1, w), T.barFg, T.barBg)
end

function ui.fuelText()
    local f = turtle and turtle.getFuelLevel() or 0
    if f == "unlimited" then return "Fuel inf" end
    return "Fuel " .. f
end

-- Word-wrap text into lines of width w.
function ui.wrap(text, w)
    local lines = {}
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            if line == "" then
                line = word
            elseif #line + 1 + #word <= w then
                line = line .. " " .. word
            else
                lines[#lines + 1] = line
                line = word
            end
            while #line > w do
                lines[#lines + 1] = line:sub(1, w)
                line = line:sub(w + 1)
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- A selectable row. `right` is drawn right-aligned (option values, hints).
function ui.row(y, text, selected, right, dim)
    local w = ui.size()
    right = right or ""
    local body = ui.fit((selected and "> " or "  ") .. text, w - #right - 1) .. right .. " "
    if selected then
        ui.write(1, y, body, T.selFg, T.selBg)
    else
        ui.write(1, y, body, dim and T.dim or T.fg, T.bg)
    end
end

-- Scrollable list of `items` ({ label=, right=, dim=, separator= }) between
-- rows top..bottom. Returns the rows used, keyed by item index, for clicks.
function ui.list(items, selected, top, bottom)
    local visible = bottom - top + 1
    local first = 1
    if selected > visible then first = selected - visible + 1 end
    local rows = {}
    for i = 0, visible - 1 do
        local idx = first + i
        local item = items[idx]
        local y = top + i
        if not item then
            ui.write(1, y, string.rep(" ", (ui.size())))
        elseif item.separator then
            ui.write(1, y, ui.fit("  " .. (item.label or ""), (ui.size())), T.dim)
        else
            ui.row(y, item.label, idx == selected, item.right, item.dim)
            rows[y] = idx
        end
    end
    if first > 1 then ui.write((ui.size()), top, "^", T.dim) end
    if first + visible - 1 < #items then ui.write((ui.size()), bottom, "v", T.dim) end
    return rows
end

-- Ask for a line of text on row y. Returns the text, or nil if left empty.
function ui.prompt(y, label, default)
    local w = ui.size()
    ui.write(1, y, string.rep(" ", w), T.fg, T.bg)
    ui.write(1, y, label .. ": ", T.accent)
    term.setCursorBlink(true)
    local text = read(nil, nil, nil, default and tostring(default) or nil)
    term.setCursorBlink(false)
    if text == "" then return nil end
    return text
end

-- Show a block of text with a title until a key is pressed (pages if long).
function ui.page(title, lines)
    local w, h = ui.size()
    local wrapped = {}
    for _, line in ipairs(lines) do
        for _, l in ipairs(ui.wrap(line, w - 2)) do wrapped[#wrapped + 1] = l end
    end
    local per = h - 3
    local top = 1
    while true do
        ui.clear()
        ui.bar(1, title, ui.fuelText())
        for i = 0, per - 1 do
            local l = wrapped[top + i]
            if l then ui.write(2, 2 + i, l) end
        end
        local more = top + per <= #wrapped
        ui.bar(h, more and "Down: more  Enter: back" or "Enter: back")
        local ev, k = os.pullEvent()
        if ev == "key" then
            if k == keys.down and more then
                top = top + 1
            elseif k == keys.up and top > 1 then
                top = top - 1
            elseif k == keys.enter or k == keys.backspace or k == keys.q then
                return
            end
        elseif ev == "mouse_click" then
            return
        end
    end
end

return ui
