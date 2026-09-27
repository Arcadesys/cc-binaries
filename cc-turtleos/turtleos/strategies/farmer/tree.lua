-- turtleos/strategies/farmer/tree.lua
-- Ensure package path includes root
if not package.path:find("/?.lua") then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local logger = require("turtleos.lib.logger")

-- Load movement API
local movement = require("turtleos.apis.movement")

local tree = {}

-- Configuration
local FARM_ROWS = 4    -- Number of trees along X axis
local FARM_COLS = 4    -- Number of trees along Z axis
local SPACING_X = 2    -- Distance between tree rows
local SPACING_Z = 2    -- Distance between trees in a row
local START_X = 2      -- X coordinate of first tree row
local START_Z = 1      -- Z coordinate of first tree in row

-- Aisle behind the last tree row to safely cross X columns
local AISLE_Z = START_Z + (FARM_COLS * SPACING_Z)

local function generateTreeLocations()
    local locs = {}
    for x = 0, FARM_ROWS - 1 do
        for z = 0, FARM_COLS - 1 do
            table.insert(locs, {
                x = START_X + (x * SPACING_X),
                z = START_Z + (z * SPACING_Z)
            })
        end
    end
    return locs
end

local treeLocations = generateTreeLocations()
local currentTreeIndex = 1

local function selectItem(pattern)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name:find(pattern) then
            turtle.select(i)
            return true
        end
    end
    return false
end

local function isLog(name)
    if not name then return false end
    -- Match any type of log
    return name:find("log") ~= nil or name:find("wood") ~= nil or name:find("stem") ~= nil
end

local function isSapling(name)
    if not name then return false end
    return name:find("sapling") ~= nil
end

local function isLeaves(name)
    if not name then return false end
    return name:find("leaves") ~= nil or name:find("wart_block") ~= nil
end

-- Comprehensive tree chopping that handles branches
local function chopTree()
    logger.info("Starting tree chop sequence...")
    local logsChopped = 0
    
    -- Dig the base log
    if turtle.detect() then
        local success, data = turtle.inspect()
        if success then
            logger.info("Base block: " .. data.name)
            if isLog(data.name) then
                turtle.dig()
                logsChopped = logsChopped + 1
            else
                logger.warn("Front block is not a log: " .. data.name)
                return 0
            end
        end
    else
        logger.warn("No block in front to chop")
        return 0
    end
    
    -- Move forward into the tree position
    if not movement.forward(true) then
        logger.error("Failed to move into tree position")
        return logsChopped
    end
    
    -- Chop upwards
    local height = 0
    while height < 32 do -- Max tree height limit
        local hasUp, upData = turtle.inspectUp()
        
        if hasUp and (isLog(upData.name) or isLeaves(upData.name)) then
            if isLog(upData.name) then
                logger.info("Found log above at height " .. height)
                turtle.digUp()
                logsChopped = logsChopped + 1
            else
                -- It's leaves, dig through them
                turtle.digUp()
            end
            
            if movement.up(true) then
                height = height + 1
            else
                logger.warn("Failed to move up at height " .. height)
                break
            end
        else
            -- No more logs/leaves above
            break
        end
        
        -- Check and dig logs in all horizontal directions at this level
        for dir = 0, 3 do
            movement.face(dir)
            local hasFront, frontData = turtle.inspect()
            if hasFront and isLog(frontData.name) then
                logger.info("Found adjacent log at height " .. height)
                turtle.dig()
                logsChopped = logsChopped + 1
            end
        end
    end
    
    logger.info("Chopped " .. logsChopped .. " logs, descending from height " .. height)
    
    -- Come back down
    for i = 1, height do
        if not movement.down(true) then
            logger.error("Failed to descend at level " .. i)
            break
        end
    end
    
    -- Move back to standing position (back out of the tree)
    -- We assume we approach from West (x-1), so we exit to West (3)
    movement.face(3)
    if not movement.forward(true) then
        logger.error("Failed to exit tree position")
    end
    
    -- Face the tree again (East) for planting or next check
    movement.face(1)
    
    return logsChopped
end

-- Move to a specific standing position safely
local function safeGoto(targetX, targetZ)
    local SAFE_HEIGHT = 2 -- Fly over chests/ground obstacles
    local current = movement.getPosition()
    
    -- Function to ensure height
    local function ensureHeight(h)
        local pos = movement.getPosition()
         -- Go Up
        while pos.y < h do
            if not movement.up(true) then return false end
            pos = movement.getPosition()
        end
        -- Go Down (only if we need to go lower, but here we just want AT LEAST h)
        return true
    end

    -- 1. Ascend to safe height
    if not ensureHeight(SAFE_HEIGHT) then
        logger.error("Failed to ascend to safe height")
        return false
    end
    
    -- 2. Traverse logic
    -- If changing columns, use the aisle at Z=9
    if math.abs(current.x - targetX) > 0.1 then
        -- Move to AISLE_Z (Back of the farm) at safe height
        if not movement.gotoPosition(current.x, SAFE_HEIGHT, AISLE_Z, true) then
            logger.error("Failed to move to safe aisle")
            return false
        end
        
        -- Move along aisle to target X
        if not movement.gotoPosition(targetX, SAFE_HEIGHT, AISLE_Z, true) then
            logger.error("Failed to move along safe aisle")
            return false
        end
    end
    
    -- 3. Move to target tree Z at safe height
    if not movement.gotoPosition(targetX, SAFE_HEIGHT, targetZ, true) then
        logger.error("Failed to move to target Z")
        return false
    end
    
    -- 4. Descend to ground (Target Y=0)
    if not movement.gotoPosition(targetX, 0, targetZ, true) then
        logger.error("Failed to descend to tree position")
        return false
    end
    
    return true
end

local STATE_FILE = "tree_state.txt"

local function saveProgress(index)
    local file = fs.open(STATE_FILE, "w")
    if file then
        file.write(tostring(index))
        file.close()
    end
end

local function loadProgress()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        if file then
            local data = file.readAll()
            file.close()
            return tonumber(data) or 1
        end
    end
    return 1
end

function tree.execute()
    -- Debug: Check if turtle API exists
    if not turtle then
        logger.error("Turtle API not available! Are you running this on a turtle?")
        return
    end
    
    -- Load movement state
    movement.loadState()
    
    -- Check fuel
    local fuelLevel = turtle.getFuelLevel()
    logger.info("Current fuel level: " .. tostring(fuelLevel))
    
    if fuelLevel ~= "unlimited" and fuelLevel < 100 then
        logger.info("Attempting to refuel...")
        movement.refuel()
        logger.info("New fuel level: " .. turtle.getFuelLevel())
    end

    -- Load progress
    currentTreeIndex = loadProgress()
    if currentTreeIndex > #treeLocations then
        logger.warn("Saved index " .. currentTreeIndex .. " exceeds tree count " .. #treeLocations .. ". Resetting to 1.")
        currentTreeIndex = 1
    end
    logger.info("Resuming from tree index " .. currentTreeIndex)

    -- Get current tree target
    local targetTree = treeLocations[currentTreeIndex]
    local standX = targetTree.x - 1
    local standZ = targetTree.z
    
    logger.info(string.format("Moving to tree %d at (%d, %d)", currentTreeIndex, targetTree.x, targetTree.z))
    
    -- Go to standing position
    if not safeGoto(standX, standZ) then
        logger.error("Aborting tree cycle due to movement error.")
        return
    end
    
    -- Save position after successful move
    movement.saveState()
    
    -- Face East (towards the tree at x+1)
    movement.face(1)
    movement.saveState()

    local hasBlock, data = turtle.inspect()
    
    if hasBlock then
        logger.info("Block detected: " .. data.name)
    else
        logger.info("No block in front")
    end
    
    if hasBlock and isLog(data.name) then
        logger.info("Found tree! Starting comprehensive chop...")
        local logsChopped = chopTree()
        logger.info("Finished chopping! Total logs: " .. logsChopped)
        
        -- Try to plant immediately after chopping
        logger.info("Planting sapling...")
        if selectItem("sapling") then
            if turtle.place() then
                logger.info("Sapling planted successfully")
            else
                logger.warn("Failed to place sapling (something blocking?)")
            end
        else
            logger.warn("No saplings found in inventory!")
        end

    elseif not hasBlock then
        -- Space is empty, try to plant
        logger.info("Space empty. Planting sapling...")
        if selectItem("sapling") then
            if not turtle.place() then
                logger.warn("Failed to place sapling.")
            end
        else
            logger.warn("No saplings found in inventory!")
        end
    else
        -- Block exists but is not a log.
        if isSapling(data.name) then
             logger.info("Sapling detected, waiting for growth...")
        else
             logger.warn("Unknown block in front: " .. data.name)
        end
    end
    
    -- Move to next tree index for next execution
    currentTreeIndex = currentTreeIndex + 1
    if currentTreeIndex > #treeLocations then
        currentTreeIndex = 1
        logger.info("Cycle complete. Restarting...")
        sleep(5) -- Wait a bit before restarting the cycle
    end
    
    -- Save progress for next run
    saveProgress(currentTreeIndex)
end

return tree
