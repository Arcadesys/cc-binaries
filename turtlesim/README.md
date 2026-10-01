# turtlesim

Run turtle scripts on your Mac against a simulated turtle and world, without Minecraft. It drives [CraftOS-PC](https://www.craftos-pc.cc) headless and swaps in a fake `turtle`, `peripheral` (adjacent chests) and `gps`.

```bash
turtlesim/turtle path/to/script.lua [args...]
```

The script's folder is copied onto the turtle as its disk, so `require` and relative paths work like on a real turtle. Prompts from `read()` are answered with Enter (or `--answer` values), `sleep()` is fast-forwarded, and each run ends with a report: position, fuel, ores mined and missed, failed actions, inventory, and a top-down map.

## Branch mining

`turtle mine` runs cc-factory's branch miner (`factory.lua mine`) in the `branchmine` world: solid stone with seeded ore veins and a supply chest behind the turtle. Any extra arguments go to the factory.

```bash
turtlesim/turtle mine --length 64 --branch-interval 3 --branch-length 12
turtlesim/turtle mine --seeds 1-8 --length 64     # 8 ore layouts in parallel, one table
turtlesim/turtle mine --fleet 4 --length 64       # 4 turtles side by side; flags shared tunnels
```

Key report lines:

- **mined**: ore blocks the turtle dug.
- **missed**: ore still touching the tunnel afterwards. This should be 0.
- **ores per 100 fuel**: the efficiency number to tune `--branch-interval` and `--branch-length`.
- **failed actions**: placement, refuel and drop calls that returned false. Routine bumps and empty digs aren't counted.

## Other commands

```bash
turtlesim/turtle harness              # every cc-factory harness_*.lua, headless, PASS/FAIL table
turtlesim/turtle harness movement     # just one
turtlesim/turtle worlds               # list bundled worlds
turtlesim/turtle --world quarry --trace turtlesim/examples/stairs.lua 8
```

Useful options: `--world NAME|FILE`, `--seed N`, `--fuel N|unlimited`, `--give coal:16`, `--answer TEXT`, `--trace` (log every turtle action), `--ui` (open the CraftOS-PC window to watch and type), `--keep` (keep the temp emulator folder). Run `turtlesim/turtle --help` for all of them.

## Worlds

A world is a Lua file that returns a table. See [`worlds/`](./worlds) for examples:

```lua
return {
    seed = 1,
    turtle = { x = 0, y = 11, z = 0, facing = "north", fuel = 2000,
               inventory = { [1] = "minecraft:coal:32" } },
    floor = "minecraft:stone", floorY = 64,          -- solid below this height
    ores = { { "minecraft:iron_ore", chance = 0.012, drops = "minecraft:raw_iron" } },
    blocks = { { 0, 11, 1, { name = "minecraft:chest", items = { "minecraft:coal:64" } } } },
    fill = { { -16, -9, -16, 16, -9, 16, "minecraft:bedrock" } },
    -- Act out "place a block" style prompts for scripts that ask a human:
    prompts = { { "Place a chest", function(world) world:setSide("front", "minecraft:chest") end } },
}
```

Coordinates follow Minecraft: north is −z, east is +x, up is +y. Item names without a namespace get `minecraft:` added.

## Limits

- One turtle per world. Fleet mode runs separate worlds and compares their tunnels.
- There are no mobs, gravity blocks or liquids. `attack()` always finds nothing.
- Torches and other blocks can be placed in any air space with no support check.
- Needs CraftOS-PC at `/Applications/CraftOS-PC.app`; set `CRAFTOS_BIN` if it lives elsewhere.
