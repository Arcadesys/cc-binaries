-- Pure layout math for Windows 1.0-style tiling. No drawing, no state.
local wm = {}

wm.ICON_ROWS = 2
wm.MIN_W, wm.MIN_H = 51, 19

function wm.isSmall(W, H)
    return W < wm.MIN_W or H < wm.MIN_H
end

function wm.maxTiles(W, H)
    return wm.isSmall(W, H) and 1 or 4
end

-- Rects for n tiled windows inside the tile area (rows 1..H-ICON_ROWS).
-- Columns are separated by a one-column divider; stacked windows are
-- separated by their own title bars.
function wm.layout(n, W, H)
    local th = H - wm.ICON_ROWS
    if n <= 0 then return {} end
    if n == 1 or wm.isSmall(W, H) then
        return { { x = 1, y = 1, w = W, h = th } }
    end
    local lw = math.floor((W - 1) / 2)
    local rx, rw = lw + 2, W - lw - 1
    local th1 = math.floor(th / 2)
    local th2 = th - th1
    if n == 2 then
        return {
            { x = 1, y = 1, w = lw, h = th },
            { x = rx, y = 1, w = rw, h = th },
        }
    elseif n == 3 then
        return {
            { x = 1, y = 1, w = lw, h = th },
            { x = rx, y = 1, w = rw, h = th1 },
            { x = rx, y = 1 + th1, w = rw, h = th2 },
        }
    end
    return {
        { x = 1, y = 1, w = lw, h = th1 },
        { x = rx, y = 1, w = rw, h = th1 },
        { x = 1, y = 1 + th1, w = lw, h = th2 },
        { x = rx, y = 1 + th1, w = rw, h = th2 },
    }
end

function wm.dividers(n, W, H)
    if n < 2 or wm.isSmall(W, H) then return {} end
    local lw = math.floor((W - 1) / 2)
    return { { x = lw + 1, y = 1, w = 1, h = H - wm.ICON_ROWS } }
end

-- Split a frame rect into title row, optional menu row, and client rect.
function wm.frame(r, hasMenu, chrome)
    if not chrome then
        return { client = { x = r.x, y = r.y, w = r.w, h = r.h } }
    end
    local f = { title = { x = r.x, y = r.y, w = r.w } }
    local cy = r.y + 1
    if hasMenu then
        f.menu = { x = r.x, y = cy, w = r.w }
        cy = cy + 1
    end
    f.client = { x = r.x, y = cy, w = r.w, h = math.max(1, r.y + r.h - cy) }
    return f
end

function wm.contains(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + (r.h or 1)
end

-- Icon strip slots: each icon is ICON_W wide, laid out left to right.
wm.ICON_W = 9
function wm.iconSlots(n, W, H)
    local slots = {}
    local per = math.max(1, math.floor(W / wm.ICON_W))
    for i = 1, math.min(n, per) do
        slots[i] = { x = (i - 1) * wm.ICON_W + 1, y = H - 1, w = wm.ICON_W - 1, h = 2 }
    end
    return slots
end

return wm
