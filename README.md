# cc-binaries

ComputerCraft programs, consolidated from separate repositories via `git subtree` (each subfolder keeps its original commit history).

## ArcadeOS

[`arcadeos/`](./arcadeos) is a Windows 1.0–style shell that runs everything below as apps, with tiled windows, menu bars, an icon strip and Windows 1.0 accessories. To install it on an Advanced Computer:

```
wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/arcadeos/install.lua
```

![ArcadeOS desktop](arcadeos/docs/desktop.png)

See the [ArcadeOS README](./arcadeos/README.md) for usage and for writing apps.

## Testing turtle scripts without Minecraft

[`turtlesim/`](./turtlesim/README.md) runs any turtle script against a simulated turtle and world in CraftOS-PC, with a report of fuel, ores and failed actions:

```
turtlesim/turtle path/to/script.lua
turtlesim/turtle mine --seeds 1-8 --length 64   # cc-factory branch miner across 8 ore layouts
turtlesim/turtle harness                        # all cc-factory harnesses, headless
```

## Programs

| Folder | Source repo |
| --- | --- |
| [`cc-turtleos`](./cc-turtleos) | [Arcadesys/cc-turtleos](https://github.com/Arcadesys/cc-turtleos) |
| [`cc-arcade`](./cc-arcade) | [Arcadesys/cc-arcade](https://github.com/Arcadesys/cc-arcade) |
| [`cc-factory`](./cc-factory) | [Arcadesys/cc-factory](https://github.com/Arcadesys/cc-factory) |
| [`cc-screensaver`](./cc-screensaver) | [Arcadesys/cc-screensaver](https://github.com/Arcadesys/cc-screensaver) |
| [`cc-jukebox`](./cc-jukebox) | [Arcadesys/cc-jukebox](https://github.com/Arcadesys/cc-jukebox) |
| [`computercraft_scripts`](./computercraft_scripts) | [Arcadesys/computercraft_scripts](https://github.com/Arcadesys/computercraft_scripts) |

For turtle branch mining, start with the [safe mining pilot guide](./cc-factory/SAFE_MINING.md). It covers bounded jobs, checked return/unload, restart recovery, installation, and the supervised in-world checks required before scaling.

The [mining fleet guide](./cc-factory/FLEET_MINING.md) adds automatic assignment of pre-approved jobs, durable area reservations, and shared-world turtle-tester scenarios. A lost turtle's area remains quarantined until manually reconciled.

## Pine3D Derby and diamond house

The [derby prototype](./cc-arcade/derby/README.md) adds a shared 3D horse race, separate betting stations, and a central diamond-backed arcade wallet. It includes the [venue concept](./cc-arcade/derby/docs/diamond-house-concept.png); live Minecraft acceptance remains pending.

## Pine games

The standalone Pine3D games are in [`computercraft_scripts`](./computercraft_scripts). Copy an entire game folder to a CC:Tweaked computer so its bundled libraries stay beside the launcher.

| Game | Launcher after copying its folder | Details |
| --- | --- | --- |
| [Pine Ball](./computercraft_scripts/pine-ball/README.md) | `/pine-ball/ball.lua` | Furball baseball vs CPU or a 2-player duel |
| [Pine Links](./computercraft_scripts/pine-links/README.md) | `/pine-links/golf.lua` | Furball's Marovitz-inspired Hole 3, par 3 |
| [Pine Lanes](./computercraft_scripts/pine-lanes/README.md) | `/pine-lanes/bowl.lua` | Furball ten-frame bowling for 1–4 players |
| [Pine Dungeon](./computercraft_scripts/pine-dungeon/README.md) | `/pine-dungeon/dungeon.lua` | First-person crawler with an ASCII map |

Pine Ball, Pine Links and Pine Lanes run Lua ports of the [furball-simulator](https://github.com/Arcadesys/furball-simulator) sport engines, checked against fixtures generated from the TypeScript. After tuning furball, run `computercraft_scripts/tools/furball-fixtures/update.sh` and then each game's `tools/test_craftos.sh`.

Note: [Arcadesys/computercraft](https://github.com/Arcadesys/computercraft) was skipped — it's an empty repository on GitHub (no commits).
