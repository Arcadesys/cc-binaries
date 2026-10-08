-- turtleos/strategies/farmer/crops.lua
-- Harvests ripe wheat, carrots, potatoes and beetroot and replants them.

local field = require("turtleos.lib.field")
local inv = require("turtleos.lib.inv")

-- Crop block -> the age it's ripe at and the item that replants it.
local CROPS = {
    ["minecraft:wheat"] = { ripe = 7, seed = "minecraft:wheat_seeds" },
    ["minecraft:carrots"] = { ripe = 7, seed = "minecraft:carrot" },
    ["minecraft:potatoes"] = { ripe = 7, seed = "minecraft:potato" },
    ["minecraft:beetroots"] = { ripe = 3, seed = "minecraft:beetroot_seeds" },
}

local SEEDS = {}
for _, c in pairs(CROPS) do SEEDS[c.seed] = true end

local opts_ = {}
for _, o in ipairs(field.options) do opts_[#opts_ + 1] = o end
opts_[#opts_ + 1] = { key = "wait", label = "Minutes between", type = "number", default = 5, min = 1, max = 60 }

-- Plant whichever seed we hold the most of.
local function plantAny()
    local best, bestCount
    for slot = 1, 16 do
        local d = turtle.getItemDetail(slot)
        if d and SEEDS[d.name] and (not bestCount or d.count > bestCount) then
            best, bestCount = slot, d.count
        end
    end
    if best then
        turtle.select(best)
        return turtle.placeDown()
    end
    return false
end

local function visit(ctx)
    local ok, block = turtle.inspectDown()
    if not ok then
        -- Empty farmland (or a gap in the field): try to plant.
        if plantAny() then ctx.count("Planted") end
        return
    end
    local crop = CROPS[block.name]
    if not crop or (block.state and block.state.age or 0) < crop.ripe then return end
    if turtle.digDown() then
        ctx.count("Harvested")
        if inv.select(crop.seed) and turtle.placeDown() then
            ctx.count("Planted")
        elseif plantAny() then
            ctx.count("Planted")
        end
    end
end

-- Hold back one stack of each kind of seed for replanting; fuel stays too.
local function keep(name, kept)
    if SEEDS[name] then return 64 - kept end
    if inv.isFuel(name) then return true end
    return 0
end

return {
    title = "Crop farm",
    summary = "Wheat, carrots, potatoes, beets",
    description = "Flies over a field, harvests ripe wheat, carrots, potatoes and beetroot, replants, and drops the harvest in a chest. Works with any turtle tool. Water blocks in the field are fine.",
    setup = {
        "1. Till and plant your field. A 9x9 with water in the middle is classic.",
        "2. Stand at one corner, just outside the field. Place the turtle there one block ABOVE the crops (level with your head), facing along the field.",
        "3. The field should run forward from the block in front of the turtle and to its right (or set 'Field is to the' to left).",
        "4. Put a chest directly BEHIND the turtle for the harvest.",
        "5. Fuel: put coal in the turtle, or in a chest directly UNDER it.",
        "6. Put some seeds in the turtle so it can fill empty spots.",
        "Tip: turn on 'Start on boot' so it keeps farming after the chunk reloads.",
    },
    options = opts_,
    repeats = true,
    estimateFuel = field.cycleFuel,
    run = function(opts, ctx)
        return field.run(opts, ctx, { visit = visit, keep = keep, moveOpts = { dig = false } })
    end,
}
