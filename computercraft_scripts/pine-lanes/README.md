# Pine Lanes

A standalone arcade bowling game for CC:Tweaked, using the bundled Pine3D renderer. One lane, 1–4 local players, a full ten-frame match, and adjustable position, aim, power, and hook.

The bowling engine is a line-for-line Lua port of the tuned [furball-simulator](https://github.com/Arcadesys/furball-simulator) kernel (`src/sports/bowling/sim`): the same ball path, gutter lockout and collision-driven pin deck, verified against fixtures generated from the TypeScript. The scene is furball's Rogers Bark Bowling Club converted to Pine3D meshes: lathe pins with red neck stripes, home lane 8 between two dressed neighbours, half-round gutters, kickbacks, masking unit, pit, benches, ball return and score monitors.

Copy the complete `pine-lanes` folder to an Advanced Computer. Launch `/pine-lanes/bowl.lua`; use `--terminal` to select the computer or `--monitor left` to select a named Advanced Monitor. By default the first attached color monitor is used. No downloads are required at runtime. Existing startup programs are untouched.

Use a screen of at least 39×19 characters; 51×19 or larger is recommended. Choose a comfortable physical text size. The game pauses after resizing or monitor detachment. Resume from the remaining display.

## Play

Choose 1–4 players, then START. Players are labeled Player 1–4 and take turns by frame. Select POSITION, AIM, POWER, or HOOK and adjust it, then ROLL. The yellow chevrons on the lane preview the exact path the engine will roll (red once it drops into a gutter). Aim is furball's launch angle; hook is its spin: negative bends left and positive bends right, more strongly past the first third of the lane. Under 20% power the ball stops short. Settings are retained separately for each player. Shot selection is untimed.

All four settings use furball's control units.

| Setting | Default | Range | Coarse / fine step |
|---|---:|---:|---:|
| Position | 0 | −100 to +100 | 10 / 2 |
| Aim (launch angle) | 0 | −100 to +100 | 5 / 1 |
| Power | 60 | 0–100 | 5 / 1 |
| Hook (spin) | 0 | −100 to +100 | 10 / 2 |

Furball's pocket shot — position −32, aim +10, power 100 — strikes from a fresh rack.

| Control | Keyboard | Tap |
|---|---|---|
| Select shot parameter | 1–4, or Up / Down | Parameter name |
| Adjust selected value | Left / Right | − / + |
| Fine adjustments | F | FINE |
| Start, roll, continue | Space | START / ROLL / CONTINUE |
| Lane / pin-deck / scorecard view | Tab | VIEW |
| Scorecard player | Up / Down in score view | Previous / next player |
| Skip animation | S | SKIP |
| Help | H | HELP |
| Pause / resume | P | MENU / RESUME |
| Restart match | R in help/menu/final screen | RESTART |
| Quit | Backspace in menu/final screen | QUIT |

After each roll, inspect the pin count and choose CONTINUE. Standing pins remain where they settled for the second delivery; fallen pins are cleared. The tenth frame awards the standard spare/strike bonus deliveries. Pending bonuses are identified in the scorecard, and tied totals share a placing. Restart keeps the current player count but resets the match and shot settings.

This is deterministic arcade physics, not a certified bowling simulator. Pin toppling is computed by the simulation and displayed by Pine3D; there are no scripted strikes. Each delivery is seeded `matchSeed + deliveryNumber`, as in furball; `--seed N` replays a match exactly. Upright pins never move in the furball deck, so a second ball faces the survivors on their spots. No network play, saved games, custom player names, sounds, changing oil patterns, or loft/foul controls are included.

## Development and verification

`lib/rng.lua` (mulberry32) and `lib/pindeck.lua` are the furball kernel; `lib/physics.lua` keeps the Pine contract over it, `lib/lane.lua` maps furball scene units to Pine axes, and `lib/alley.lua` holds the converted meshes. The kernel's fixed 1/120-second steps run in bounded batches, record 30 Hz playback snapshots, and display at a 10 Hz target. Skipping the animation cannot change a roll. Numerical failures cancel without altering the score or rack. `tests/furball.lua` checks the port against `tests/fixtures/furball_bowling.json`; regenerate it after furball tuning with `../tools/furball-fixtures/update.sh`.

Run `tools/test_craftos.sh RESULT_DIRECTORY` for core tests or `tools/test_runtime.sh RESULT_DIRECTORY` for GUI CraftOS-PC integration tests. They use isolated emulator directories. The runtime tests require GUI monitor emulation. In CraftOS, launch `tests/run.lua` from the game folder for the core checks.

`--seed N` replays a match; `--diagnostic` starts a labeled lane inspection; `--log /path.jsonl` records explicit local playtest receipts. Logs are opt-in and are not saved match progress.

See `docs/CONTRACT.md` for module ownership/interfaces, `docs/CALIBRATION.md` for physics settings and playable fixtures, and `docs/VALIDATION.md` for actual executed checks and remaining target-pack validation. Vendor revision and license are in `vendor/REVISION.txt` and `vendor/LICENSE`.
