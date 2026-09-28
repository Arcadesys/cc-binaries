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
