# Pine Lanes validation

Build base: `computercraft_scripts` commit `0aefec5`; Pine Lanes is a standalone folder. The existing Pine Links core suite passed unchanged. Local commit and ZIP identity are recorded in the companion validation report shipped with the release bundle.

## Automated checks

- Five CraftOS core groups passed: physics, rules, input, display, and controller. The rules fixtures cover 0, 90, 150, 300, the mixed reference score, unresolved strike/spare bonuses, tenth-frame rack cases, shared placings, duplicate/error rejection, and one- through four-player progression.
- Physics fixtures verify a real ten-pin strike, a six-plus-four spare using returned standing poses, mirrored left/right hook, zero-hook straight travel, gutter lockout, max-power contact chains, down-pin capsule contacts, finite values, initial/surviving-pose preservation, and identical trajectories across step budgets 1, 17, and 120. A short timeout produces a cancellable error result.
- The GUI integration runner sends actual keyboard and `monitor_touch` events through the application dispatcher. It completes a one-player match (20 deliveries, score 80), a two-player monitor match (40 deliveries, scores 70 and 90), and a one-player perfect match (12 deliveries, score 300). These runs do not mutate score or rack state directly.
- A separate GUI recovery scenario shrinks the monitor below 39×19 during playback, verifies the resize/quit message, restores its size, detaches it, resumes on the computer terminal, and confirms the same delivery resolves once. An injected observer failure verifies terminal redirect and palette restoration on error exit.
- The seven-module Pine Links core regression passed. Pine Links and the existing desktop/MIDI programs were not edited.

## Native CraftOS-PC review

Tested in the installed macOS CraftOS-PC 2.8.3 application, Computer 8. The full solo game was played with keyboard input and all twelve strike deliveries completed for 300, including the tenth-frame bonus rolls. The second visible playtest knocked six pins, cleared the same rack's four survivors for a spare, passed control to Player 2, played right- and left-hook deliveries, and returned control to Player 1 with their prior settings. The close deck and scorecard cameras, labeled X/Y/Z diagnostic rods, Help from the scorecard, and normal exit were inspected.

Actual 39×19 and 51×19 display captures were reviewed for readable controls, named pins, score information, and visible ball/rack. The 39×19 native capture used an exact-size CraftOS window. The numbered diagram identifies each pin's state with digits and `!`, independently of color. Buttons on supported screens occupy at least two rows. Pine3D terminal-buffer PNGs at both sizes accompany native captures in the evidence folder; they were generated from rendered terminal lines, not from an artist's mockup.

The application runs its event loop at a 0.1-second display target and caches playback at 30 Hz. In the native solo playthrough, displayed playback frames had a 104 ms median interval (about 9.6 frames per second). The automated integration reports include per-frame render times and wall durations in `runtime.json`; these are emulator measurements, not Minecraft performance.

## Remaining compatibility boundary

CraftOS-PC validation does not establish operation inside Minecraft, ATM10, or a particular Advanced Monitor build. No Minecraft/ATM10 instance was available for an in-world acceptance run. The terminal is not exposed to macOS accessibility as individual text cells, so this validation establishes visible large-label and keyboard/tap behavior, not screen-reader compatibility.
