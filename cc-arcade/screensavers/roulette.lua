-- roulette.lua
-- Roulette Wheel Screensaver for Arcade OS
-- Ambient spinning wheel

local term = term.current()
local w, h = term.getSize()

-- European Roulette Wheel Sequence
local WHEEL = {
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 
    11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 
    22, 18, 29, 7, 28, 12, 35, 3, 26
}

local REDS = {
    [1]=true, [3]=true, [5]=true, [7]=true, [9]=true, [12]=true,
    [14]=true, [16]=true, [18]=true, [19]=true, [21]=true, [23]=true,
    [25]=true, [27]=true, [30]=true, [32]=true, [34]=true, [36]=true
}

local function getNumberColor(num)
    if num == 0 then return colors.green end
    if REDS[num] then return colors.red end
    return colors.black -- ComputerCraft black is actually black
end

-- Helper to handle wait and input check
local function wait(seconds)
    local timer = os.startTimer(seconds)
    while true do
        local event, p1 = os.pullEvent()
        if event == "timer" and p1 == timer then
            return true
        elseif event == "key" or event == "mouse_click" or 
               event == "monitor_touch" or event == "disk" then
            return false -- Input detected, exit
        end
    end
end

local function drawView(offsetIndex)
    term.setBackgroundColor(colors.black)
    term.clear()
    
    local centerY = math.floor(h/2)
    local itemWidth = 5
    local visibleItems = math.ceil(w / itemWidth) + 2
    local centerScreen = math.floor(w/2)
    
    -- Draw Pointer
    term.setTextColor(colors.yellow)
    term.setCursorPos(centerScreen, centerY - 2)
    term.write("v")
    term.setCursorPos(centerScreen, centerY + 2)
    term.write("^")
    
    -- Draw Wheel Strip
    -- offsetIndex is the index of the number currently at center
    -- We need to draw neighbors to the left and right
    
    for i = -math.floor(visibleItems/2), math.floor(visibleItems/2) do
        -- Calculate index in WHEEL (1-based wrapping)
        local idx = ((offsetIndex + i - 1) % #WHEEL) + 1
        local num = WHEEL[idx]
        local bg = getNumberColor(num)
        
        -- Screen X position
        -- If i=0 (center item), x should be centerScreen - (itemWidth/2) approximately
        local x = math.floor(centerScreen + (i * itemWidth) - (itemWidth/2))
        
        -- Draw block
        if x + itemWidth > 1 and x <= w then
             term.setBackgroundColor(bg)
             term.setTextColor(colors.white)
             
             -- Draw box
             for dy = -1, 1 do
                 if x < 1 then 
                     -- Partial draw left
                 else
                     term.setCursorPos(x, centerY + dy)
                     
                     local text = tostring(num)
                     local pad = math.floor((itemWidth - #text)/2)
                     local str = string.rep(" ", pad) .. text .. string.rep(" ", itemWidth - #text - pad)
                     
                     if dy ~= 0 then str = string.rep(" ", itemWidth) end -- Only text on middle line
                     
                     -- Handle clipping
                     if x + #str - 1 > w then
                         str = string.sub(str, 1, w - x + 1)
                     end
                     if x < 1 then
                          str = string.sub(str, 2 - x)
                          term.setCursorPos(1, centerY + dy)
                     end
                     
                     term.write(str)
                 end
             end
        end
    end
    
    -- Decor: Spinning ASCII Wheel (Visual only)
    -- Just a rotating character or something above
    term.setBackgroundColor(colors.black)
    local spinChars = {"|", "/", "-", "\\"}
    local spinFrame = math.floor(os.clock() * 10) % 4 + 1
    -- drawText(centerScreen, centerY - 4, spinChars[spinFrame], colors.gray, colors.black)
end

while true do
    -- 1. Spin Phase
    local speed = 0.05 -- Delay per frame (lower is faster)
    local friction = 1.05 -- Multiplier to speed (slow down)
    local currentIndex = math.random(1, #WHEEL)
    local totalSpins = math.random(30, 60) -- Number of ticks to spin
    
    -- Accelerate / Constant
    local runTicks = 0
    while runTicks < totalSpins do
        currentIndex = (currentIndex % #WHEEL) + 1
        
        drawView(currentIndex)
        
        if not wait(0.05) then return end -- Fixed fast speed
        
        runTicks = runTicks + 1
    end
    
    -- Decelerate
    while speed < 0.8 do
        currentIndex = (currentIndex % #WHEEL) + 1
        
        drawView(currentIndex)
        
        if not wait(speed) then return end
        
        speed = speed * friction
    end
    
    -- Stop & Highlight
    local winner = WHEEL[currentIndex]
    local wColor = getNumberColor(winner)
    
    -- Blink effect
    for i=1, 6 do
        term.setCursorPos(math.floor(w/2)-2, math.floor(h/2)-1)
        if i % 2 == 0 then
            term.setBackgroundColor(wColor)
            term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.white)
            term.setTextColor(wColor)
        end
        term.write(string.format(" %2d  ", winner))
        
        if not wait(0.3) then return end
    end
    
    -- Hold
    if not wait(3) then return end
end
