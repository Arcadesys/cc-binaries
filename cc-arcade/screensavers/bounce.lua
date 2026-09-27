-- bounce.lua
-- Simple Bouncing DVD Logo Screensaver

local term = term.current()
local width, height = term.getSize()
local x, y = math.floor(width / 2), math.floor(height / 2)
local dx, dy = 1, 1
local color = colors.red

local colorsList = {colors.red, colors.orange, colors.yellow, colors.green, colors.blue, colors.purple, colors.cyan}

while true do
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(x, y)
    term.setTextColor(color)
    term.write("O")
    
    x = x + dx
    y = y + dy
    
    if x <= 1 or x >= width then
        dx = -dx
        color = colorsList[math.random(#colorsList)]
    end
    
    if y <= 1 or y >= height then
        dy = -dy
        color = colorsList[math.random(#colorsList)]
    end
    
    -- Check for input to exit
    local timer = os.startTimer(0.1)
    local event, p1 = os.pullEvent()
    if event == "key" or event == "mouse_click" or event == "monitor_touch" or event == "disk" then
        return -- Exit screensaver
    end
end
