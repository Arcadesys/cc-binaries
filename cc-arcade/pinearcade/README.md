# Pine Arcade

A Pine3D menu for a computer with several Pine games installed. Each game stands on a pedestal in a turning carousel; the pedestal of the game the computer boots into is ringed in green.

```
wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-arcade/get.lua all --startup
```

| Button | Carousel | Game chosen | STARTUP tile chosen |
| --- | --- | --- | --- |
| LEFT | previous | back | back |
| CENTER | choose | play | boot into this menu |
| RIGHT | next | start at boot (or, if it already does, menu at boot) | nothing at boot |

The buttons are the cabinet's three (taught with `config`), the arrow keys and Enter, 1 / 2 / 3, or a click or touch on the bottom bar. Clicking the left or right of the carousel turns it. Backspace closes a chosen game; Ctrl+T leaves the menu. When a game ends, the menu comes back.

Boot changes run `get boot`, which rewrites `/startup.lua` and the install's `.get.json`, so `get update` keeps the choice. The menu lists what `get` installed beside it, so a computer set up before Pine Arcade existed needs `get all` (or `get update` after adding `pinearcade` to the install).

`pinearcade --monitor NAME` or `--terminal` picks the screen, and games that take the same option open there too. Needs an advanced computer or monitor at least 26 x 16.

Tests: `python3 cc-arcade/derby/tools/run.py pinearcade.tests.run` installs `all` from this checkout, loads each game, drives the menu through a boot change and a play, and dumps screens for `casino/tools/screens.py`.
