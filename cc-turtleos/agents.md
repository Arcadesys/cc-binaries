# TurtleOS Agent Guide

TurtleOS is a menu for ComputerCraft turtles. The player picks a role (Farmer, Miner), then a job, sets its options, and starts it. Jobs can be set to start on boot, so a turtle keeps working after a chunk reload or server restart.

## Layout

- `boot.lua`: entry point (`startup.lua` runs it). Adds `/` to `package.path` and calls `core.init()`.
- `install.lua`: downloads the files from GitHub. **Its `FILES` list must name every file under `turtleos/`**; update it when adding or removing one.
- `turtleos/menu.lua`: the menu (main → role → job screen).
- `turtleos/lib/`
  - `core.lua`: runs a start-on-boot job (5 second countdown, any key skips it), then the menu.
  - `jobs.lua`: finds jobs, saves their options, runs them with a status screen and a Q-to-stop listener.
  - `nav.lua`: position tracking relative to the job's start spot, saved on every move.
  - `inv.lua`: inventory helpers (find, refuel, refuel from a chest, unload).
  - `field.lua`: the snake-over-a-field loop shared by the crop and sugar cane jobs.
  - `ui.lua`: drawing helpers sized for the 39x13 turtle screen.
- `turtleos/strategies/<role>/<job>.lua`: one file per job. A folder here is a role in the menu.
- `turtleos/apis/movement.lua`: older movement API, still used by `tree.lua`.
- `tests/`: turtlesim worlds and runners (see below).

Saved state lives in `/.turtleos/` on the turtle: `nav` (position), `options/<role>.<job>`, `progress/<role>.<job>`, `autorun`.

## Job format

```lua
return {
    title = "Crop farm",
    summary = "One line for the job list",
    description = "A paragraph, shown first under How to set up",
    setup = { "1. Step", "2. Step" },
    options = {
        { key = "length", label = "Length", type = "number", default = 9, min = 1, max = 64, step = 1 },
        { key = "side", label = "Field is to the", type = "choice", default = "right", choices = { "right", "left" } },
        { key = "veins", label = "Follow ore veins", type = "bool", default = true },
    },
    estimateFuel = function(opts) return 100 end, -- optional, shown on the job screen
    repeats = true,          -- optional: the fuel estimate is per cycle
    bootResumeOnly = true,   -- optional: on boot, only resume saved progress
    progressText = function(saved, opts) return "branch 3 of 10" end, -- optional: enables Resume
    run = function(opts, ctx) return "Result shown to the player" end,
}
```

`ctx` gives the job: `ctx.opts`, `ctx.resume` (true when continuing after a reboot or Resume), `ctx.status(text)`, `ctx.count(name, n)`, `ctx.log(text)`, `ctx.stopping()`, `ctx.wait(seconds, label)`, `ctx.progress()`, `ctx.saveProgress(table)`, `ctx.clearProgress()`.

Rules for jobs:

- Move with `nav`, never raw `turtle.forward()`, so the position stays saved. `nav.goTo` takes an axis order; pick one that keeps the path inside tunnels or above the field.
- When `ctx.resume` is true, the turtle may be anywhere: go home first.
- Check `ctx.stopping()` at safe points, then go home and return.
- Throw `error("message", 0)` for failures the player should see.

Strategies with only `execute(schema)` (like `tree.lua`) still run: the runner calls `execute` in a loop.

## Testing

[turtlesim](../turtlesim/README.md) runs jobs headless in CraftOS-PC:

```bash
turtlesim/turtle --root cc-turtleos --world cc-turtleos/tests/world_crops.lua cc-turtleos/tests/run_job.lua farmer crops length=5 width=5 cycles=1
turtlesim/turtle --root cc-turtleos --world cc-turtleos/tests/world_cane.lua cc-turtleos/tests/run_job.lua farmer sugarcane length=4 width=3 cycles=1
turtlesim/turtle --root cc-turtleos --world cc-turtleos/tests/world_mine.lua cc-turtleos/tests/run_job.lua miner branch length=24 branch=8
turtlesim/turtle --root cc-turtleos --world cc-turtleos/tests/world_mine.lua cc-turtleos/tests/stop_resume.lua miner branch 150 length=24 branch=8 hard
turtlesim/turtle --root cc-turtleos --world empty --key enter --key enter cc-turtleos/tests/preview.lua
```

`cycles=N` (farm jobs only) stops after N cycles. `stop_resume.lua` presses Q after N forward moves (`hard` presses it twice, stopping in place), then resumes. `preview.lua` shows the menu at the real 39x13 turtle size.
