-- turtleos/lib/inv.lua
-- Inventory helpers shared by jobs: finding items, fuel, unloading.

local inv = {}

local FUEL = {
    ["minecraft:coal"] = true,
    ["minecraft:charcoal"] = true,
    ["minecraft:coal_block"] = true,
    ["minecraft:lava_bucket"] = true,
    ["minecraft:blaze_rod"] = true,
    ["minecraft:dried_kelp_block"] = true,
}

function inv.isFuel(name)
    return FUEL[name] == true
end

function inv.fuelLevel()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return math.huge end
    return level
end

-- First slot holding an item whose name passes `match` (a name or a
-- function(name)), or nil.
function inv.find(match)
    for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d and (d.name == match or (type(match) == "function" and match(d.name))) then
            return slot, d
        end
    end
end

function inv.select(match)
    local slot = inv.find(match)
    if slot then turtle.select(slot) end
    return slot ~= nil
end

function inv.count(match)
    local n = 0
    for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d and (d.name == match or (type(match) == "function" and match(d.name))) then
            n = n + d.count
        end
    end
    return n
end

function inv.freeSlots()
    local n = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then n = n + 1 end
    end
    return n
end

-- Burn fuel items from the inventory, one at a time, until the fuel level
-- reaches `target`. Returns true when it got there.
function inv.refuel(target)
    if inv.fuelLevel() >= target then return true end
    local selected = turtle.getSelectedSlot()
    for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d and FUEL[d.name] then
            turtle.select(slot)
            while inv.fuelLevel() < target and turtle.getItemCount(slot) > 0 do
                if not turtle.refuel(1) then break end
            end
        end
        if inv.fuelLevel() >= target then break end
    end
    turtle.select(selected)
    return inv.fuelLevel() >= target
end

-- Pull fuel from a chest on `side` ("up", "down" or "front") and burn it
-- until the fuel level reaches `target`. Non-fuel items are put back.
function inv.refuelFrom(side, target)
    local suck = side == "up" and turtle.suckUp or side == "down" and turtle.suckDown or turtle.suck
    local drop = side == "up" and turtle.dropUp or side == "down" and turtle.dropDown or turtle.drop
    local tries = 0
    while inv.fuelLevel() < target and tries < 8 do
        tries = tries + 1
        local empty
        for slot = 1, 16 do
            if turtle.getItemCount(slot) == 0 then empty = slot break end
        end
        if not empty then break end
        turtle.select(empty)
        if not suck() then break end
        local d = turtle.getItemDetail(empty)
        if d and FUEL[d.name] then
            while inv.fuelLevel() < target and turtle.getItemCount(empty) > 0 do
                if not turtle.refuel(1) then break end
            end
        end
        if turtle.getItemCount(empty) > 0 then
            drop()
            if not (d and FUEL[d.name]) then break end
        end
    end
    turtle.select(1)
    return inv.fuelLevel() >= target
end

-- Drop everything into the chest on `side`, except what `keep(name, kept)`
-- asks to keep. `kept` is how many of that item have been kept so far, so
-- keep can hold back e.g. one stack of seeds. Returns false if the chest
-- filled up.
function inv.unload(side, keep)
    local drop = side == "up" and turtle.dropUp or side == "down" and turtle.dropDown or turtle.drop
    local kept = {}
    local ok = true
    for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d then
            local have = kept[d.name] or 0
            local hold = keep and keep(d.name, have) or 0
            if hold == true then hold = d.count elseif not hold then hold = 0 end
            local give = d.count - math.min(d.count, math.max(0, hold))
            kept[d.name] = have + (d.count - give)
            if give > 0 then
                turtle.select(slot)
                if not drop(give) then ok = false end
            end
        end
    end
    turtle.select(1)
    return ok
end

-- Merge partial stacks so freed slots can take new items.
function inv.compact()
    for slot = 16, 2, -1 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            for target = 1, slot - 1 do
                if turtle.getItemCount(target) > 0 and turtle.compareTo(target) then
                    turtle.transferTo(target)
                    if turtle.getItemCount(slot) == 0 then break end
                end
            end
        end
    end
    turtle.select(1)
end

return inv
