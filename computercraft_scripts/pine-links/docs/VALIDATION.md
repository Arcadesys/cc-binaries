# Validation — 27 September 2026

This is an emulator-validated milestones 0–2 implementation, not a completed in-world compatibility gate. Only hole 7 is playable.

## Environment and provenance

- macOS, installed `/Applications/CraftOS-PC.app`, CraftOS-PC 2.8.3; CraftOS 1.9, Lua 5.2.
- Real Pine3D revision `2fbbd2cebe9b1ce8a8fc173a2a8a7694878a62a4`, with its `betterblittle.lua` dependency and MIT license bundled. No runtime downloads.
- Repository: `Arcadesys/computercraft_scripts`, local branch `pine-links-m0-m2`. Existing startup and MIDI programs were inspected and preserved. Their monitor/event conventions were useful context; their OS/event loops are not coupled to this game.
- Three requested Luna workers implemented physics/rules, course/sampler, and renderer/input. The coordinator integrated the state machine, runtime, and validation.
- Original implementation handoff is preserved in `PLAN.md` and `docs/AGENT_START.md`. Course assumptions and official references are in `REFERENCES.md`.

## Executed checks

`tools/test_craftos.sh RESULT_DIRECTORY` runs seven test modules in the installed emulator: physics, rules, course, input, real tee-to-cup sequence, real bunker recovery, and app state. All pass. These cover deterministic batches, power/aim response, surface drag, uphill/downhill rolling, swept collision, cup speed, water flyover/contact, invalid shots, scoring idempotence, penalties, no strokes after completion, playback/skip equivalence, pause/help/restart, and input filtering/debounce.

`tools/test_runtime.sh RESULT_DIRECTORY` runs the real application dispatcher and Pine3D renderer in GUI CraftOS-PC. Both keyboard events and `monitor_touch` events on a real emulated color monitor pass:

- Wedge power 73%, cup-aimed putter power 61%: **2 strokes, Birdie**, zero penalties.
- Wedge power 73%, aim +12 degrees: water, total 2 strokes including one penalty, exact pre-shot lie restored.
- Wedge power 70%, aim −3 degrees: bunker; cup-aimed wedge power 21%: recovery outside the bunker and within six yards of the cup.
- Help, view switching, restart, pause, and quit.
- Actual emulated monitor text-scale change and peripheral removal: safe pause, state retained, resume on the computer after detachment.
- Terminal redirection and palette restoration. Diagnostic runs additionally check the monitor palette, input echo, moving ball, and clean exit.

The automated monitor driver queues the same discrete events Minecraft delivers and selects coordinates from the visible button layout. It does not mutate ball positions or scores. This establishes the monitor event path, not a physical Minecraft monitor tap.

A separate native keyboard playthrough in the visible CraftOS-PC app completed the same two-shot Birdie with full animations at 125×52 characters. The event log records the wedge resting at `(110.6293, -0.00214, -0.71320)` and the putt reaching `(107, 0, 0)`.

## Presentation and accessibility

The first rendered attempt failed visual review: terrain appeared as a horizon stripe and repeated control labels consumed the screen. The revised renderer uses a downward tee camera, a fixed three-quarter overview, overhead map, distinct shaded materials, visible ball/cup markers, and one centered label per button. The scorecard has a high-contrast result panel.

Controls have explicit text labels, a dedicated swing target, and keyboard equivalents. Power selection is untimed. Fine mode is labeled in text; lie, distance, strokes, and penalties do not depend on color. At least 39×19 characters are required; 51×19 provides a nine-row 3D viewport and two-row tap targets. Larger screens retain a separate control area. Small displays show a resize prompt and retain a quit control. Fullscreen 125×52 and standard 51×19 views were inspected in the emulator. The screen reader does not expose CraftOS terminal cells as individual controls; no screen-reader compatibility claim is made.

## Remaining target-pack gate

The original M0 gate explicitly requires a capture inside the target Minecraft pack. This remains pending. Record ATM10, Minecraft, and CC:Tweaked versions; computer type; monitor block dimensions, character size and text scale; and server limits. Then run `diagnostic.lua`, tap and use keyboard controls, play the hole, and measure frame timing. Emulator timing is not server performance evidence.

Geometry is a source-informed approximation, not surveyed terrain. Wind remains calm for this milestone. There are no other playable holes, persistent round saves, or full-course progression. The manifest preserves the supplied 18-hole scorecard metadata only.
