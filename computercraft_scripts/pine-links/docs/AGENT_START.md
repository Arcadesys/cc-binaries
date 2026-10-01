> **Historical.** This describes the original Pebble Beach hole 7 prototype. Pine Links now runs furball-simulator's Marovitz-inspired Hole 3 and golf kernel; see `README.md`.

# First implementation task: Pine Links

Read `PINE_LINKS_IMPLEMENTATION_PLAN.md` (or `PLAN.md` if renamed) and `course_manifest.json`.

Build an original CC:Tweaked / Pine3D golf game, starting with a source-based recreation of Pebble Beach hole 7. Complete milestones 0-2 before expanding scope. This is a Lua program inside Minecraft, not a browser game, Minecraft mod, or physical golf course.

## Required first actions

1. Inspect the workspace before modifying it. Establish the runnable entry point, a tiny pure-Lua test runner, and a short progress log. Do not erase or overwrite unrelated files.
2. Inspect the Pine3D documentation and actual source, choose an exact revision, and include its real dependencies. Prove colored geometry, camera orientation, input mapping, and screen output on a terminal and an Advanced Monitor. Record tests that still need access to Minecraft as pending.
3. Inspect real hole-7 reference imagery and the official scorecard. The supplied manifest is verified numerical metadata, not a terrain mesh. Author approximate but recognizable geometry, mark inferred elevations/pin position, and produce a top-down validation preview.
4. Implement fixed-step pure-Lua ball physics, terrain sampling, wedge/putter control, cup capture, the shot state machine, and scoring. Use the same canonical terrain boundaries for collision and rendering.
5. Deliver the first playable hole, installation instructions, controls, executed tests, and evidence. Do not expand to the other 17 holes before the hole-7 playtest checkpoint.

## Non-negotiable constraints

- Keep Pine3D as the renderer; no unapproved engine replacement or extra graphics mod.
- Support keyboard-only and Advanced Monitor tap-only play. No monitor drag/hold requirement.
- Use explicit aim/power controls with no mandatory timing minigame.
- A low render rate or skipped playback must not change a shot result.
- Flying over water is legal; touching water triggers the simplified penalty rule.
- Count each shot and penalty once. A missed putt or bunker recovery must remain playable.
- Preserve original user startup programs and unrelated code.
- No copied commercial-game assets or ROM data.
- No procedural random holes labeled as Pebble Beach.
- No claims of benchmarked speed, exact real-world geometry, or passed in-world tests without evidence.

## First playable acceptance script

Launch the game. Read the controls. Aim and adjust power. Hit a wedge shot. Watch its flight and landing. Play from sand if it misses. Trigger a water penalty and verify the restored lie and stroke total. Reach the green, use the putter, sink a slow putt, and read the hole score. Restart. Repeat using only monitor buttons.

Run the deterministic physics/rules tests and report actual output. Where the target pack is inaccessible, provide the exact pending in-world checks instead of marking them passed.

## Report format

Briefly report: current milestone; changed files; run/install command; tests actually executed; screenshots or captures actually obtained; remaining blocker; and next smallest task.
