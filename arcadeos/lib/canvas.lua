-- Subpixel canvas: 2x3 pixels per character cell using CC's drawing characters.
-- Subpixels are square (3x3 screen px each), so circles come out round.
local canvas = {}
local HEX = {}
for i = 0, 15 do HEX[2 ^ i] = ("0123456789abcdef"):sub(i + 1, i + 1) end

local C = {}
C.__index = C

function canvas.new(cw, ch)
    local c = setmetatable({ cw = cw, ch = ch, pw = cw * 2, ph = ch * 3, px = {} }, C)
    return c
end

function C:clear() self.px = {} end

function C:set(x, y, color)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x < 1 or y < 1 or x > self.pw or y > self.ph then return end
    self.px[(y - 1) * self.pw + x] = color
end

function C:get(x, y)
    return self.px[(y - 1) * self.pw + x]
end

function C:line(x0, y0, x1, y1, color)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(math.abs(dx), math.abs(dy), 1)
    for i = 0, steps do
        self:set(x0 + dx * i / steps, y0 + dy * i / steps, color)
    end
end

function C:circle(cx, cy, r, color)
    local steps = math.max(16, math.floor(r * 8))
    for i = 0, steps - 1 do
        local a = 2 * math.pi * i / steps
        self:set(cx + r * math.cos(a), cy + r * math.sin(a), color)
    end
end

function C:disc(cx, cy, r, color)
    for y = math.floor(cy - r), math.ceil(cy + r) do
        for x = math.floor(cx - r), math.ceil(cx + r) do
            if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then self:set(x, y, color) end
        end
    end
end

-- Draw at cell (ox, oy) on the current terminal; bg fills unset pixels.
function C:draw(ox, oy, bg)
    local t = term.current()
    for cy = 1, self.ch do
        local text, fg, bgs = {}, {}, {}
        for cx = 1, self.cw do
            local x0, y0 = (cx - 1) * 2 + 1, (cy - 1) * 3 + 1
            local p = {
                self:get(x0, y0), self:get(x0 + 1, y0),
                self:get(x0, y0 + 1), self:get(x0 + 1, y0 + 1),
                self:get(x0, y0 + 2), self:get(x0 + 1, y0 + 2),
            }
            local counts, best, bestN = {}, nil, 0
            for i = 1, 6 do
                local c = p[i]
                if c and c ~= bg then
                    counts[c] = (counts[c] or 0) + 1
                    if counts[c] > bestN then best, bestN = c, counts[c] end
                end
            end
            local fgc = best or bg
            local bits = 0
            for i = 1, 6 do
                if p[i] == fgc and fgc ~= bg then bits = bits + 2 ^ (i - 1) end
            end
            local cellFg, cellBg = fgc, bg
            if bits >= 32 then
                bits = 63 - bits
                cellFg, cellBg = bg, fgc
            end
            text[cx] = string.char(128 + bits)
            fg[cx] = HEX[cellFg]
            bgs[cx] = HEX[cellBg]
        end
        t.setCursorPos(ox, oy + cy - 1)
        t.blit(table.concat(text), table.concat(fg), table.concat(bgs))
    end
end

return canvas
