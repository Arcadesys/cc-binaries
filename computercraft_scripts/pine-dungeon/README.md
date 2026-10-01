# Pine Dungeon

A small, standalone first-person dungeon crawler for CC:Tweaked. The left pane is a real Pine3D corridor view. The right pane is the complete ASCII map of the current floor, with north at the top. Slay the Warden on floor 3, then enter the End Portal (`O`) to win. There are three authored floors, deterministic turn-based mobs (zombies, skeletons, a Warden boss), emeralds, steak, death, and restart.

Copy the entire `pine-dungeon` folder to an Advanced Computer and run `/pine-dungeon/dungeon.lua`. Use `--terminal` for the computer terminal, or `--monitor left` for a named Advanced Monitor. Without either option, the first attached color monitor is selected. Nothing downloads at runtime. The bundled Pine3D revision and license are in `vendor/`.

The minimum supported display is 39×19 characters; 51×19 or larger is more comfortable. Controls have two-row tap targets at the minimum size. Smaller displays show a resize message and a quit control.

## Controls

| Action | Keyboard | Monitor tap |
|---|---|---|
| Step forward or backward without turning | Up/Down or W/S | FORWARD, BACKWARD |
| Turn 90 degrees in place | Left/Right or A/D | TURN LEFT, TURN RIGHT |
| Strike the tile ahead | Space | ATTACK |
| Eat a steak, healing up to 5 hearts | E or H | EAT |
| Show the enlarged ASCII map and legend | Tab | MAP |
| Wait one turn | Period or Enter | WAIT |
| Open or close Help | F1 | HELP |
| Open or close menu | P | MENU |
| Restart from menu or an ending | R | NEW GAME |
| Quit | Q | QUIT |

Moving into a monster strikes it instead of entering its tile. A zombie (`z`) takes one hit; a skeleton (`k`) takes two. Turning takes a turn, so nearby monsters can move or attack; backward steps keep your current facing. Steak (`%`) and emeralds (`$`) are picked up automatically. A wall (`#`) blocks movement without spending a turn. Walking onto the ladder `>` descends; floor 3 starts with a campfire that restores your hearts.

## The Warden

The floor-3 boss (`W`, 14 HP) slams for 2 when adjacent. When you share an open row or column with it, its chest glows red and it charges a sonic boom for two turns, then hits for 4 unless you broke line of sight (use the pillars). It rests after each attack. At half health it roars and raises two zombies. The End Portal stays sealed until it falls. The map marks your position with `@` and names your facing direction above it; it carries all essential location information without relying on color.

The game is deliberately short and replayable. It has no random generation, saved progress, networking, names, sound, or equipment system.

## Development

`lib/world.lua` owns the dungeon, combat, movement, and progression with no terminal, renderer, or clock dependency. `lib/render.lua` builds the Pine3D first-person view and restores the terminal palette. `lib/ui.lua` supplies the ASCII map and large tap targets; `lib/input.lua` translates keys and touch coordinates.

Run `tools/test_craftos.sh RESULT_DIRECTORY` for the pure game, input, and display checks. Run `tools/test_runtime.sh RESULT_DIRECTORY` for complete keyboard and monitor campaigns through the real event loop, including monitor resize and detachment. Both scripts use isolated CraftOS-PC data directories. These emulator checks do not establish Minecraft/ATM10 compatibility.
