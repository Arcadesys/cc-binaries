-- Screenshot scenarios: each writes /results/<name>.screen.json for tools/render.py.
package.path = "/arcadeos/?.lua;/arcadeos/?/init.lua;/arcadeos/tests/?.lua;" .. package.path
local H = require("helpers")

local HEX = "0123456789abcdef"

local function dump(parent, name)
    local w, h = parent.getSize()
    local pal = {}
    for i = 0, 15 do
        pal[HEX:sub(i + 1, i + 1)] = colors.packRGB(parent.getPaletteColor(2 ^ i))
    end
    local lines = {}
    for y = 1, h do
        local text, fg, bg = parent.getLine(y)
        lines[y] = { text = { text:byte(1, -1) }, fg = fg, bg = bg }
    end
    local f = fs.open("/results/" .. name .. ".screen.json", "w")
    f.write(textutils.serializeJSON({ w = w, h = h, palette = pal, lines = lines }))
    f.close()
end

local function send(k, ...) H.send(k, ...) end
local function ctrl(k, key)
    send(k, "key", keys.leftCtrl, false)
    send(k, "key", key, false)
    send(k, "key_up", keys.leftCtrl)
end
local function clickMenu(k, p, label)
    local fr = k.frames[p]
    local chrome = require("sys.chrome")
    for _, sp in ipairs(chrome.menuSpans(p.menus, fr.menu)) do
        if p.menus[sp.index].label == label then send(k, "mouse_click", 1, sp.x1 + 1, fr.menu.y) end
    end
end

local SCENARIOS = {}
local ORDER = {}
local function scenario(name, fn) SCENARIOS[name] = fn; ORDER[#ORDER + 1] = name end

scenario("01-executive", function(k, parent)
    H.pump(k, 0.2)
    dump(parent, "01-executive")
end)

scenario("02-executive-menu", function(k, parent)
    H.pump(k, 0.2)
    clickMenu(k, k.focus, "File")
    dump(parent, "02-executive-menu")
end)

scenario("03-files", function(k, parent)
    H.pump(k, 0.2)
    clickMenu(k, k.focus, "View")
    send(k, "key", keys.down, false)
    send(k, "key", keys.enter, false)
    H.pump(k, 0.2)
    dump(parent, "03-files")
end)

scenario("04-tiled", function(k, parent)
    H.pump(k, 0.2)
    for _, id in ipairs(k.env.tileApps or { "terminal", "terminal", "terminal" }) do
        k:launch(id)
        H.pump(k, 0.2)
    end
    dump(parent, "04-tiled")
end)

scenario("05-exit-confirm", function(k, parent)
    H.pump(k, 0.2)
    k:close(k.focus)
    H.pump(k, 0.1)
    dump(parent, "05-exit-confirm")
end)

scenario("06-iconized", function(k, parent)
    H.pump(k, 0.2)
    k:launch("terminal")
    H.pump(k, 0.2)
    k:launch("terminal")
    H.pump(k, 0.2)
    k:iconize(k.focus)
    H.pump(k, 0.2)
    dump(parent, "06-iconized")
end)

scenario("07-accessories", function(k, parent)
    H.pump(k, 0.2)
    for _, id in ipairs({ "clock", "calculator", "notepad" }) do
        k:launch(id)
        H.pump(k, 0.3)
    end
    for _, c in ipairs({ "H", "e", "l", "l", "o", ",", " ", "W", "o", "r", "l", "d", "!" }) do send(k, "char", c) end
    H.pump(k, 1.2)
    dump(parent, "07-accessories")
end)

scenario("08-clock-zoomed", function(k, parent)
    H.pump(k, 0.2)
    k:launch("clock")
    H.pump(k, 0.3)
    k:toggleZoom(k.focus)
    H.pump(k, 1.2)
    dump(parent, "08-clock-zoomed")
end)

scenario("09-reversi", function(k, parent)
    H.pump(k, 0.2)
    k:launch("reversi")
    H.pump(k, 0.3)
    k:toggleZoom(k.focus)
    H.pump(k, 0.3)
    local p = k.focus
    local c = k.frames[p].client
    -- Play d3 (row 3, col 4): a legal opening move for black.
    local sw, sh = 2, 1
    if c.w >= 24 and c.h - 1 >= 16 then sw, sh = 3, 2 end
    local bx = math.floor((c.w - 8 * sw) / 2) + 1
    local by = math.max(1, math.floor((c.h - 1 - 8 * sh) / 2) + 1)
    send(k, "mouse_click", 1, c.x + bx - 1 + 3 * sw + 1, c.y + by - 1 + 2 * sh)
    H.pump(k, 1.0)
    dump(parent, "09-reversi")
end)

scenario("10-paint", function(k, parent)
    H.pump(k, 0.2)
    k:launch("paint")
    H.pump(k, 0.3)
    local c = k.frames[k.focus].client
    local function cl(ev, x, y) send(k, ev, 1, c.x + x - 1, c.y + y - 1) end
    -- pick red from the palette row, draw a rectangle, then blue pencil scribble
    send(k, "mouse_click", 1, c.x + 14, c.y + c.h - 1)
    send(k, "key", keys.r, false)
    cl("mouse_click", 5, 3); cl("mouse_drag", 20, 10); cl("mouse_up", 20, 10)
    send(k, "mouse_click", 1, c.x + 11, c.y + c.h - 1)
    send(k, "key", keys.b, false)
    cl("mouse_click", 25, 5); cl("mouse_drag", 40, 14); cl("mouse_up", 40, 14)
    H.pump(k, 0.3)
    dump(parent, "10-paint")
end)

scenario("11-control-panel", function(k, parent)
    H.pump(k, 0.2)
    k:launch("control")
    H.pump(k, 0.3)
    dump(parent, "11-control-panel")
end)

scenario("12-open-dialog", function(k, parent)
    H.pump(k, 0.2)
    k:launch("notepad")
    H.pump(k, 0.3)
    k:toggleZoom(k.focus)
    H.pump(k, 0.2)
    k:post(k.focus, "arcadeos_menu", "open")
    H.pump(k, 0.3)
    dump(parent, "12-open-dialog")
end)

scenario("13-pine-links", function(k, parent)
    H.pump(k, 0.2)
    k:launch("pinelinks")
    H.pump(k, 1.5)
    dump(parent, "13-pine-links")
    ctrl(k, keys.tab)
    H.pump(k, 0.3)
    k:launch("clock")
    H.pump(k, 1.2)
    dump(parent, "14-back-to-desktop")
end)

scenario("15-blackjack", function(k, parent)
    H.pump(k, 0.2)
    k:launch("blackjack")
    H.pump(k, 1.0)
    send(k, "key", keys.enter, false)
    H.pump(k, 1.5)
    dump(parent, "15-blackjack")
end)

scenario("16-minesweeper", function(k, parent)
    H.pump(k, 0.2)
    k:launch("minesweeper")
    H.pump(k, 0.6)
    dump(parent, "16-minesweeper")
end)

scenario("17-screensaver", function(k, parent)
    local idle = require("sys.idle")
    H.pump(k, 0.2)
    idle.start(k, "pipes-3d")
    H.pump(k, 2.0)
    dump(parent, "17-screensaver")
end)

scenario("18-pine-dungeon", function(k, parent)
    H.pump(k, 0.2)
    k:launch("pinedungeon")
    H.pump(k, 1.5)
    send(k, "key", keys.enter, false)
    H.pump(k, 1.0)
    dump(parent, "18-pine-dungeon")
end)

local args = { ... }
local names = #args > 0 and args or ORDER
for _, name in ipairs(names) do
    local fn = SCENARIOS[name]
    if fn then
        local ok, err = pcall(H.withKernel, { first = "executive" }, fn)
        if not ok then
            local f = fs.open("/results/" .. name .. ".error.txt", "w")
            f.write(tostring(err))
            f.close()
        end
    end
end
