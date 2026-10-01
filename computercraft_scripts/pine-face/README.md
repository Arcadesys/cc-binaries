# Pine Face

A Faceball 2000–style first-person tag game for CC:Tweaked, drawn in Pine3D. Four Smileys roam one maze. Three hits tag a Smiley, the shooter scores a point, and the tagged Smiley respawns two seconds later at the spawn point farthest from everyone else, with a brief white-flashing shield. The first to 10 tags wins.

Each player uses their own Advanced Computer (or a computer with a color monitor), connected by any modem, wired or wireless. Bots play any seat without a person, so a match always has four Smileys, and one computer with no modem plays you against three bots.

## Playing

Copy the whole `pine-face` folder to each computer, then:

| Computer | Command |
|---|---|
| Host (seat 1, runs the game) | `/pine-face/face.lua` or `/pine-face/face.lua --host` |
| Each other player | `/pine-face/face.lua --join`, or `--join <host computer ID>` to skip the lookup |
| Alone against bots | `/pine-face/face.lua --solo` |

Players join in the lobby and fill seats 2–4. The host presses ENTER (or START) when everyone is in; any empty seat gets a bot. A player who joins after the match starts takes over a bot's seat. If a player's computer goes quiet for three seconds, a bot takes over their seat, and running `--join` again gets them the same seat back. If the host goes away, players see "Lost the host" and can press R to rejoin.

`--terminal` uses the computer's own screen; `--monitor NAME` picks a monitor. Without either, the first color monitor attached is used. The minimum display is 39×19 characters; at 46 columns or more a radar appears beside the view.

## Controls

| Action | Keys | Buttons (click or monitor tap) |
|---|---|---|
| Move forward or back | Up/Down or W/S (hold) | ↑ GO, ↓ BACK |
| Turn | Left/Right or A/D (hold) | ← TURN, TURN → |
| Fire (one shot in the air at a time) | Space or Left Ctrl | FIRE |
| Start or restart the match (host) | Enter | START, NEW MATCH |
| Scores during play | Tab | |
| Help | F1 or H | HELP |
| Menu (the match keeps running) | P | MENU |
| Rejoin after losing the host | R | RETRY |
| Quit | Q | QUIT |

Each tap on a button holds that control briefly; for continuous movement, hold the keys.

## How it works

`lib/world.lua` is the whole game: the arena, movement with wall sliding, bullets, hits, tags, respawns and the win. It runs at a fixed ten ticks per second and has no clock, terminal or network dependency, so a match from a given seed always plays the same way. `lib/bot.lua` routes bots through the maze by breadth-first search, turns them toward any rival in plain sight, and fires once they are lined up.

`lib/net.lua` speaks rednet protocol `pine-face-v1`. The host advertises itself with `rednet.host`, owns the only copy of the world, steps it, and sends every player a compact snapshot each tick. Players send only which keys they're holding. `lib/render.lua` builds the walls, floor, Smileys and bullets as Pine3D objects once, and each frame draws only those near you and in front of you. `lib/ui.lua` draws the scoreboard, hearts, radar, lobby and results.

## Tests

Run `tools/test_craftos.sh RESULT_DIRECTORY` (CraftOS-PC, headless). The tests cover:
- an arena where every tile can be reached
- wall sliding
- bullets that stop at walls
- the hit, tag and respawn timings
- spawn shields
- the tenth tag ending the match
- snapshot round trips
- a deterministic four-bot match played to a winner
- host and clients over a fake rednet: joining, a full lobby, dropouts, rejoining
- input
- layouts at three sizes
- rendering every phase, plus the real event loop

The tests also leave screen dumps (`*.json`) in the result directory, which `arcadeos/tools/render.py` turns into PNGs.

These are emulator checks. Networked play has not yet been tried between real Minecraft computers.
