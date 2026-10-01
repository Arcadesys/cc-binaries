-- Open flat area, 1000 fuel, coal/cobblestone/planks on board (the default)
return {
    turtle = {
        x = 0, y = 0, z = 0, facing = "north",
        fuel = 1000,
        inventory = {
            [1] = "minecraft:coal:16",
            [2] = "minecraft:cobblestone:64",
            [3] = "minecraft:oak_planks:32",
        },
    },
    -- Stone floor below y=0; everything at y>=0 is air unless listed.
    floor = "minecraft:stone",
    floorY = -1,
}
