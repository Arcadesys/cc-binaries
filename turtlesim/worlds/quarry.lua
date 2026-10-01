-- Solid stone with ores from y=-1 down to y=-8; turtle on the surface with fuel
return {
    turtle = {
        facing = "north",
        fuel = 2000,
        inventory = { [1] = "minecraft:coal:32", [2] = "minecraft:torch:64" },
    },
    floor = "minecraft:stone",
    floorY = -1,
    blocks = {
        { 0, -3, -4, "minecraft:coal_ore" },
        { 1, -3, -4, { name = "minecraft:iron_ore", drops = "minecraft:raw_iron" } },
        { 0, -5, -10, { name = "minecraft:diamond_ore", drops = "minecraft:diamond" } },
        { -2, -9, 0, "minecraft:bedrock" },
    },
    fill = {
        { -16, -9, -16, 16, -9, 16, "minecraft:bedrock" },
    },
}
