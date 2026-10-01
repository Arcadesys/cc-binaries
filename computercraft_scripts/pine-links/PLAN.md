> **Historical.** This describes the original Pebble Beach hole 7 prototype. Pine Links now runs furball-simulator's Marovitz-inspired Hole 3 and golf kernel; see `README.md`.

# Pine Links: Pebble Beach implementation plan

**Target:** An original, flat-shaded golf game running entirely inside CC:Tweaked with Pine3D.

**Prepared:** 2026-09-27. **Status:** Implementation specification, not an implemented or benchmarked game.

**First release goal:** Finish a playable recreation of hole 7. **Full release goal:** Play an 18-hole round based on the real Pebble Beach layout, with reliable scoring and saved progress.

## 1. Lock the scope

Build a small arcade golf game, not a general game engine or a physical Minecraft golf course. The player chooses a club, aims, sets power, shoots, watches the ball, and plays from its new lie until it is holed. Then the scorecard advances.

Use the actual course as the level-design reference. Preserve each hole's routing, bends, broad proportions, green position, significant bunkers, coastline, and important elevation changes. Simplify outlines and slopes for the display and computational budget. This is an approximate low-poly recreation, not surveyed terrain or a replica of any particular historic golf video game.

Use original code, meshes, sound cues, and presentation. Do not import another game's ROM, models, textures, audio, or interface artwork. Describe the course recreation as unofficial; do not present it as an endorsed product.

Do not put these on the critical path: construction turtles, physical golf equipment, an entire Minecraft resort, network multiplayer, live weather, real-time course downloads, advanced spin simulation, animated human golfers, a general-purpose level editor, or a browser port.

The game must be playable on a computer terminal before building its decorative cabinet. A cabinet or clubhouse is an optional Minecraft shell around a finished program.

## 2. Platform facts and the first technical gate

Pine3D is a rendering library, not a complete game engine. It provides the scene/camera/rendering layer; this project must supply gameplay, collision, physics, input mapping, scoring, and persistence. The author's listing explicitly distinguishes rendering from game-engine functionality. [R1]

Pine3D's models are lists of colored polygons, and its model guide supports hand-authored or programmatically generated geometry. It does not render conventional textures. Use flat-colored terrain and small, original low-poly props rather than a texture pipeline. [R2]

CC terminals have 16 simultaneous palette slots, which can be recolored. Advanced monitors support color and act as terminal redirects. Their touch event reports the monitor identity and character coordinates. Treat an in-world monitor as a tap interface, not as a mouse-drag surface. [R3, R4, R5]

### Target configuration

Start with one Advanced Computer. Support an optional, modest-sized Advanced Monitor wall, with one optional speaker. Do not require Advanced Peripherals, external graphics mods, a modem, or another factory mod.

Record the actual ATM10 version, Minecraft version, CC:Tweaked version, monitor dimensions, text scale, and relevant server limits during the first in-world check. No particular ATM10 installation or monitor configuration has been inspected for this plan.

### Milestone 0: prove the display path

Implement a diagnostic program that can load Pine3D, render an original flat terrain tile, a flag, and a moving ball marker, and accept one keyboard action and one monitor-touch action.

Choose and record an exact Pine3D revision plus every required dependency and its license. Do not silently fetch a moving `main` branch whenever the game starts. The documentation's installer downloads dependencies as well as the library, so packaging only the file named Pine3D is not sufficient evidence of a working installation. [R6]

Use a small renderer adapter around documented operations such as `Pine3D.newFrame`, `frame:newObject`, `frame:setCamera`, `frame:drawObjects`, `frame:drawBuffer`, and `frame:map3dTo2d`. Confirm behavior against the pinned implementation rather than assuming documentation examples are flawless. [R7]

Verify axis orientation with labeled axes, polygon winding, near-plane clipping, scene/HUD coordinate conversion, palette restoration, resize handling, and terminal redirection. Initialize the frame after selecting its display target. Restore the original terminal on error or exit. Terminal redirection is a documented CC capability. [R8]

**Completion gate:** A screenshot or capture of the test running inside the target Minecraft pack, keyboard/tap inputs working, and a short benchmark record. An emulator-only result is not an in-world compatibility test.

## 3. Real-course reference and data policy

### Pin one scorecard

Use the **2026 official scorecard, Blue tees: 6,801 yards, par 72**. The verified metadata is supplied in `course_manifest.json`. It includes the 18 hole numbers, pars, and listed yardages, but no invented geometry. Hole 7 is 107 yards on this card. [R9]

Use this PDF as the authority for numerical metadata. The official course webpage is useful for descriptions and photographs, but does not match every card value: for example, its hole 15 description lists 393 yards while the selected card lists 392. Keep the card's value. Do not combine different tee colors or tournament pars. [R9, R10]

### Geometry sources and authoring

Use the official course map/routing, per-hole map views where accessible, and photographs as visual references. The scorecard includes a schematic routing diagram; it is not a precision overhead survey. The course webpage links map views and photographs. [R9, R10]

For each hole, the implementation agent must inspect the actual reference image before creating the layout. Record the source, date or reference era where known, and what is directly observed versus approximated. The goal is recognizability, not invented precision.

Author these elements: tee; intended playing-line waypoints; green boundary; a fixed, playable cup position; fairway/rough/bunker boundaries; coastline or other hazards; a few major height controls; and only the trees or obstacles that affect shot choices.

Scale the intended playing line to the selected scorecard distance. For a dogleg, do not force the straight tee-to-cup distance to equal the scorecard length. Preserve the bend and use the routed centerline as the scale reference. Treat the exact pin position and most slope values as authored approximations unless better evidence is available.

Use a consistent source era wherever practical. When a map and a photograph conflict, record the discrepancy and choose deliberately. If an important layout cannot be seen, mark the geometry blocked or unverified instead of generating a generic hole and calling it accurate.

**The coding agent owns the first-pass geometry. Austen should review a top-down preview and a tee-camera screenshot, not be assigned eighteen manual modeling exercises.**

### Build the holes in this order

| Order | Hole | What it must prove |
|---|---:|---|
| First playable | 7 | A full tee-to-cup loop with coastline, bunkers, downhill terrain, and putting. |
| Long-shot check | 1 | Par-4 progression, multiple lies, club selection, and a bent playing line. |
| Long-hole check | 18 | Par-5 progression, coastal risk, and a strategically relevant tree obstacle. |
| Terrain stress check | 8 | Airborne travel over a gap, cliff collision, and no invisible ground across water. |
| Content completion | Remaining 14 | Distinct source-based layouts using the established engine and schema. |

These selections are based on the official hole descriptions and imagery. The recommended order is a development decision, not the order of a full round. Full-round mode uses holes 1 through 18. [R10, R11]

After hole 8, handle the substantial elevation at 6, the elevated green at 14, and the shaped green at 17 early in the remaining content pass. Keep the descriptions and geometry at an approximate arcade level. [R10]

## 4. Course representation: one source for appearance and collision

Use yards as the canonical unit, a local coordinate system per hole, and seconds for simulation. Define canonical `x/z` as the ground plane and `y` as height. Translate to Pine3D conventions inside the renderer adapter if required. Rotating a hole for authoring must also rotate its wind and directional metadata.

Each authored hole is a small data file, not a hand-written scene program. Keep metadata separate from geometry status. A metadata-only hole must not appear in the playable-hole selector.

### Proposed data contract

| Field | Meaning |
|---|---|
| `schema_version`, `id`, `geometry_revision` | Stable identity and migration boundary. |
| `par`, `listed_yards`, `tee_set` | Verified scorecard metadata. |
| `source_refs`, `approximation_notes` | Provenance and known simplifications. |
| `tee`, `cup`, `playing_line` | Canonical positions and distance-calibration route. |
| `surface_regions`, `elevation_controls` | Authored ground materials and coarse topography. |
| `terrain_vertices`, `terrain_triangles` | Compiled, material-tagged collision/render geometry. |
| `hazards`, `bounds` | Water, out-of-bounds, and a generous simulation safety envelope. |
| `obstacles` | Sparse primitives with matching visible props. |
| `camera_hints` | Tee framing and useful green framing. |
| `verification_status` | Unverified, reference-reviewed, or playtested. |

No coordinates in this handoff are real-world measurements; geometry authoring is still to be done.

### Compilation approach

Create a small host-side tool that validates the authoring data, emits a triangulated terrain surface, generates a top-down debug preview, and produces runtime data plus a simple spatial index. It may be Python or another convenient development tool; the installed game must need only Lua and its bundled assets.

For the first hole, explicit hand-authored vertices and triangles are acceptable. Do not postpone the playable hole to build a universal polygon compiler. Add reusable region-to-mesh generation only as it reduces work on holes 1 and 18.

The canonical terrain mesh is a piecewise planar height surface with material tags. Sample height and normal from its containing triangle using barycentric interpolation. Use the same vertices and boundaries for the visible terrain. Visual-only coastline skirts and distant scenery must not create hidden support surfaces.

Never place a continuous collision plane under a visible ocean gap. Split playable terrain at the shoreline. Water has its own level and hazard behavior. Cliffs can be represented by steep boundary faces and an unplayable region below; overhang simulation is outside scope.

Do not use stacked, coplanar fairway/green/bunker meshes as the primary surface model. Shared edges and material-tagged triangles avoid ambiguous collision and overlapping surfaces. Bake triangulation and lookup data offline rather than rebuilding it every frame.

Trees that matter to play get simple trunk/canopy collision primitives with reasonable correspondence to their visible shape. Decorative distant trees have no gameplay role. No invisible forest walls.

**Completion gate:** A point labeled BUNKER in the HUD is visibly in the bunker; the green's visible slope agrees with putting behavior; a water gap cannot support the ball.

## 5. Gameplay and controls

### First playable feature set

Include a wedge and putter initially, plus a selectable test club for exaggerated collision tests. Add a small club bag for the three-hole build: driver, wood, long iron, mid iron, short iron, pitching wedge, sand wedge, and putter. Keep club definitions in data.

Use explicit, untimed power selection by default. Optional timing-based swing modes can come later, without replacing the accessible default. There is no need for a golfer animation before the ball game is working.

| Action | Keyboard | In-world monitor |
|---|---|---|
| Aim left/right | Left/right arrows | Large left/right buttons |
| Set power | Up/down arrows | Minus/plus and a tappable power bar |
| Change club | Q/E | Previous/next club buttons |
| Shoot | Space | Distinct SWING button |
| Change view | Tab | VIEW button |
| Pause / help | P / H | MENU / HELP buttons |

Support coarse/fine aim and power adjustments, show exact selected power as text, and display nominal club carry. Taps change settings discretely; never require a monitor hold, drag, mouse release, or keyboard modifier. Debounce accidental duplicate activation.

Computer-GUI mouse controls may be added using its separate mouse events, but keyboard and monitor taps remain complete input paths. CC documents `mouse_drag` separately from `monitor_touch`; do not unify them by pretending both have identical semantics. [R4, R12]

### State machine

`TITLE -> HOLE_INTRO -> AIM -> SIMULATE -> SHOT_PLAYBACK -> RESOLVE -> AIM / HOLE_COMPLETE -> SCORECARD`

The game accepts a shot only from AIM. A shot gets a unique local ID and can be applied to scoring only once. Menus and restart actions must not leak into swing input. Starting a hole initializes the tee lie, not the previous hole's ball position.

### Proposed arcade rules

Count one stroke per executed swing. A water or out-of-bounds result adds one penalty stroke and returns the ball to the pre-shot lie. Display this as simplified arcade rules, not a complete implementation of tournament golf rules.

Offer an optional pickup at a configurable stroke cap, initially 12, and record that outcome clearly. Single-hole practice can restart freely; restarting does not masquerade as a completed scored round. Keep practice and full-round best scores separate.

Use one fixed pin per hole for version one. Full-round play supports save/resume. Add local pass-and-play only after the single-player 18-hole game is stable; networking is not required.

## 6. Physics: deterministic, modest, and testable

Implement physics in pure Lua without renderer or peripheral dependencies. Ball state contains position, velocity, motion phase, and current surface. A shot definition contains starting lie, club, aim, power, wind, and any deterministic seed.

Begin with simple ballistic flight under a configurable gravity value. Calibrate each club against a nominal carry on a flat, windless test field. Treat these values as arcade tuning, not verified golf-launch data. Add a constant per-hole wind after the no-wind prototype; no live weather service or complex spin aerodynamics.

Handle terrain contact with swept segment/surface tests or equivalent subdivision, not endpoint-only checks. The ball must not tunnel through the ground or hop across a cup without being checked.

On landing, use the surface normal and a modest restitution rule for bounce. During rolling, apply slope acceleration, surface-specific resistance, and a stable resting rule. Rough should be harder to escape and stop the ball sooner than fairway; sand should strongly dampen motion. These are proposed game-balancing relationships, to be tested and tuned.

Use an explicit motion transition between airborne, rolling, resting, and holed. Once a ball is at rest under the static-friction threshold, it must not jitter forever or spontaneously restart on a nearly flat green.

### Cup behavior

Use a segment-versus-cup test during low-height rolling. A ball can be captured only within a configurable capture radius and below a capture-speed threshold. A fast pass across the cup must not be an automatic hole-in-one. The exaggerated visual ball marker must not enlarge the physical collision radius.

### Wind and water

Detect water entry when the ball actually contacts water or enters a defined unplayable volume, not merely when its horizontal projection passes above it. Hole 8 must allow a sufficiently high/long flight across the gap. Wind changes must not occur halfway through a cached shot unless the shot definition explicitly includes them.

### Simulation versus animation

Use a fixed simulation step, initially 1/60 second, but do not assume the display runs at 60 frames per second. Simulate shots in bounded batches, cache their trajectory, and play the result at the available rendering rate. Skipping animation must not alter the final lie or score.

CC timers are quantized in 0.05-second world-tick increments. The physics step is an internal numerical step, not a promise that a timer fires every 1/60 second. Use a single event dispatcher and yield between bounded batches; do not discard input events by waiting only for a private timer. [R13]

A runaway simulation must produce a logged, recoverable error and return to a safe state. Do not silently award a successful shot or change score after a timeout. Include an explicit maximum simulated duration and finite-number checks.

## 7. Rendering, UI, and performance

Use a behind-ball aiming view, a restrained ball-follow camera during playback, a useful elevated putting view, and a simple top-down hole map. Do not build free-roam camera controls for version one.

Use flat-shaded terrain, a calm ocean, simple rock faces, and a handful of low-poly props. Bake any face shading into the palette choices. There is no requirement for shader effects, imported textures, animated waves, or a physically accurate sky.

Keep the ball readable with an adjustable high-contrast marker, outline/halo, short trail, and ground shadow. Distinguish deliberate ball tracking from physically visible geometry; do not let a visibility marker become an accidental collision-size change.

Keep the persistent HUD short: hole/par, strokes, club, power, distance, lie, and wind. Show surface names as words, not just colors. Provide a larger-text layout, clear focus state, a non-timing mode, and an option to disable camera motion. Reserve enough space for controls before sizing the 3D viewport.

Pine3D provides 3D-to-2D projection for markers and frame sizing for a scene area. Verify actual returned coordinates and visibility behavior in the adapter; do not scatter projection math through gameplay code. [R7]

### Initial budgets, not measured claims

Start with roughly 300-800 visible terrain/prop triangles and one hole loaded at a time. Target about 10-15 displayed frames per second during ball flight on a modest monitor, while keeping controls responsive. These are provisional design targets; actual numbers depend on the chosen screen and server configuration.

Measure geometry transformation/drawing, terminal flush, simulation time, input latency, loaded-data size, and frame-time spikes separately. Redraw static aiming scenes only when input or displayed state changes. Reduce decorative geometry and render resolution before compromising collision or shot determinism.

If the rendering budget fails, reduce the scene, monitor character resolution, draw frequency, or animation complexity. Do not make an unapproved engine switch or quietly add a graphics mod. Do not build the entire 18-hole property as one simultaneous mesh.

## 8. Code boundaries and proposed layout

```text
pine-links/
  golf.lua                    # entry point and safe shutdown
  README.md                   # installation, controls, tested hardware
  PLAN.md
  AGENTS.md                   # scope and verification rules
  lib/
    app.lua                   # state machine and event dispatch
    course.lua                # validated data and terrain queries
    physics.lua               # deterministic shot simulation
    rules.lua                 # strokes, penalties, hole progression
    render.lua                # the only Pine3D adapter
    input.lua                 # event-to-action mapping
    ui.lua                    # HUD, menus, map, touch regions
    storage.lua               # versioned saves and recovery
    audio.lua                 # optional nonblocking cues
  vendor/                     # pinned renderer and actual dependencies
  courses/pebble_beach/
    course_manifest.json
    hole_07.json              # first authored and validated hole
    ...
  tools/
    build_course.py           # validation, compilation, debug preview
  tests/
    run.lua
    physics.lua
    rules.lua
    course.lua
    storage.lua
    fixtures/
  docs/
    REFERENCES.md
    VALIDATION.md
    BENCHMARKS.md
```

Avoid making every file up front as empty scaffolding. Each milestone should add only what it needs and remain runnable. Core physics and rules tests should run without Minecraft or Pine3D. Runtime integration tests must still exercise the actual computer and monitor.

Do not assume the stock development Lua interpreter exactly matches CC behavior. Check syntax and libraries against the tested CC version. Use the host environment for fast pure-Lua tests and the target runtime for final compatibility checks.

## 9. Milestones and acceptance gates

| Milestone | Deliverable | Must pass before expanding |
|---|---|---|
| 0. Platform proof | Renderer/input diagnostic, dependency lock, measurements | Real in-pack output, keyboard and monitor taps, clean exit, no timeouts. |
| 1. Course and physics foundation | Source-reviewed hole 7 geometry, terrain queries, deterministic shot tests | Correct surfaces, no collision/render mismatch, stable rest and cup capture. |
| 2. First playable hole | Tee-to-cup play on 7, wedge/putter, scoring, restart, readable HUD | Complete the hole repeatedly; miss into sand/water and recover; score never doubles. |
| 3. Three-hole build | Add 1 and 18, club bag, sparse tree collision, round state, save/resume | Complete a three-hole practice round without debug intervention. |
| 4. Full-course content | Add 8 as a stress check, then remaining 14; all holes individually reviewed | Full 1-18 round, real layouts rather than renamed templates, pars/distances validate. |
| 5. Cabinet-ready release | Robust installer, optional speaker cues, title/attract mode, local scores | Fresh install, offline play, unplug/resize tests, reboot/resume, measured target performance. |

Stop for a brief playtest at milestone 2. Adjust aim, power, putting, and readability before mass-producing the rest of the course. The first acceptance question is whether someone wants another shot, not whether the menu has a logo.

### Tests that must exist

**Physics:** same shot/seed yields the same result; different playback rates and skipped playback do not change the lie; stronger shots carry farther in the intended tuning range; rough/sand change stopping behavior; uphill/downhill rolls differ; a slow centered putt is captured; a fast crossing putt is not; no ground/cup tunneling; stable rest; no NaNs.

**Terrain:** tee and cup lie on valid surfaces; the cup is inside the green; triangles have valid winding and nonzero area; water does not support the ball; visible and sampled materials agree; sparse obstacle collision matches visible obstacles; hole 8's gap can be flown over but not rolled across.

**Rules and saves:** one stroke per swing; exactly one penalty per hazard outcome; next-shot lie resets correctly; completing a hole advances once; finishing 18 ends the round; save/load preserves hole, ball, score, controls, course revision, and seed; a damaged save does not destroy a valid backup.

**Inputs and runtime:** the game is fully playable keyboard-only and monitor-only; unrelated monitor events are ignored; double touches cannot produce two shots; resize or monitor detachment pauses safely; a missing speaker does not crash; terminal/palette state is restored on exit; performance is checked inside the pack.

### Evidence to retain

For every milestone, retain the exact commands used, test output, one or two screenshots/captures, outstanding issues, and whether tests ran in a host environment, an emulator, or Minecraft. Never label an unrun check as passed.

## 10. Saving, installation, and release

Save only serializable gameplay state, not Pine3D objects. Include a schema version, course/physics version, hole number, ball state, stroke ledger, selected controls, settings, and wind/seed. Stage writes in a temporary file and keep a validated backup. Test recovery rather than claiming filesystem-wide atomic guarantees.

Treat a shot as a transaction: record its pre-shot lie and ID, apply its result once, and save the settled state. Define interruption behavior explicitly so a reboot during playback does not grant a free shot or count it twice. Resuming at the already-computed result is acceptable.

Package assets and dependencies for offline play after installation. The installer must report missing dependencies, unsupported display configurations, failed downloads, or insufficient storage plainly. Do not overwrite an existing startup program without consent. Keep user saves separate from code so upgrades do not erase a round.

Short audio cues are optional: club hit, water, cup, and a restrained completion sound. Missing audio is never fatal. CC's speaker guide describes buffered audio and the event used when a speaker can accept more samples; keep audio out of the main blocking render path. [R14]

Attract mode should replay a known deterministic shot or a stored trajectory. It should not run an unpredictable tournament simulator. Keep personal bests local. Add network leaderboards or multiplayer only as a later, separate project.

## 11. How to hand this to a coding agent

Place this document at `PLAN.md` and use the supplied `AGENT_START.md` as the first task. Start with milestones 0-2 only. The intended checkpoint is one working hole, not a finished eighteen-hole promise.

Only parallelize after the coordinate system and data contract are stable. Physics/rules, renderer/input, and source-based hole authoring can then be separate workstreams with explicit file ownership. Integrate into one runnable program before adding more workstreams.

Require each agent task to end with changed files, executed tests, evidence, remaining blockers, and the next smallest task. Do not accept plausible-looking screenshots as proof of playable golf, or a green test suite as proof of real-course layout accuracy.

**Definition of the first win:** Launch on the CC computer, aim at the seventh green, swing, watch a deterministic shot, putt into the cup, see the correct score, and restart without a shell error.

## References

These are implementation references, not permission to redistribute source photographs or unrelated assets. Accessed 2026-09-27 unless a source is explicitly historical. Proposed design choices and budgets above are not claims from these sources.

- **R1:** Pine3D author's project listing, renderer scope and limits. `https://pinestore.cc/projects/24/pine3d`
- **R2:** Pine3D model creation guide, polygon representation and lack of conventional texture rendering. `https://pine3d.cc/docs/guide/6_creatingModels`
- **R3:** CC:Tweaked terminal API, palette and terminal behavior. `https://tweaked.cc/module/term.html`
- **R4:** CC:Tweaked monitor-touch event, monitor identity and character coordinates. `https://tweaked.cc/event/monitor_touch.html`
- **R5:** CC:Tweaked monitor peripheral, color variants and terminal redirection. `https://tweaked.cc/peripheral/monitor.html`
- **R6:** Pine3D getting-started guide, installation and dependencies. `https://pine3d.cc/docs/guide/1_gettingStarted`
- **R7:** Pine3D ThreeDFrame API, scene operations and projection. `https://pine3d.cc/docs/class/ThreeDFrame`
- **R8:** CC:Tweaked terminal redirection documentation. `https://tweaked.cc/module/term.html#redirect`
- **R9:** Official 2026 Pebble Beach scorecard, inspected visually, page 1. `https://www.pebblebeach.com/content/uploads/PebbleBeach-Scorecard.pdf`
- **R10:** Official Pebble Beach Golf Links course page, descriptions, map links, and photographs. `https://www.pebblebeach.com/golf/pebble-beach-golf-links/`
- **R11:** Official historical photo essay for hole 7. Use for visual context, not as the selected 2026 yardage authority. `https://www.pebblebeach.com/insidepebblebeach/a-history-of-the-7th-hole-at-pebble-beach-in-photos/`
- **R12:** CC:Tweaked mouse-drag event. `https://tweaked.cc/event/mouse_drag.html`
- **R13:** CC:Tweaked OS API, timer rounding and events. `https://tweaked.cc/module/os.html#startTimer`
- **R14:** CC:Tweaked speaker audio guide. `https://tweaked.cc/guide/speaker_audio.html`
