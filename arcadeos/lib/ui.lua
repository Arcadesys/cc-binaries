-- Widgets for ArcadeOS apps. Everything draws on term.current() (the app's window).
local ui = {}

local function roles()
    return arcadeos and arcadeos.theme().role or {
        window = colors.white, text = colors.black, select = colors.black, selectText = colors.white,
        scroll = colors.lightGray, scrollThumb = colors.gray, titleActive = colors.blue,
        titleActiveText = colors.white, button = colors.white, buttonText = colors.black,
        buttonDefault = colors.blue, buttonDefaultText = colors.white, shadow = colors.gray,
        menuDisabled = colors.lightGray,
    }
end
ui.roles = roles

function ui.now() return os.epoch("utc") end

function ui.fill(x, y, w, h, bg)
    if w <= 0 or h <= 0 then return end
    local t = term.current()
    t.setBackgroundColor(bg)
    local line = (" "):rep(w)
    for yy = y, y + h - 1 do
        t.setCursorPos(x, yy)
        t.write(line)
    end
end

function ui.text(x, y, s, fg, bg, maxw)
    local t = term.current()
    s = tostring(s)
    if maxw and #s > maxw then s = s:sub(1, math.max(0, maxw)) end
    t.setCursorPos(x, y)
    if fg then t.setTextColor(fg) end
    if bg then t.setBackgroundColor(bg) end
    t.write(s)
end

function ui.pad(s, w)
    s = tostring(s)
    if #s >= w then return s:sub(1, w) end
    return s .. (" "):rep(w - #s)
end

function ui.center(y, s, fg, bg, x, w)
    local tw = term.getSize()
    x, w = x or 1, w or tw
    s = tostring(s):sub(1, w)
    ui.text(x + math.floor((w - #s) / 2), y, s, fg, bg)
end

function ui.inRect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + (r.h or 1)
end

function ui.button(x, y, label, isDefault)
    local R = roles()
    local s = " " .. label .. " "
    ui.text(x, y, s, isDefault and R.buttonDefaultText or R.buttonText,
        isDefault and R.buttonDefault or R.scroll)
    return { x = x, y = y, w = #s, h = 1 }
end

function ui.wrap(text, width)
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
    while #lines > 1 and lines[#lines] == "" do lines[#lines] = nil end
    return lines
end

--------------------------------------------------------------------------
-- Vertical scroll bar: arrows at both ends, proportional thumb.

function ui.scrollbar(x, y, h, top, total, visible)
    local R = roles()
    ui.text(x, y, "\30", R.text, R.scroll)
    ui.text(x, y + h - 1, "\31", R.text, R.scroll)
    local track = h - 2
    if track <= 0 then return end
    ui.fill(x, y + 1, 1, track, R.scroll)
    if total > visible then
        local size = math.max(1, math.floor(track * visible / total))
        local maxTop = total - visible
        local pos = math.floor((track - size) * (top - 1) / math.max(1, maxTop) + 0.5)
        ui.fill(x, y + 1 + pos, 1, size, R.scrollThumb)
    end
end

-- Returns the new top index for a click on the scroll bar, or nil.
function ui.scrollClick(x, y, h, top, total, visible, mx, my)
    if mx ~= x or my < y or my >= y + h then return nil end
    local maxTop = math.max(1, total - visible + 1)
    if my == y then return math.max(1, top - 1) end
    if my == y + h - 1 then return math.min(maxTop, top + 1) end
    local frac = (my - y - 1) / math.max(1, h - 3)
    return math.max(1, math.min(maxTop, math.floor(frac * (maxTop - 1) + 1.5)))
end

--------------------------------------------------------------------------
-- List box with selection, keyboard navigation, double-click, scroll bar.
-- Items: { label = "...", right = "...", fg = color, header = bool, value = any }

local List = {}
List.__index = List

function ui.list(items)
    return setmetatable({ items = items or {}, sel = 1, top = 1, x = 1, y = 1, w = 10, h = 5 }, List)
end

function List:place(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
    self:clamp()
end

function List:selectable(i)
    local it = self.items[i]
    return it and not it.header
end

function List:clamp()
    local n = #self.items
    if n == 0 then self.sel, self.top = 0, 1; return end
    self.sel = math.max(1, math.min(self.sel, n))
    if not self:selectable(self.sel) then self:move(1, true) end
    if not self:selectable(self.sel) then self:move(-1, true) end
    local maxTop = math.max(1, n - self.h + 1)
    self.top = math.max(1, math.min(self.top, maxTop))
end

function List:setItems(items, keepSel)
    self.items = items
    if not keepSel then self.sel, self.top = 1, 1 end
    self:clamp()
end

function List:selected()
    return self.items[self.sel]
end

function List:ensureVisible()
    if self.sel < self.top then self.top = self.sel end
    if self.sel > self.top + self.h - 1 then self.top = self.sel - self.h + 1 end
    self:clamp2()
end

function List:clamp2()
    local maxTop = math.max(1, #self.items - self.h + 1)
    self.top = math.max(1, math.min(self.top, maxTop))
end

function List:move(delta, quiet)
    local n = #self.items
    if n == 0 then return end
    local dir = delta < 0 and -1 or 1
    local remaining = math.max(1, math.abs(delta))
    local i = self.sel
    while remaining > 0 do
        local j = i + dir
        while j >= 1 and j <= n and not self:selectable(j) do j = j + dir end
        if j < 1 or j > n then break end
        i, remaining = j, remaining - 1
    end
    self.sel = i
    if not quiet then self:ensureVisible() end
end

function List:draw()
    local R = roles()
    local bodyW = self.w - 1
    for row = 1, self.h do
        local i = self.top + row - 1
        local it = self.items[i]
        local y = self.y + row - 1
        if it then
            local hi = i == self.sel and not it.header
            local fg = hi and R.selectText or (it.fg or R.text)
            local bg = hi and R.select or R.window
            local label = it.label
            local right = it.right and (" " .. it.right) or ""
            if #label + #right > bodyW then right = "" end
            ui.text(self.x, y, ui.pad(label, bodyW - #right) .. right, fg, bg)
        else
            ui.fill(self.x, y, bodyW, 1, R.window)
        end
    end
    ui.scrollbar(self.x + self.w - 1, self.y, self.h, self.top, #self.items, self.h)
end

-- Returns ("select"|"activate", item) or nil. Caller redraws.
function List:handle(ev, a, b, c)
    if ev == "mouse_click" or ev == "mouse_drag" then
        local mx, my = b, c
        local sx = self.x + self.w - 1
        local nt = ui.scrollClick(sx, self.y, self.h, self.top, #self.items, self.h, mx, my)
        if nt then self.top = nt; return "scroll" end
        if mx >= self.x and mx < sx and my >= self.y and my < self.y + self.h then
            local i = self.top + my - self.y
            if self:selectable(i) then
                local now = ui.now()
                local double = ev == "mouse_click" and i == self.sel and self.lastClick and now - self.lastClick < 500
                self.sel = i
                self.lastClick = ev == "mouse_click" and now or self.lastClick
                if double then self.lastClick = nil; return "activate", self.items[i] end
                return "select", self.items[i]
            end
        end
    elseif ev == "mouse_scroll" then
        self.top = self.top + a
        self:clamp2()
        return "scroll"
    elseif ev == "key" then
        local k = a
        if k == keys.up then self:move(-1)
        elseif k == keys.down then self:move(1)
        elseif k == keys.pageUp then self:move(-(self.h - 1))
        elseif k == keys.pageDown then self:move(self.h - 1)
        elseif k == keys.home then self.sel = 1; self:clamp(); self:ensureVisible()
        elseif k == keys["end"] then self.sel = #self.items; self:clamp(); self:ensureVisible()
        elseif k == keys.enter or k == keys.numPadEnter then
            return "activate", self.items[self.sel]
        else return nil end
        return "select", self.items[self.sel]
    end
end

--------------------------------------------------------------------------
-- Single-line text field.

local Field = {}
Field.__index = Field

function ui.field(text)
    text = text or ""
    return setmetatable({ text = text, cursor = #text + 1, scroll = 1, x = 1, y = 1, w = 10 }, Field)
end

function Field:place(x, y, w) self.x, self.y, self.w = x, y, w end

function Field:draw(focused)
    local R = roles()
    if self.cursor - self.scroll >= self.w then self.scroll = self.cursor - self.w + 1 end
    if self.cursor < self.scroll then self.scroll = self.cursor end
    local vis = self.text:sub(self.scroll, self.scroll + self.w - 1)
    ui.text(self.x, self.y, ui.pad(vis, self.w), R.text, R.scroll)
    if focused then
        local t = term.current()
        t.setCursorPos(self.x + self.cursor - self.scroll, self.y)
        t.setTextColor(R.text)
        t.setCursorBlink(true)
    end
end

function Field:handle(ev, a, b, c)
    if ev == "char" then
        self.text = self.text:sub(1, self.cursor - 1) .. a .. self.text:sub(self.cursor)
        self.cursor = self.cursor + 1
        return "change"
    elseif ev == "paste" then
        a = a:gsub("[\r\n]", "")
        self.text = self.text:sub(1, self.cursor - 1) .. a .. self.text:sub(self.cursor)
        self.cursor = self.cursor + #a
        return "change"
    elseif ev == "key" then
        if a == keys.backspace and self.cursor > 1 then
            self.text = self.text:sub(1, self.cursor - 2) .. self.text:sub(self.cursor)
            self.cursor = self.cursor - 1
            return "change"
        elseif a == keys.delete then
            self.text = self.text:sub(1, self.cursor - 1) .. self.text:sub(self.cursor + 1)
            return "change"
        elseif a == keys.left then self.cursor = math.max(1, self.cursor - 1)
        elseif a == keys.right then self.cursor = math.min(#self.text + 1, self.cursor + 1)
        elseif a == keys.home then self.cursor = 1
        elseif a == keys["end"] then self.cursor = #self.text + 1
        elseif a == keys.enter or a == keys.numPadEnter then return "enter"
        elseif a == keys.escape then return "escape"
        end
        return "move"
    elseif ev == "mouse_click" and c == self.y and b >= self.x and b < self.x + self.w then
        self.cursor = math.min(#self.text + 1, self.scroll + b - self.x)
        return "move"
    end
end

function Field:set(text)
    self.text = text or ""
    self.cursor = #self.text + 1
    self.scroll = 1
end

return ui
