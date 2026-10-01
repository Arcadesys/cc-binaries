# Pine Links — Rogers Bark Municipal Golf

A Pine3D golf game for CC:Tweaked: the Marovitz-inspired Hole 3 from [furball-simulator](https://github.com/Arcadesys/furball-simulator), a par 3 of 162.8 m (178 yd) from the blue tee. It is an original stylized mechanics study, not a survey of the real course: fairway, bunkers, tree lines, out-of-bounds stakes, park path and skyline are fictional dressing.

The shot engine is a line-for-line Lua port of furball's `golf-core.ts` and `course.ts`: the same clubs, launch speeds, lies, tree deflection, bounce, rollout, cup capture and out-of-bounds rule, verified against fixtures generated from the TypeScript. The scene is furball's hole converted to Pine3D meshes.

## Run

Copy this complete `pine-links` folder onto an Advanced Computer. Keep `lib` and `vendor` inside it. No network access is needed at runtime.

```text
/pine-links/golf.lua
/pine-links/golf.lua --terminal
/pine-links/golf.lua --monitor left
/pine-links/diagnostic.lua --terminal
```

The default uses the first attached Advanced Monitor, or the computer screen. Use at least 39 columns × 19 rows; 51×19 works, and a larger monitor gives the 3D scene more room. Smaller displays show a resize prompt.

## Play

Press Space or tap START. You start with furball's default: 5 iron, aim 0°, power 94%. Set club, aim and power, then SWING. Row three shows the calm-weather forecast for the current settings — where the ball will finish, on which lie, or a red out-of-bounds warning — and white diamonds trace it on the course. After each shot the game does what furball does: it aims at the cup, switches to the putter on the green with power scaled to the distance, and to the wedge in sand.

| Club | Carry at 100% | Notes |
|---|---:|---|
| 5 iron | 150 m | 38° loft |
| 7 iron | 115 m | 46° loft |
| Wedge | 48 m | 62° loft; best from sand |
| Putter | 32 m | rolls only |

Rough and sand weaken a shot: rough to 72% power, sand to 50% (83% with the wedge). A ball must roll into the cup slowly; a fast one passes over it. Out of bounds costs a stroke and a penalty, and the shot is replayed from the previous lie. Trees deflect low shots.

| Action | Keyboard | Screen button |
|---|---|---|
| Aim | Left / Right (2° or 0.5° fine) | AIM LEFT / RIGHT |
| Power | Up / Down (5% or 0.5% fine) | POWER − / + |
| Club | Q / E, or C | CLUB − / + |
| Aim at cup | A | AIM CUP |
| Fine adjustments | F | FINE |
| Swing / start | Space or Enter | SWING / START |
| Tee / 3D overview / overhead map | Tab | VIEW |
| Skip shot animation | S | SKIP |
| Help / resume | H | HELP / RESUME |
| Pause / resume | P | MENU / RESUME |
| Restart hole | R | MENU, then RESTART |
| Quit | Backspace | MENU, then QUIT |

The scorecard uses furball's labels (Hole in one!, Birdie!, Par!, +N over par).

## Architecture and tests

`lib/course.lua` and `lib/golf.lua` are the furball kernel and contain no rendering. `lib/physics.lua` runs a shot on a copy of the hole state in bounded batches of 1/120 s ticks and records 20 Hz playback samples; `lib/rules.lua` commits the finished state once. Skipping playback cannot change the result. `lib/render.lua` builds the converted course meshes.

```sh
./tools/test_craftos.sh /tmp/pine-links-results   # core: furball parity, physics, rules, input, app
./tools/test_runtime.sh /tmp/pine-links-runtime   # GUI: keyboard and monitor rounds, resize/detach
```

`tests/furball.lua` replays 125 shots and 200 lie samples from `tests/fixtures/furball_golf.json`. After furball tuning, regenerate fixtures with `../tools/furball-fixtures/update.sh`. `vendor/REVISION.txt` records the pinned Pine3D revision.

The original Pebble Beach hole 7 prototype (terrain mesh, its own physics) is in git history before the furball port; `PLAN.md` and `docs/` describe that prototype.
