# Pine Ball — Rogers Bark Municipal Field

Arcade baseball for CC:Tweaked, rendered with Pine3D. It runs the tuned baseball engine from [furball-simulator](https://github.com/Arcadesys/furball-simulator): the same pitches, swing timing windows, contact tiers, spray, outcome weights, fielding and catch plans, base running, innings and walk-offs, ported line for line to Lua and verified against fixtures generated from the TypeScript. The stadium is furball's Rogers Bark Municipal Field converted to Pine3D meshes. Players are simple team-coloured pawns; the furball character avatars are not converted.

## Run

Copy the complete `pine-ball` folder to an Advanced Computer and run:

```text
/pine-ball/ball.lua
/pine-ball/ball.lua --terminal
/pine-ball/ball.lua --monitor left
/pine-ball/ball.lua --duel --innings 5 --seed 123
```

The default uses the first attached Advanced Monitor, otherwise the computer screen. Minimum 39×19; 51×19 or larger is recommended. `--seed` replays the same CPU pitches, contact rolls and catch rolls. `--log FILE` writes local JSON receipts of deliveries, swings and plays.

## Play

Choose CPU (the computer pitches; pass the keyboard between batters, like furball) or a 2-player duel, set 1–9 innings, then PLAY BALL. Light visits and bats first; Dark is home. Each team is furball's nine placeholder players with their numbers and batting hands.

**Batting.** Press Space just before the ball reaches the plate. As in furball, the bat crosses the plate 80 ms after the press, and quality is judged from that crossing: within 25 ms is perfect, 60 ms good, 110 ms weak; outside that you whiff. Pitches outside the zone narrow those windows, and beyond 1.6 zone-widths they cannot be hit. Weak contact is often fouled off. Swing early to pull, late to go the other way. Hold the arrows while you swing to aim: Left/Right toward that field, Up to lift (more fly balls and extra bases), Down to chop (more grounders). Taking a pitch gives a ball or a called strike.

**Fielding** follows furball's rules: the nearest fielder chases each hit; fly balls roll a catch plan (reaction 180 ms, 9 m/s, 94% hands), so a fly can be dropped (error, safe at first) or reached late (single). Grounders go to first, or to second for the force.

**Duel.** The batting player swings as above. The pitching player shares the keyboard: 1–4 choose fastball, changeup, curve left or curve right; W/A/S/D move the target in quarter-zone steps (up to 1.5 zones out); E throws. Roles swap each half inning.

| Action | Keyboard | Screen button |
|---|---|---|
| Swing / skip intro / play again | Space | SWING |
| Aim (hold) | Arrows | AIM (cycle), LIFT/LEVEL/CHOP |
| Pitch type / spot / throw (duel) | 1–4 / WASD / E | type, < > ^ v, THROW |
| Setup: mode / innings | M or Up/Down / Left/Right | MODE, INN −/+ |
| Help, menu | H, P | HELP, MENU |
| New game | R in menu or final | NEW GAME |
| Quit | Backspace in menu, setup or final | QUIT |

Menus and resizing pause the game clock, so a pause never costs a pitch.

**Timing in Minecraft.** The windows are furball's, measured with `os.epoch("utc")` when the key event arrives. A server delivers input on 50 ms ticks, so perfect contact is harder in-world than in a browser; good and weak contact remain reachable.

## Code and tests

| File | Role |
|---|---|
| `lib/rng.lua` | mulberry32, bit-exact with furball |
| `lib/baseball.lua` | Kernel: constants, pitch/swing resolution, CPU pitcher, game reducer, catch plans |
| `lib/plays.lua` | Furball match rules: landing spots, fielder pursuit, catch conversions, runner paths, headlines |
| `lib/app.lua` | Match flow on a pausable clock and the event loop |
| `lib/stadium.lua`, `lib/render.lua`, `lib/ui.lua`, `lib/input.lua` | Converted meshes, Pine3D view, HUD and controls |

```sh
./tools/test_craftos.sh /tmp/pine-ball-results
```

The core suite checks furball parity (400 pitch resolutions, 50 CPU pitches, 612 reducer steps over six full games, 40 catch plans, fielding seed), the fielding layer, input, the controller (perfect swing matches the kernel, walks/strikeouts end a half, pause freezes deadlines, duel pitches, a full game reaches FINAL) and Pine3D display layouts at 39×19, 51×19 and 82×40. `tests/smoke.lua` drives the live event loop with real timers and queued keys. After furball tuning, regenerate fixtures with `../tools/furball-fixtures/update.sh`.

Not yet run inside Minecraft.
