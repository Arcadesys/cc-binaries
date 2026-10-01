-- For harness_placement: acts out each scenario's "place/remove a block" prompt
return {
    turtle = {
        fuel = 1000,
        inventory = {
            [1] = "minecraft:cobblestone:16",
            [2] = "minecraft:oak_planks:16",
        },
    },
    prompts = {
        { "Place an indestructible block in front", function(world)
            world:setSide("front", "minecraft:obsidian")
        end },
        { "Break the blocking block", function(world)
            world:setSide("front", nil)
        end },
        { "Remove all minecraft:cobblestone", function(world)
            world:take("minecraft:cobblestone")
        end },
    },
}
