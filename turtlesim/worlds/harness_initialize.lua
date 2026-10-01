-- For harness_initialize: the sample schema's materials split between turtle and a chest
return {
    turtle = {
        fuel = 500,
        inventory = {
            [1] = "minecraft:stone_bricks:10",
            [2] = "minecraft:torch:1",
        },
    },
    blocks = {
        { 0, 0, -1, { name = "minecraft:chest", items = {
            "minecraft:stone_bricks:8", "minecraft:glass:2", "minecraft:lantern:1",
        } } },
    },
}
