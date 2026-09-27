# Pine Lanes integration contract

## Scope and ownership

One lane, 1–4 local players taking turns by frame, ten-pin scoring, position/aim/power/hook, deterministic arcade contacts, real Pine3D, keyboard and Advanced Monitor. No networking, saves, sound, custom names, or oil patterns. Base commit: `0aefec5`. Three Luna workers at medium effort; coordinator owns integration. Preserve Pine Links and existing programs without extracting a shared framework.

| Owner | Files |
|---|---|
| Luna A — Physics | `lib/lane.lua`, `lib/physics.lua`, `tests/physics.lua`, `docs/CALIBRATION.md` |
| Luna B — Rules | `lib/rules.lua`, `tests/rules.lua` |
| Luna C — Presentation | `lib/render.lua`, `lib/ui.lua`, `lib/input.lua`, `tests/input.lua`, `tests/display.lua` |
| Coordinator | Launcher, controller, integration tests, runners, remaining docs, packaging |

## Units and poses

Meters: X down the lane, Y up, Z right. Aim is radians toward +X; positive hook bends toward +Z. Power is .25–1, position is −.38–+.38, hook is −1–1. Pin IDs use standard numbering 1–10. A pose is `{id,x,z,angle,tilt,down}`: angle is the fall direction in the X/Z plane, tilt is 0 upright to π/2 flat. Rendering never decides knockdown.

## Physics

`lane.newRack()` returns fresh poses. Public constants include `width`, `headX`, `pinSpacing`, `pinRadius`, `pinHeight`, `ballRadius`, and `endX`.

- `physics.begin(rack, shot)` → simulation, or nil/error.
- Shot: `{deliveryId,position,aim,power,hook}`.
- `physics.advance(sim, stepBudget)` → completion boolean.
- `sim.trajectory`: immutable 30 Hz snapshots `{t,ball={x,y,z,gutter},pins={poses...}}`, including the initial state.
- `sim.result`: `{deliveryId,status='ok'|'error',knocked={ids...},standing={poses...},duration,error?}`.
- Successful knocked and standing IDs exactly partition the input rack.
- `physics.simulate(rack,shot)` is a synchronous test/calibration helper returning result and trajectory.

Fixed 1/120-second steps, bounded batches, adaptive contact subdivisions. Fallen pins remain colliders during the delivery; surviving poses are retained. Gutters lock out all later pin contact. Hook stops after first pin contact. Numerical errors and timeouts produce an error result. No terminal, peripheral, renderer, or wall-clock dependencies.

## Rules

`rules.new(playerCount)` → match or nil/error. Match exposes `{playerCount,currentPlayer,frame,ballNumber,rack,complete,players,lastDeliveryId}`.

`rules.apply(match,deliveryId,result)` → accepted boolean/error. Validate success status, IDs, finite surviving poses, and legal counts before any mutation. Duplicate delivery IDs are rejected without changes. Accepted deliveries advance rack and turn immediately; tenth-frame bonus deliveries remain with that player. The controller retains a separate roll summary for the result screen.

`rules.score(player)` → `{frames,total,pending}`. Each of ten frame entries has `{rolls,marks,score?,cumulative?}`. Unresolved bonuses have no final frame/cumulative score; total is the resolved subtotal. Marks are `X`, `/`, `-`, or numbers.

`rules.rankings(match)` → `{player,total,place}` entries, with shared placing for ties. Rules depend only on lane definitions, never on rendering or time.

## Presentation and input

`render.new(target)` returns an object with `draw(view)`, `close()`, and current `buttons`. The controller redirects the terminal before construction. Rendering consumes the view without changing game state.

View fields: phase, playerCount, currentPlayer, frame, ballNumber, settings, selected, fine, camera, scorePlayer, snapshot, scorecards, rankings, message, lastInput, diagnostic, and optional rollSummary `{player,frame,ballNumber,count,knocked}`.

Cameras: `lane`, `deck`, `score`. Phases: SETUP, AIM, SIMULATE, PLAYBACK, RESULT, FINAL, HELP, PAUSED.

`ui.layout(w,h,phase,camera)` returns rectangles `{id,label,x,y,w,h}`. `input.action(event,buttons,monitorName)` returns an action or nil. Foreign monitor touches are ignored. Pointer input and keyboard input share the same actions. Repeat key events and rapidly repeated primary actions are rejected.

Keyboard: 1–4 select parameters; Up/Down select parameter or scorecard player; Left/Right adjust; Space starts, rolls, or continues; Tab changes view; F toggles fine; H help; P menu; S skip; R restarts in menu/final; Backspace quits in menu/final or the small-screen fallback.

Minimum 39×19; normal targets are at least two rows tall. Small displays retain resize instructions and quit. Text/numbered pin diagrams supplement color. Help and pause preserve game state. Palette, terminal redirect, text/background colors, and cursor blink are restored on normal and error exits.

## Controller

Flow: setup → aim → simulate → playback → result → continue → aim/final. Settings persist per player. Restart begins a fresh match with the same player count. Result commit happens exactly once; skipping only changes presentation. Errors return to AIM with rack and score unchanged.

Simulation advances up to 120 fixed steps per 0.1-second event-loop tick. Playback uses the 30 Hz cache at a 10 Hz display target. Resize polling complements events; detachment falls back to the computer terminal and pauses. Optional `--log` captures local validation receipts, not saved progress.
