-- turtleos/strategies/farmer/sugarcane.lua
-- Cuts sugar cane (and cactus) down to the bottom block so it regrows.

local field = require("turtleos.lib.field")
local inv = require("turtleos.lib.inv")

local TALL = {
    ["minecraft:sugar_cane"] = true,
    ["minecraft:cactus"] = true,
}

local function isTall(block)
    return TALL[block.name] == true
end

local opts_ = {}
for _, o in ipairs(field.options) do opts_[#opts_ + 1] = o end
opts_[#opts_ + 1] = { key = "wait", label = "Minutes between", type = "number", default = 15, min = 1, max = 120 }

-- The turtle flies at the height of a cane's third block, so it can cut a
-- third block in its way and then the second block below it, leaving the
-- bottom one to regrow. Everything it cuts lands in its inventory.
local function visit(ctx)
    local ok, block = turtle.inspectDown()
    if ok and TALL[block.name] and turtle.digDown() then
        ctx.count("Cut")
    end
end

return {
    title = "Sugar cane farm",
    summary = "Cuts cane (or cactus) to regrow",
    description = "Flies over a cane field and cuts every stalk down to its bottom block, so it grows back. Also works on cactus. Drops the harvest in a chest.",
    setup = {
        "1. Plant cane in rows beside water. Rows of cane with water between them work; so does a ring around a pond.",
        "2. Stand at one corner, just outside the field. Place the turtle TWO blocks above the ground the cane grows from (level with a full-grown cane's top block), facing along the rows.",
        "3. The field runs forward from the block in front of the turtle, and to its right (or set 'Field is to the' to left).",
        "4. Put a chest directly BEHIND the turtle for the harvest.",
        "5. Fuel: put coal in the turtle, or in a chest directly UNDER it.",
        "Nothing above the field may be in the way: the turtle only cuts cane and cactus, never other blocks.",
    },
    options = opts_,
    repeats = true,
    estimateFuel = field.cycleFuel,
    run = function(opts, ctx)
        return field.run(opts, ctx, {
            visit = visit,
            keep = function(name) return inv.isFuel(name) end,
            moveOpts = { dig = function(block)
                if isTall(block) then ctx.count("Cut") return true end
                return false
            end },
        })
    end,
}
