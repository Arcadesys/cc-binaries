# Approved Pine Lanes build

## Outcome

A complete 1–4 player, ten-frame arcade bowling game for CC:Tweaked using real Pine3D. One shared lane, frame-by-frame player turns, position/aim/power and left/right hook. Preserve Pine Links and the existing desktop/MIDI programs. Start from repository commit `0aefec5`; commit locally without remote publishing.

## Milestones

1. **M0: display and contact proof.** Render a recognizable lane, gutters, ball and ten pins. Verify keyboard/tap input and camera/axis orientation; review real emulator screenshots before accepting integration.
2. **M1: complete frame.** First delivery, physical contacts and tipping, settling, deadwood removal, and a second delivery against surviving pins. Establish repeatable strike, spare, partial-hit, hook-left/right and gutter fixtures without scripted pin counts.
3. **M2: complete match.** Ten-frame scoring, tenth-frame bonuses/rack resets, 1–4 players, final rankings, restart, pause/resume, display recovery and clean exit.

## Assignments

Three Luna workers at medium effort implement physics, rules, and presentation independently against CONTRACT.md. The coordinator reviews integration, owns the controller/launcher and runtime tests, validates the visible CraftOS-PC application, records evidence, and packages the build. Workers do not edit each other's modules or extract a shared framework.

## Acceptance

- Known scores: gutters 0, 9/miss 90, 5/spares 150, perfect game 300, mixed reference game and unresolved bonuses.
- Tenth-frame open, spare, consecutive strikes, and strike/non-strike bonus rack handling; multiplayer ownership and shared placings.
- Deterministic contacts, no maximum-speed tunneling, mirrored hook, stable settling, finite state, valid pin partitions, retained surviving poses, and error cancellation without scoring.
- Complete games through real keyboard and monitor event dispatch. Native manual solo game and two-player handoff.
- Readable 39×19 and 51×19 layouts, at least two-row tap targets, numbered pin diagram, text status independent of color.
- Resizing, monitor detachment, small-screen fallback, normal/error palette and terminal restoration, duplicate input, paused simulation and playback-skip equivalence.
- Existing Pine Links core tests still pass.

## Defaults and boundaries

Player 1–4 labels, untimed controls, settings retained per player, and explicit CONTINUE after each roll. Fixed 1/120-second simulation, 30 Hz cached snapshots, 10 Hz display target. Arcade capsule/impulse approximation, not a full 3D rigid-body engine. No network play, saves, sound, custom names, oil selection or loft/foul controls. Emulator success is reported separately from actual Minecraft/ATM10 validation.
