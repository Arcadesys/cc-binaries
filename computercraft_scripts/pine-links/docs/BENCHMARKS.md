# Emulator drawing measurements

Measured during the keyboard/monitor acceptance scenarios on 27 September 2026. Times cover one Pine3D frame plus HUD drawing, not full simulation or end-to-end displayed FPS. Animation is scheduled every 0.1 seconds (10 Hz target).

| Display path | Frames | Median draw | Maximum draw |
|---|---:|---:|---:|
| keyboard | 181 | 1 ms | 3 ms |
| monitor | 184 | 2 ms | 6 ms |

Standard test terminal and emulated monitor begin at 51×19 characters; the monitor scenario also changes text scale. Native 125×52 playthrough frames were around 8–11 ms near the captured flight. These are local emulator observations, not ATM10/server benchmarks. Raw reports are emitted by the test runners.
