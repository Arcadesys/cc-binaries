-- ArcadeOS boot: splash screen, then the kernel.
local root = fs.getDir(shell.getRunningProgram())
local theme = require("sys.theme")
local Kernel = require("sys.kernel")

local args = { ... }
local quick = args[1] == "--quick"

local FONT = {
    A = { " ### ", "#   #", "#####", "#   #", "#   #" },
    R = { "#### ", "#   #", "#### ", "#  # ", "#   #" },
    C = { " ####", "#    ", "#    ", "#    ", " ####" },
    D = { "#### ", "#   #", "#   #", "#   #", "#### " },
    E = { "#####", "#    ", "#### ", "#    ", "#####" },
    O = { " ### ", "#   #", "#   #", "#   #", " ### " },
    S = { " ####", "#    ", " ### ", "    #", "#### " },
    [" "] = { "  ", "  ", "  ", "  ", "  " },
}

local function splash(t)
    local W, H = t.getSize()
    theme.apply(t)
    t.setBackgroundColor(colors.white)
    t.clear()
    local word, tints = "ARCADE OS", { colors.blue, colors.red }
    local width = 0
    for ch in word:gmatch(".") do width = width + #FONT[ch][1] + 1 end
    width = width - 1
    local x0 = math.max(1, math.floor((W - width) / 2) + 1)
    local y0 = math.max(1, math.floor(H / 2) - 4)
    if W >= width then
        local x, tint = x0, tints[1]
        for ch in word:gmatch(".") do
            if ch == " " then tint = tints[2] end
            local glyph = FONT[ch]
            for row = 1, 5 do
                t.setCursorPos(x, y0 + row - 1)
                local line = glyph[row]
                for i = 1, #line do
                    t.setBackgroundColor(line:sub(i, i) == "#" and tint or colors.white)
                    t.write(" ")
                end
            end
            x = x + #glyph[1] + 1
        end
    else
        t.setCursorPos(math.floor((W - 8) / 2) + 1, y0 + 2)
        t.setTextColor(colors.blue)
        t.write("ArcadeOS")
    end
    local lines = {
        "Version " .. Kernel.VERSION,
        "Copyright (c) 2026 Arcadesys.",
        "All Rights Reserved.",
    }
    t.setBackgroundColor(colors.white)
    t.setTextColor(colors.black)
    for i, s in ipairs(lines) do
        t.setCursorPos(math.max(1, math.floor((W - #s) / 2) + 1), y0 + 6 + i)
        t.write(s)
    end
end

local native = term.current()
if not quick then
    splash(native)
    local timer = os.startTimer(1.5)
    while true do
        local ev, p1 = os.pullEvent()
        if (ev == "timer" and p1 == timer) or ev == "key" or ev == "mouse_click" then break end
    end
end

for _, dir in ipairs({ "/home", "/midi" }) do
    if not fs.exists(dir) then fs.makeDir(dir) end
end

local kernel = Kernel.new({ root = root, shell = shell, parent = native })
kernel:run()
print("Thank you for using ArcadeOS.")
