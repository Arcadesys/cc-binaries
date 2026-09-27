local credits = require("credits")
local completion = require("cc.completion")

-- Configuration
local PRICES = {
    ["minecraft:diamond"] = 1,
    ["minecraft:obsidian"] = 4,
    ["minecraft:ender_eye"] = 16
}

local mon = peripheral.find("monitor")
local drive = peripheral.find("drive")
local chest = nil
local storage = nil

-- Attempt to find chests/inventories
local periphs = peripheral.getNames()
for _, name in ipairs(periphs) do
    if peripheral.getType(name) == "minecraft:chest" or peripheral.getType(name) == "minecraft:barrel" then
        if not chest then
            chest = peripheral.wrap(name)
        elseif not storage then
            storage = peripheral.wrap(name)
        end
    end
end

-- If only one chest found, assume we are a turtle or we void items? 
-- The user said "sucked in". 
-- If we are a command computer, maybe we can clearslot?
-- For now, if no storage, we will just count and NOT move (safety) unless we are a turtle.
local is_turtle = turtle ~= nil

local function getDriveSide()
    for _, name in ipairs(periphs) do
        if peripheral.getType(name) == "drive" then
            return name
        end
    end
    return nil
end

local driveSide = getDriveSide()

local interacting = false

local function showAttract()
    if not mon then return end
    mon.setTextScale(1)
    mon.setBackgroundColor(colors.black)
    
    local w, h = mon.getSize()
    local colors_list = {colors.red, colors.orange, colors.yellow, colors.lime, colors.blue, colors.purple}
    
    local i = 1
    while true do
        if not interacting then
            mon.setBackgroundColor(colors.black)
            mon.clear()
            mon.setCursorPos(1, h/2)
            mon.setTextColor(colors_list[i])
            mon.setTextScale(2)
            local msg = "TURN IN COINS!"
            -- Center roughly
            mon.setCursorPos(3, 2) 
            mon.write(msg)
            
            mon.setTextScale(1)
            mon.setCursorPos(1, h-2)
            mon.setTextColor(colors.white)
            mon.write("No Disk? Check Chest!")
            
            i = i + 1
            if i > #colors_list then i = 1 end
            sleep(0.5)
        else
            sleep(0.5)
        end
    end
end

local function drawStatus(msg, color)
    if not mon then return end
    mon.setBackgroundColor(colors.black)
    mon.clear()
    mon.setCursorPos(1, 1)
    mon.setTextColor(color or colors.white)
    mon.setTextScale(1)
    mon.write(msg)
end

local function launchFireworks()
    -- Only works if command computer or configured
    if commands then
       -- Summon random firework
       commands.exec("summon firework_rocket ~ ~2 ~ {LifeTime:15,FireworksItem:{id:firework_rocket,Count:1,tag:{Fireworks:{Flight:1,Explosions:[{Type:1,Flicker:1,Trail:1,Colors:[I;11743532],FadeColors:[I;11743532]}]}}}}")
    else
        -- Fallback sound or visualization could go here
    end
end

local function processItems(mountPath)
    if not chest then return end
    
    local total_credit_gain = 0
    
    -- Iterate all slots
    for slot, item in pairs(chest.list()) do
        if PRICES[item.name] then
            local value = PRICES[item.name]
            local count = item.count
            local gain = value * count
            
            -- Move logic
            local moved = false
            if storage then
                -- Push to storage
                local pushed = chest.pushItems(peripheral.getName(storage), slot)
                if pushed == count then moved = true end
            elseif is_turtle then
                -- Turtle suck (must be facing chest)
                -- This is tricky if we don't know orientation. 
                -- We'll assume standard computer behavior first.
            else
                 -- WE CANNOT DESTROY ITEMS SAFELY WITHOUT STORAGE
                 -- but maybe the user wants us to?
                 -- User said "sucked in". 
                 -- Let's try to push to ANY other inventory found that is not the drive.
                 for _, p in ipairs(peripheral.getNames()) do
                    if p ~= peripheral.getName(chest) and p ~= peripheral.getName(drive) and peripheral.getType(p) ~= "monitor" and peripheral.getType(p) ~= "modem" then
                        -- try push
                        local pushed = chest.pushItems(p, slot)
                        if pushed >= count then 
                            moved = true 
                            break 
                        end
                    end
                 end
            end
            
            if moved then
                total_credit_gain = total_credit_gain + gain
                -- print("Processed " .. item.name .. " x" .. count .. " = " .. gain)
            else
                -- Could not move items
                if mon then
                     local w, h = mon.getSize()
                     mon.setCursorPos(1, h-1)
                     mon.setTextColor(colors.red)
                     mon.write("ERR: CANNOT MOVE ITEM")
                     sleep(1)
                     mon.setCursorPos(1, h-1)
                     mon.clearLine()
                end
            end
        end
    end
    
    if total_credit_gain > 0 then
        credits.add(total_credit_gain, mountPath)
        return total_credit_gain
    end
    return 0
end

local function mainLoop()
    local hadDisk = false
    
    while true do
        local hasDisk = disk.isPresent(driveSide)
        local mountPath = disk.getMountPath(driveSide)
        
        if hasDisk and mountPath then
            interacting = true
            if not hadDisk then
                if mon then
                    mon.setBackgroundColor(colors.black) -- Clear animation
                    mon.clear()
                end
                hadDisk = true
            end
            
            -- User logic
            local current = credits.get(mountPath)
            local name = credits.getName(mountPath) or "Guest"
            
            if mon then
                mon.setCursorPos(1,1)
                mon.setTextColor(colors.lime)
                mon.write("Welcome, " .. name)
                mon.setCursorPos(1,2)
                mon.write("Credits: " .. current)
                mon.setCursorPos(1,4)
                mon.setTextColor(colors.white)
                mon.write("Place items in chest...")
            end
            
            local gained = processItems(mountPath)
            if gained > 0 then
                if mon then
                    mon.setCursorPos(1,6)
                    mon.setTextColor(colors.yellow)
                    mon.write("Added: " .. gained .. " credits!")
                    sleep(1)
                    mon.setCursorPos(1,6) 
                    mon.clearLine()
                end
            end
            
        else
            -- No disk
            interacting = false
            if hadDisk then hadDisk = false end
            
            -- Check if someone is interacting (e.g. items in chest but no disk)
            local chestHasItems = false
            if chest then
                local list = chest.list()
                if list then
                    for slot, item in pairs(list) do
                        if PRICES[item.name] then
                            chestHasItems = true
                            break
                        end
                    end
                end
            end

            if chestHasItems then
                -- "Throws fireworks and encourages them"
                launchFireworks()
                -- We rely on parallel animation to show "TURN IN COINS" / "INSERT DISK"
                sleep(2) -- Don't spam fireworks
            end
        end
        
        sleep(0.5)
    end
end

-- Run
if not mon then
    print("Error: No monitor found.")
    return
end

parallel.waitForAny(showAttract, mainLoop)
