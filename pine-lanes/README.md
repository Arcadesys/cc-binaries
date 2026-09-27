# Pine Lanes

A standalone, unofficial arcade bowling game for CC:Tweaked, using the bundled Pine3D renderer. One lane, 1–4 local players, a full ten-frame match, and adjustable position, aim, power, and hook.

Copy the complete `pine-lanes` folder to an Advanced Computer. Launch `/pine-lanes/bowl.lua`; use `--terminal` to select the computer or `--monitor left` to select a named Advanced Monitor. By default the first attached color monitor is used. No downloads are required at runtime. Existing startup programs are untouched.

Use a screen of at least 39×19 characters; 51×19 or larger is recommended. Choose a comfortable physical text size. The game pauses after resizing or monitor detachment. Resume from the remaining display.

## Play

Choose 1–4 players, then START. Players are labeled Player 1–4 and take turns by frame. Select POSITION, AIM, POWER, or HOOK and adjust it, then ROLL. Hook is an arcade curve: negative bends left and positive bends right. The ball curves more farther down the lane, until its first pin contact. Settings are retained separately for each player. Shot selection is untimed.

| Setting | Default | Range | Coarse / fine step |
|---|---:|---:|---:|
| Position | Center | −0.38 to +0.38 m | 0.05 / 0.01 m |
| Aim | Straight | −8° to +8° | 1° / 0.25° |
| Power | 75% | 25–100% | 5 / 1 percentage points |
| Hook | 0% | −100 to +100% | 10 / 2 percentage points |

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

This is deterministic arcade physics, not a certified bowling simulator. Pin toppling is computed by the simulation and displayed by Pine3D; there are no scripted strikes. No network play, saved games, custom player names, sounds, changing oil patterns, or loft/foul controls are included.

## Development and verification

Pure lane, physics, and rules modules are separate from rendering. Fixed 1/120-second simulation runs in bounded batches, records 30 Hz playback snapshots, and displays at a 10 Hz target. Collision subdivisions limit movement relative to contact size. Skipping the animation cannot change a roll. Numerical failures cancel without altering the score or rack.

Run `tools/test_craftos.sh RESULT_DIRECTORY` for core tests or `tools/test_runtime.sh RESULT_DIRECTORY` for GUI CraftOS-PC integration tests. They use isolated emulator directories. The runtime tests require GUI monitor emulation. In CraftOS, launch `tests/run.lua` from the game folder for the core checks.

`--diagnostic` starts a labeled lane inspection; `--log /path.jsonl` records explicit local playtest receipts. Logs are opt-in and are not saved match progress.

See `docs/CONTRACT.md` for module ownership/interfaces, `docs/CALIBRATION.md` for physics settings and playable fixtures, and `docs/VALIDATION.md` for actual executed checks and remaining target-pack validation. Vendor revision and license are in `vendor/REVISION.txt` and `vendor/LICENSE`.
