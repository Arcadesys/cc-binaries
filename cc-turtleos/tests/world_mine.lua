-- Solid stone with seeded ore veins. The turtle stands in a 2-high nook at
-- y=11 facing north, output chest behind, fuel chest below.
local branchmine = dofile("/.turtlesim/worlds/branchmine.lua")
local Y = 11
return {
    seed = 1,
    turtle = { x = 0, y = Y, z = 0, facing = "north", fuel = 100,
               inventory = { [1] = "minecraft:coal:4", [2] = "minecraft:torch:16" } },
    floor = "minecraft:stone", floorY = 64,
    floorDrops = branchmine.floorDrops,
    ores = branchmine.ores,
    blocks = {
        { 0, Y, 0, "air" },
        { 0, Y + 1, 0, "air" },
        { 0, Y, 1, { name = "minecraft:chest", items = {} } },
        { 0, Y - 1, 0, { name = "minecraft:chest", items = { "minecraft:coal:64" } } },
    },
}
