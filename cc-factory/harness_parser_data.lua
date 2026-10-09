local parser_data = {}

parser_data.SAMPLE_TEXT_GRID = [[
legend:
# = minecraft:cobblestone
~ = minecraft:glass

####
#..#
#..#
####

layer:1
~..~
.##.
~..~
]]

parser_data.SAMPLE_JSON = [[
{
  "legend": {
    "A": "minecraft:oak_planks",
    "B": { "material": "minecraft:stone", "meta": { "variant": "smooth" } }
  },
  "layers": [
    {
      "y": 0,
      "rows": ["AA", "BB"]
    },
    {
      "y": 1,
      "rows": ["BB", "AA"]
    }
  ]
}
]]

parser_data.SAMPLE_VOXEL = [[
{
  "grid": {
    "0": {
      "0": { "0": "minecraft:oak_log", "1": "minecraft:oak_log" },
      "1": { "0": "minecraft:oak_leaves", "1": "minecraft:oak_leaves" }
    },
    "1": {
      "0": { "0": "minecraft:oak_leaves", "1": "minecraft:oak_leaves" },
      "1": { "0": "minecraft:air", "1": "minecraft:torch" }
    }
  }
}
]]

parser_data.EXPECT_TEXT_GRID = {
    totalBlocks = 18,
    materials = {
        ["minecraft:cobblestone"] = 14,
        ["minecraft:glass"] = 4,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 3, y = 1, z = 3 },
    },
}

parser_data.EXPECT_JSON = {
    totalBlocks = 8,
    materials = {
        ["minecraft:oak_planks"] = 4,
        ["minecraft:stone"] = 4,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 1 },
    },
}

parser_data.EXPECT_VOXEL = {
    totalBlocks = 8,
    materials = {
        ["minecraft:oak_log"] = 2,
        ["minecraft:oak_leaves"] = 4,
        ["minecraft:air"] = 1,
        ["minecraft:torch"] = 1,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 1 },
    },
}

parser_data.SAMPLE_BLOCK_DATA = {
    blocks = {
        { x = 0, y = 0, z = 0, material = "minecraft:cobblestone" },
        { x = 1, y = 0, z = 0, material = "minecraft:stone" },
        { x = 0, y = 1, z = 0, material = "minecraft:stone" },
    },
}

parser_data.SAMPLE_VOXEL_DATA = {
    grid = {
        [0] = {
            [0] = { [0] = "minecraft:oak_log", [1] = "minecraft:oak_log" },
            [1] = { [0] = "minecraft:oak_leaves", [1] = "minecraft:oak_leaves" },
        },
        [1] = {
            [0] = { [0] = "minecraft:oak_leaves", [1] = "minecraft:oak_leaves" },
            [1] = { [0] = "minecraft:air", [1] = "minecraft:torch" },
        },
    },
}

parser_data.EXPECT_BLOCK_DATA = {
    totalBlocks = 3,
    materials = {
        ["minecraft:cobblestone"] = 1,
        ["minecraft:stone"] = 2,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 0 },
    },
}

-- Building Gadgets 2 template, as turtle-blueprints exports it and BG2's Template Manager copies it.
-- statelist walks x fastest, then y, then z: stone floor 3x2, stairs at 0,1,0, glass at 2,1,1.
parser_data.SAMPLE_BG2 = [[
{
  "name": "bg2_sample",
  "statePosArrayList": "{blockstatemap:[{Name:\"minecraft:air\"},{Name:\"minecraft:stone\"},{Name:\"minecraft:oak_stairs\",Properties:{facing:\"north\",half:\"bottom\"}},{Name:\"minecraft:glass\"}],endpos:{X:2,Y:1,Z:1},startpos:{X:0,Y:0,Z:0},statelist:[I;1,1,1,2,0,0,1,1,1,0,0,3]}",
  "requiredItems": { "minecraft:stone": 6, "minecraft:glass": 1, "minecraft:oak_stairs": 1 }
}
]]

parser_data.EXPECT_BG2 = {
    totalBlocks = 8,
    materials = {
        ["minecraft:stone"] = 6,
        ["minecraft:oak_stairs"] = 1,
        ["minecraft:glass"] = 1,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 2, y = 1, z = 1 },
    },
}

-- Same shape written the way Minecraft's SNBT also allows: spacing, single quotes, quoted keys,
-- an escaped quote, a non-zero start corner and cave_air.
parser_data.SAMPLE_BG2_LOOSE = {
    name = "loose",
    statePosArrayList = "{ 'blockstatemap' : [ {Name:'minecraft:cave_air'}, {Name:'minecraft:stone'}, "
        .. "{Name:\"minecraft:oak_stairs\", Properties:{facing:'north', half:'bottom', note:'it\\'s'}}, {Name:'minecraft:glass'} ], "
        .. "startpos:{X:10, Y:64, Z:-3}, endpos:{X:12, Y:65, Z:-2}, "
        .. "statelist:[I; 1, 1, 1, 2, 0, 0, 1, 1, 1, 0, 0, 3] }",
}

parser_data.SAMPLE_BG2_SHORT = {
    name = "short",
    statePosArrayList = "{blockstatemap:[{Name:\"minecraft:air\"},{Name:\"minecraft:stone\"}],endpos:{X:1,Y:0,Z:0},startpos:{X:0,Y:0,Z:0},statelist:[I;1]}",
}

parser_data.FILE_SAMPLES = {
    {
        label = "File Text Grid",
        path = "tmp_sample_grid.txt",
        contents = parser_data.SAMPLE_TEXT_GRID,
        expect = parser_data.EXPECT_TEXT_GRID,
    },
    {
        label = "File JSON",
        path = "tmp_sample_schema.json",
        contents = parser_data.SAMPLE_JSON,
        expect = parser_data.EXPECT_JSON,
    },
    {
        label = "File Voxel",
        path = "tmp_sample_voxel.vox",
        contents = parser_data.SAMPLE_VOXEL,
        expect = parser_data.EXPECT_VOXEL,
        opts = { formatHint = "voxel" },
    },
    {
        label = "File BG2 Template",
        path = "tmp_sample_bg2.json",
        contents = parser_data.SAMPLE_BG2,
        expect = parser_data.EXPECT_BG2,
    },
}

return parser_data
