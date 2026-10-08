-- Cane rows at x=0 and x=2 with water between, growing from y=0. The turtle
-- flies at y=2 facing north. Output chest behind, fuel chest below.
local blocks = {
    { 0, 2, 1, { name = "minecraft:chest", items = {} } },
    { 0, 1, 0, { name = "minecraft:chest", items = { "minecraft:coal:4" } } },
    { 0, 0, 0, "minecraft:stone" },
}
for z = -4, -1 do
    blocks[#blocks + 1] = { 1, 0, z, "minecraft:water" }
    for _, x in ipairs({ 0, 2 }) do
        local height = (x + z) % 3 + 1 -- 1, 2 or 3 tall
        for y = 0, height - 1 do
            blocks[#blocks + 1] = { x, y, z, "minecraft:sugar_cane" }
        end
    end
end
return {
    turtle = { x = 0, y = 2, z = 0, facing = "north", fuel = 0 },
    floor = "minecraft:sand", floorY = -1,
    blocks = blocks,
}
