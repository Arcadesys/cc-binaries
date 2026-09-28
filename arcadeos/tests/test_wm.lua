local wm = require("sys.wm")

local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return {
    { "layout fills the tile area without overlap for 1-4 windows", function(T)
        local W, H = 51, 19
        for n = 1, 4 do
            local rects = wm.layout(n, W, H)
            T.eq(#rects, n, "rect count for " .. n)
            local area = 0
            for i, r in ipairs(rects) do
                T.ok(r.x >= 1 and r.y >= 1 and r.x + r.w - 1 <= W and r.y + r.h - 1 <= H - wm.ICON_ROWS,
                    "rect " .. i .. " inside tile area for n=" .. n)
                area = area + r.w * r.h
                for j = i + 1, #rects do T.ok(not overlaps(r, rects[j]), "overlap n=" .. n) end
            end
            local dividerArea = n >= 2 and (H - wm.ICON_ROWS) or 0
            T.eq(area + dividerArea, W * (H - wm.ICON_ROWS), "coverage n=" .. n)
        end
    end },
    { "two columns are 25 wide on a 51-wide screen", function(T)
        local r = wm.layout(2, 51, 19)
        T.eq(r[1].w, 25, "left")
        T.eq(r[2].w, 25, "right")
        T.eq(r[2].x, 27, "right x")
    end },
    { "small screens get one full tile", function(T)
        T.ok(wm.isSmall(39, 13), "turtle is small")
        T.ok(wm.isSmall(26, 20), "pocket is small")
        T.eq(wm.maxTiles(39, 13), 1, "max tiles")
        local r = wm.layout(3, 39, 13)
        T.eq(#r, 1, "one tile")
        T.eq(r[1].w, 39, "full width")
    end },
    { "frame splits title, menu, client", function(T)
        local f = wm.frame({ x = 1, y = 1, w = 25, h = 17 }, true, true)
        T.eq(f.title.y, 1, "title row")
        T.eq(f.menu.y, 2, "menu row")
        T.eq(f.client.y, 3, "client y")
        T.eq(f.client.h, 15, "client h")
        local full = wm.frame({ x = 1, y = 1, w = 51, h = 19 }, false, false)
        T.eq(full.client.h, 19, "full client h")
        T.ok(not full.title, "no title when chromeless")
    end },
}
