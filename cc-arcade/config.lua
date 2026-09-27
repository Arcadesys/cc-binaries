-- config.lua
-- Button Configuration Wizard

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function saveConfig(config)
    local file = fs.open(".button_config", "w")
    file.write(textutils.serialize(config))
    file.close()
end

local function waitForInput(buttonName)
    clear()
    print("BUTTON SETUP")
    print("============")
    print("")
    print("Please press the " .. buttonName .. " button.")
    print("(Press a Key or activate Redstone)")
    
    while true do
        local event, p1 = os.pullEvent()
        
        if event == "key" then
            -- p1 is key code
            return { type = "key", value = p1 }
            
        elseif event == "redstone" then
            -- Check all sides for active input
            for _, side in ipairs(rs.getSides()) do
                if rs.getInput(side) then
                    -- Wait for signal to turn off to avoid double detection?
                    -- For now, just accept it.
                    return { type = "redstone", value = side }
                end
            end
        end
    end
end

-- Main Wizard
local config = {}

-- 1. Left Button
config.LEFT = waitForInput("LEFT")
print("Captured!")
sleep(0.5)

-- 2. Center Button
config.CENTER = waitForInput("CENTER")
print("Captured!")
sleep(0.5)

-- 3. Right Button
config.RIGHT = waitForInput("RIGHT")
print("Captured!")
sleep(0.5)

-- Save
saveConfig(config)

clear()
print("Configuration Saved!")
print("Left: " .. config.LEFT.type .. " " .. config.LEFT.value)
print("Center: " .. config.CENTER.type .. " " .. config.CENTER.value)
print("Right: " .. config.RIGHT.type .. " " .. config.RIGHT.value)
print("")
print("Continuing startup...")
sleep(2)
