-- Supply chests in front, above and below the turtle; wall to the east
return {
    turtle = {
        facing = "north",
        fuel = 500,
        inventory = { [1] = "minecraft:coal:4" },
    },
    blocks = {
        { 0, 0, -1, { name = "minecraft:chest", items = { "minecraft:cobblestone:64", "minecraft:coal:32" } } },
        { 0, 1, 0, { name = "minecraft:chest", items = { "minecraft:oak_planks:64" } } },
        { 0, -1, 0, { name = "minecraft:chest", items = {} } },
    },
    fill = {
        { 2, 0, -3, 2, 2, 3, "minecraft:stone_bricks" },
    },
}
