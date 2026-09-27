# Pine Links — Hole 7 practice

An unofficial, original low-poly Pebble Beach hole 7 game for CC:Tweaked, rendered by Pine3D. Blue tees: 107 yards, par 3. This build covers milestones 0–2 only. Terrain, slopes, coastline, and pin position are documented approximations.

## Run

Copy this complete `pine-links` folder onto an Advanced Computer. Keep `lib`, `vendor`, and `courses` inside it. No network access is needed at runtime.

```text
/pine-links/golf.lua
/pine-links/golf.lua --terminal
/pine-links/golf.lua --monitor left
/pine-links/diagnostic.lua --terminal
```

The default uses the first attached Advanced Monitor, or the computer screen. A named monitor can be selected explicitly. Existing startup programs are preserved; launch this from the shell when desired.

Use at least 39 columns × 19 rows. A 51×19 Advanced Computer works; a larger monitor gives the 3D scene more room. Smaller displays show a resize prompt. Preserve a comfortable text size when choosing a monitor wall or emulator window size.

## Play

Press Space or tap START. Set club, aim, and power, then SWING. The game aims toward the cup after each shot; adjust left or right to choose another line. Power is untimed. The wedge flies; the putter rolls. FINE switches between 3-degree / 5-percent steps and 0.5-degree / 1-percent steps. Blue-tee distance is measured horizontally in game yards.

| Action | Keyboard | Screen button |
|---|---|---|
| Aim | Left / Right | AIM LEFT / RIGHT |
| Power | Down / Up | POWER − / + |
| Club | Q / E | CLUB − / + |
| Fine adjustments | F | FINE |
| Swing / start | Space | SWING / START |
| Tee / fixed 3D overview / overhead map | Tab | VIEW |
| Skip shot animation | S | SKIP |
| Help / resume | H | HELP / RESUME |
| Pause / resume | P | MENU / RESUME |
| Restart practice | R | MENU, then RESTART |
| Quit | Backspace | MENU, then QUIT |

All essential monitor actions use separate taps. No dragging, held buttons, or keyboard modifiers are required. Menus pause the simulation/playback. A resize or monitor detachment pauses safely; resume from the remaining screen.

Each executed swing counts once. Water or out-of-bounds adds one penalty and returns the ball to the pre-shot lie. These are simplified arcade rules. Restart begins fresh practice; there are no saved records or full-course rounds in this milestone. The extra Test club is for collision diagnostics.

## Architecture and tests

`lib/course.lua`, `lib/physics.lua`, and `lib/rules.lua` contain no rendering dependencies. The canonical tagged triangles provide both the terrain samples and visible ground. Shots use fixed 1/60-second steps in bounded batches; cached playback can be skipped without changing scoring or the final lie. The renderer and input adapter are isolated from simulation.

Run the pure-module suite in CraftOS from the game directory with `tests/run.lua`. On macOS, the included runner uses the installed CraftOS-PC executable and an isolated data directory:

```sh
./tools/test_craftos.sh /tmp/pine-links-results
```

See [validation](docs/VALIDATION.md) for executed checks, measured results, and pending Minecraft checks; [source notes](docs/REFERENCES.md) for observed versus inferred geometry; [original specification](PLAN.md) for milestone scope. The [top-down preview](docs/preview/hole-07-top-down.svg) is generated from the runtime mesh source. `vendor/REVISION.txt` records the pinned Pine3D revision and dependency.
