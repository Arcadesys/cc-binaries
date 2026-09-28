-- Kernel-side drawing: title bars, menu bars, dropdowns, icon strip, modal boxes.
local theme = require("sys.theme")
local R = theme.role

local chrome = {}

local function fit(s, w)
    s = tostring(s or "")
    if #s > w then return s:sub(1, math.max(0, w)) end
    return s
end
chrome.fit = fit

local function fill(t, x, y, w, h, bg)
    t.setBackgroundColor(bg)
    local line = (" "):rep(w)
    for yy = y, y + h - 1 do
        t.setCursorPos(x, yy)
        t.write(line)
    end
end
chrome.fill = fill

local function put(t, x, y, s, fg, bg)
    t.setCursorPos(x, y)
    if fg then t.setTextColor(fg) end
    if bg then t.setBackgroundColor(bg) end
    t.write(s)
end
chrome.put = put

-- Title bar: [-] system box, centered title, iconize and zoom buttons.
function chrome.titleHit(r, x)
    local xr = r.x + r.w - 1
    if x <= r.x + 2 then return "system" end
    if r.w >= 12 then
        if x >= xr - 3 and x <= xr - 2 then return "iconize" end
        if x >= xr - 1 then return "zoom" end
    end
    return "title"
end

function chrome.drawTitle(t, r, title, active, zoomed)
    local bg = active and R.titleActive or R.titleInactive
    local fg = active and R.titleActiveText or R.titleInactiveText
    fill(t, r.x, r.y, r.w, 1, bg)
    put(t, r.x, r.y, "[-]", fg, bg)
    local right = 0
    if r.w >= 12 then
        right = 4
        local xr = r.x + r.w - 1
        put(t, xr - 3, r.y, " \25", R.menuText, R.menuBg)
        put(t, xr - 1, r.y, zoomed and " \18" or " \24", R.menuText, R.menuBg)
    end
    local avail = r.w - 4 - right
    local s = fit(title, avail)
    local tx = r.x + 3 + math.floor((avail - #s) / 2) + 1
    put(t, tx, r.y, s, fg, bg)
end

-- Menu bar: returns spans {x1, x2, index} for hit testing.
function chrome.menuSpans(menus, r)
    local spans, x = {}, r.x + 1
    for i, m in ipairs(menus or {}) do
        local w = #m.label + 2
        if x + w - 1 > r.x + r.w - 1 then break end
        spans[#spans + 1] = { x1 = x, x2 = x + w - 1, index = i }
        x = x + w
    end
    return spans
end

function chrome.drawMenuBar(t, r, menus, openIndex)
    fill(t, r.x, r.y, r.w, 1, R.menuBg)
    for _, sp in ipairs(chrome.menuSpans(menus, r)) do
        local hi = sp.index == openIndex
        put(t, sp.x1, r.y, " " .. menus[sp.index].label .. " ",
            hi and R.menuHiText or R.menuText, hi and R.menuHiBg or R.menuBg)
    end
end

-- Dropdown geometry, clamped to the screen.
function chrome.dropdownRect(items, ax, ay, W, H)
    local w = 4
    for _, it in ipairs(items) do
        if type(it) == "table" then w = math.max(w, #it.label + 4) end
    end
    w = math.min(w, W - 1)
    local h = math.min(#items, H - ay)
    local x = math.max(1, math.min(ax, W - w))
    return { x = x, y = ay, w = w, h = h }
end

function chrome.drawDropdown(t, dr, items, sel, W, H)
    for i = 1, dr.h do
        local it = items[i]
        local y = dr.y + i - 1
        if it == "-" then
            put(t, dr.x, y, ("\140"):rep(dr.w), R.menuDisabled, R.menuBg)
        else
            local hi = i == sel and not it.disabled
            local fg = it.disabled and R.menuDisabled or (hi and R.menuHiText or R.menuText)
            local bg = hi and R.menuHiBg or R.menuBg
            local mark = it.checked and "\7" or " "
            put(t, dr.x, y, fit(mark .. " " .. it.label .. (" "):rep(dr.w), dr.w), fg, bg)
        end
    end
    -- Shadow on the right and bottom edges.
    if dr.x + dr.w <= W then fill(t, dr.x + dr.w, dr.y + 1, 1, dr.h, R.shadow) end
    if dr.y + dr.h <= H then fill(t, dr.x + 1, dr.y + dr.h, dr.w, 1, R.shadow) end
end

local function inside(r, x, y)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function chrome.dropdownHit(dr, items, x, y)
    if not inside(dr, x, y) then return nil end
    local i = y - dr.y + 1
    local it = items[i]
    if it == "-" or (type(it) == "table" and it.disabled) then return false end
    return i
end

-- Icon strip along the bottom two rows.
function chrome.drawIcon(t, slot, glyph, label, active)
    local bg = active and R.iconActive or R.iconBg
    local fg = active and R.iconActiveText or R.iconText
    local g = fit(glyph or "?", slot.w - 2)
    local gx = slot.x + 1
    fill(t, gx, slot.y, slot.w - 2, 1, bg)
    put(t, gx + math.floor((slot.w - 2 - #g) / 2), slot.y, g, fg, bg)
    local l = fit(label, slot.w)
    put(t, slot.x + math.floor((slot.w - #l) / 2), slot.y + 1, l, R.desktopText, R.desktop)
end

-- Kernel-modal message box, centered. Returns button rects for hit testing.
function chrome.wrap(text, width)
    local lines = {}
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            while #word > width do
                if #line > 0 then lines[#lines + 1] = line; line = "" end
                lines[#lines + 1] = word:sub(1, width)
                word = word:sub(width + 1)
            end
            if #line == 0 then line = word
            elseif #line + 1 + #word <= width then line = line .. " " .. word
            else lines[#lines + 1] = line; line = word end
        end
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    return lines
end

function chrome.boxLayout(W, H, title, text, buttons)
    local bw = 0
    for _, b in ipairs(buttons) do bw = bw + #b + 4 end
    local w = math.min(W - 2, math.max(24, #title + 6, bw + 2))
    local lines = chrome.wrap(text, w - 4)
    local maxLines = H - 7
    while #lines > maxLines do lines[#lines] = nil end
    local h = #lines + 5
    local x = math.floor((W - w) / 2) + 1
    local y = math.floor((H - h) / 2) + 1
    local rects, bx = {}, x + math.floor((w - bw) / 2) + 1
    for i, b in ipairs(buttons) do
        rects[i] = { x = bx, y = y + h - 2, w = #b + 2, h = 1, label = b }
        bx = bx + #b + 4
    end
    return { x = x, y = y, w = w, h = h, lines = lines, buttons = rects, title = title }
end

function chrome.drawBox(t, L, sel)
    fill(t, L.x + 1, L.y + 1, L.w, L.h, R.shadow)
    fill(t, L.x, L.y, L.w, L.h, R.window)
    fill(t, L.x, L.y, L.w, 1, R.titleActive)
    local tt = fit(L.title, L.w - 2)
    put(t, L.x + math.floor((L.w - #tt) / 2), L.y, tt, R.titleActiveText, R.titleActive)
    for i, line in ipairs(L.lines) do
        put(t, L.x + 2, L.y + 1 + i, line, R.text, R.window)
    end
    for i, b in ipairs(L.buttons) do
        local def = i == sel
        put(t, b.x - 1, b.y, def and "\16" or " ", R.text, R.window)
        put(t, b.x, b.y, " " .. b.label .. " ",
            def and R.buttonDefaultText or R.buttonText, def and R.buttonDefault or R.scroll)
        put(t, b.x + b.w, b.y, def and "\17" or " ", R.text, R.window)
    end
end

return chrome
