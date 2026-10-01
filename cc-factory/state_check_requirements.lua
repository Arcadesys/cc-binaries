---@diagnostic disable: undefined-global
--[[
State: CHECK_REQUIREMENTS
Verifies that the turtle has enough fuel and materials to complete the task.
Prompts the user if items are missing.
--]]

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local fuel = require("lib_fuel")
local diagnostics = require("lib_diagnostics")

local function calculateRequirements(ctx, strategy)
    local reqs = {
        fuel = 0,
        materials = {}
    }

    -- Estimate fuel: one per movement step (turns, scans and torches are free).
    if strategy then
        for _, step in ipairs(strategy) do
            if step.type == "move" or step.type == nil then
                reqs.fuel = reqs.fuel + 1
            end
        end
    end
    
    -- Add a safety margin for fuel (e.g. 10% + 100)
    reqs.fuel = math.ceil(reqs.fuel * 1.1) + 100

    -- Calculate materials
    if ctx.config.mode == "mine" then
        -- Mining mode
        -- Check for torches if strategy has place_torch
        for _, step in ipairs(strategy) do
            if step.type == "place_torch" then
                reqs.materials["minecraft:torch"] = (reqs.materials["minecraft:torch"] or 0) + 1
            end
        end
    else
        -- Build mode
        for _, step in ipairs(strategy) do
            if step.block and step.block.material then
                local mat = step.block.material
                reqs.materials[mat] = (reqs.materials[mat] or 0) + 1
            end
        end
    end

    return reqs
end

-- Fuel the turtle can burn from its own inventory (REFUEL uses it on the go).
local FUEL_VALUES = {
    ["minecraft:coal"] = 80,
    ["minecraft:charcoal"] = 80,
    ["minecraft:coal_block"] = 800,
    ["minecraft:charcoal_block"] = 800,
    ["minecraft:blaze_rod"] = 120,
    ["minecraft:lava_bucket"] = 1000,
}

local function onboardFuel(invCounts)
    local total = 0
    for name, count in pairs(invCounts) do
        total = total + (FUEL_VALUES[name] or 0) * count
    end
    return total
end

local function getInventoryCounts(ctx)
    local counts = {}
    -- Scan all slots
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            counts[item.name] = (counts[item.name] or 0) + item.count
        end
    end
    return counts
end

local function checkNearbyChests(ctx, missing)
    local found = {}
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local types = { peripheral.getType(side) }
            local isInventory = false
            for _, t in ipairs(types) do
                if t == "inventory" then isInventory = true break end
            end
            
            if isInventory then
                local p = peripheral.wrap(side)
                if p and p.list then
                    local list = p.list()
                    for slot, item in pairs(list) do
                        if item and missing[item.name] then
                            found[item.name] = (found[item.name] or 0) + item.count
                        end
                    end
                end
            end
        end
    end
    return found
end

local function CHECK_REQUIREMENTS(ctx)
    logger.log(ctx, "info", "Checking requirements...")

    local strategy, errMsg = diagnostics.requireStrategy(ctx)
    if not strategy then
        return "ERROR"
    end

    local reqs = calculateRequirements(ctx, strategy)
    local invCounts = getInventoryCounts(ctx)
    local currentFuel = turtle.getFuelLevel()
    if currentFuel == "unlimited" then currentFuel = 999999 end
    local carriedFuel = onboardFuel(invCounts)

    local missing = {
        fuel = 0,
        materials = {}
    }
    local hasMissing = false

    -- Check fuel
    if currentFuel + carriedFuel < reqs.fuel then
        missing.fuel = reqs.fuel - currentFuel - carriedFuel
        hasMissing = true
    end

    -- Check materials
    for mat, count in pairs(reqs.materials) do
        local have = invCounts[mat] or 0
        if have < count then
            missing.materials[mat] = count - have
            hasMissing = true
        end
    end

    if not hasMissing then
        logger.log(ctx, "info", "All requirements met.")
        return ctx.nextState or "DONE"
    end

    -- Report missing
    print("\n=== MISSING REQUIREMENTS ===")
    if missing.fuel > 0 then
        print(string.format("- Fuel: %d (Have %d + %d in fuel items, Need %d)", missing.fuel, currentFuel, carriedFuel, reqs.fuel))
    end
    for mat, count in pairs(missing.materials) do
        print(string.format("- %s: %d", mat, count))
    end

    -- Check nearby
    local nearby = checkNearbyChests(ctx, missing.materials)
    local foundNearby = false
    for mat, count in pairs(nearby) do
        if not foundNearby then
            print("\n=== FOUND IN NEARBY CHESTS ===")
            foundNearby = true
        end
        print(string.format("- %s: %d", mat, count))
    end

    print("\nPress Enter to re-check, or type 'q' then Enter to quit.")
    local input = read()
    if input == "q" or input == "Q" then
        return "DONE"
    end
    
    return "CHECK_REQUIREMENTS"
end

return CHECK_REQUIREMENTS
