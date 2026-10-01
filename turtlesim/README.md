# turtlesim

Run turtle scripts on your Mac against a simulated turtle and world, without Minecraft. It drives [CraftOS-PC](https://www.craftos-pc.cc) headless and swaps in a fake `turtle`, `peripheral` (adjacent chests) and `gps`.

```bash
turtlesim/turtle path/to/script.lua [args...]
```

The script's folder is copied onto the turtle as its disk, so `require` and relative paths work like on a real turtle. Prompts from `read()` are answered with Enter (or `--answer` values), `sleep()` is fast-forwarded, and each run ends with a report: position, fuel, ores mined and missed, failed actions, inventory, and a top-down map.

## Branch mining

`turtle mine` runs cc-factory's safe branch miner (`factory.lua mine`) in the `branchmine` world. That world is solid stone with seeded ore veins and the miner's default bay: a supply chest above the turtle and an output chest below. Any extra arguments go to the factory. The miner's required `--job`, `--home`, `--heading`, `--dimension` and `--bounds-*` arguments are filled in to match the world (bounds sized from `--length` and `--branch-length`), and ENTER is pressed to confirm the start screen.

```bash
turtlesim/turtle mine --length 48 --branch-interval 3 --branch-length 12
turtlesim/turtle mine --seeds 1-8 --length 48     # 8 ore layouts in parallel, one table
turtlesim/turtle mine --fleet 4 --length 48       # 4 turtles side by side; flags shared tunnels
```

The miner caps jobs at `--length 256` and `--branch-length 64`. If a run stops early, the report's **last screen** shows the miner's status page and its reason (for example `NEEDS HELP` with a supply or receiver problem).

Key report lines:

- **mined**: ore blocks the turtle dug.
- **missed**: ore still touching the tunnel afterwards. This should be 0.
- **ores per 100 fuel**: the efficiency number to tune `--branch-interval` and `--branch-length`.
- **failed actions**: placement, refuel and drop calls that returned false. Routine bumps and empty digs aren't counted.

## Programs that wait for input

Headless runs answer `read()` with Enter, or the `--answer` values in order. Programs that wait for key events instead get the `--key NAME` presses, one per second (CC `keys` names, e.g. `enter`, `q`). If nothing happens for `--idle` seconds (default 10), meaning no turtle action and no output, the run stops and says so. Use `--ui` to drive a program yourself in the CraftOS-PC window.

Timers and `sleep()` are fast-forwarded, so a program pacing itself with `os.startTimer` runs at full speed. Pass `--real-time` if timing matters.

## Building a schema

Run cc-factory's schema builder on a blueprint kept outside `cc-factory/`, and get the result as JSON:

```bash
turtlesim/turtle --world my_world.lua --file my.txt:/my.txt \
  --results out/ --dump-blocks cc-factory/factory.lua my.txt
```

- `--file SRC:DEST` copies a file onto the turtle's disk (repeatable).
- `--results DIR` keeps `summary.json`, `status.json`, `output.txt` and `actions.txt` after the run.
- `--dump-blocks` adds `blocks` to `summary.json`: every placed or scripted block as `[x, y, z, name, facing?]`.
- The builder only counts the turtle's own inventory, so put every material (and fuel) in the world's `turtle.inventory` or pass `--give`.
- With the default origin (north), blueprint `(x, y, z)` is built at world `(-(x+1), y, z+1)`, with y at the turtle's own level: mirrored left to right and behind-left of the turtle.
- The exit status only says the run did not crash. Judge a build by comparing `blocks` with the blueprint.

## Other commands

```bash
turtlesim/turtle harness              # every cc-factory harness_*.lua, headless, PASS/FAIL table
turtlesim/turtle harness movement     # just one
turtlesim/turtle worlds               # list bundled worlds
turtlesim/turtle --world quarry --trace turtlesim/examples/stairs.lua 8
```

Useful options: `--world NAME|FILE`, `--seed N`, `--fuel N|unlimited`, `--give coal:16`, `--answer TEXT`, `--key NAME`, `--trace` (log every turtle action), `--ui` (open the CraftOS-PC window to watch and type), `--keep` (keep the temp emulator folder). Run `turtlesim/turtle --help` for all of them.

The report also lists every container that holds items and the program's last screen.

cc-factory also has its own regression suite with a purpose-built simulator, `cc-factory/tests/run.py` (see `cc-factory/SAFE_MINING.md`). turtlesim is the general-purpose runner: any script, editable worlds, and scale comparisons.

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
