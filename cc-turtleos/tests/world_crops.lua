-- 5x5 field north-east of the turtle: farmland at y=-1, crops at y=0,
-- turtle at y=1 facing north. Output chest behind, fuel chest below.
local SEEDS = {
    ["minecraft:wheat_seeds"] = "minecraft:wheat",
    ["minecraft:carrot"] = "minecraft:carrots",
    ["minecraft:potato"] = "minecraft:potatoes",
    ["minecraft:beetroot_seeds"] = "minecraft:beetroots",
}
local blocks = {
    { 0, 1, 1, { name = "minecraft:chest", items = {} } },
    { 0, 0, 0, { name = "minecraft:chest", items = { "minecraft:coal:8" } } },
    { 2, 0, -3, "minecraft:water" },
}
for x = 0, 4 do
    for z = -5, -1 do
        local i = x * 5 - z
        if not (x == 2 and z == -3) and i % 4 ~= 0 then
            if i % 4 == 1 then
                blocks[#blocks + 1] = { x, 0, z, { name = "minecraft:wheat", state = { age = 7 },
                    drops = { "minecraft:wheat:1", "minecraft:wheat_seeds:2" } } }
            elseif i % 4 == 2 then
                blocks[#blocks + 1] = { x, 0, z, { name = "minecraft:carrots", state = { age = 3 } } }
            else
                blocks[#blocks + 1] = { x, 0, z, { name = "minecraft:potatoes", state = { age = 7 },
                    drops = "minecraft:potato:3" } }
            end
        end
    end
end
return {
    turtle = { x = 0, y = 1, z = 0, facing = "north", fuel = 0,
               inventory = { [1] = "minecraft:wheat_seeds:4" } },
    floor = "minecraft:farmland", floorY = -1,
    blocks = blocks,
    onPlace = function(world, x, y, z, item)
        local crop = SEEDS[item]
        if not crop then return nil end
        local below = world:getBlock(x, y - 1, z)
        if y ~= 0 or not below or below.name ~= "minecraft:farmland" then return false end
        return { name = crop, state = { age = 0 } }
    end,
}
