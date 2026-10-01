-- For harness_inventory: supply chest in front, empty output chest below
return {
    turtle = { fuel = 500, inventory = { [1] = "minecraft:coal:4" } },
    blocks = {
        { 0, 0, -1, { name = "minecraft:chest", items = { "minecraft:cobblestone:64", "minecraft:oak_planks:32" } } },
        { 0, -1, 0, { name = "minecraft:chest", items = {} } },
    },
}
