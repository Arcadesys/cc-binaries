-- Solid stone at y=11 with seeded ore veins; supply chest above, output chest below
-- Change `seed` (or pass a different world) to get a different ore layout.
local Y = 11
return {
    seed = 1,
    turtle = {
        x = 0, y = Y, z = 0, facing = "north",
        fuel = 2000,
        inventory = {
            [1] = "minecraft:coal:32",
            [2] = "minecraft:torch:64",
            [3] = "minecraft:cobblestone:32",
        },
    },
    -- Everything at or below y=64 is stone unless an ore rolls there.
    floor = "minecraft:stone",
    floorY = 64,
    floorDrops = { ["minecraft:stone"] = "minecraft:cobblestone" },
    -- chance = odds a 2x2x2 cell holds a vein; density = fill within the vein.
    ores = {
        { "minecraft:coal_ore", chance = 0.020, drops = "minecraft:coal" },
        { "minecraft:iron_ore", chance = 0.012, drops = "minecraft:raw_iron" },
        { "minecraft:copper_ore", chance = 0.010, drops = "minecraft:raw_copper:3" },
        { "minecraft:redstone_ore", chance = 0.006, maxY = 15, drops = "minecraft:redstone:4" },
        { "minecraft:lapis_ore", chance = 0.003, drops = "minecraft:lapis_lazuli:6" },
        { "minecraft:gold_ore", chance = 0.003, drops = "minecraft:raw_gold" },
        { "minecraft:diamond_ore", chance = 0.0015, maxY = 15, drops = "minecraft:diamond" },
        { "minecraft:gravel", chance = 0.010, vein = 3 },
        { "minecraft:andesite", chance = 0.015, vein = 3 },
    },
    -- cc-factory's default bay: supply inventory above, output inventory below.
    blocks = {
        { 0, Y, 0, "air" },
        { 0, Y + 1, 0, { name = "minecraft:chest", items = (function()
            -- A well-stocked bay: 9 stacks each of coal, torches and fill.
            local items = {}
            for i = 1, 9 do
                items[#items + 1] = "minecraft:coal:64"
                items[#items + 1] = "minecraft:torch:64"
                items[#items + 1] = "minecraft:cobblestone:64"
            end
            return items
        end)() } },
        -- The miner keeps the cobblestone it digs, so the receiver needs room:
        -- 108 slots, like a modded storage block (a plain chest fills mid-run).
        { 0, Y - 1, 0, { name = "minecraft:chest", size = 108, items = {} } },
    },
}
