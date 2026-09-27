# Pine Dungeon

A small, standalone first-person dungeon crawler for CC:Tweaked. The left pane is a real Pine3D corridor view. The right pane is the complete ASCII map of the current floor, with north at the top. Reach the `>` stairs on floor 3 to escape. There are three authored floors, deterministic turn-based monsters, gold, potions, death, and restart.

Copy the entire `pine-dungeon` folder to an Advanced Computer and run `/pine-dungeon/dungeon.lua`. Use `--terminal` for the computer terminal, or `--monitor left` for a named Advanced Monitor. Without either option, the first attached color monitor is selected. Nothing downloads at runtime. The bundled Pine3D revision and license are in `vendor/`.

The minimum supported display is 39×19 characters; 51×19 or larger is more comfortable. Controls have two-row tap targets at the minimum size. Smaller displays show a resize message and a quit control.

## Controls

| Action | Keyboard | Monitor tap |
|---|---|---|
| Move and face north, west, east, south | Arrows or WASD | NORTH, WEST, EAST, SOUTH |
| Strike the tile ahead | Space | ATTACK |
| Drink a potion, healing up to 5 HP | H | POTION |
| Show the enlarged ASCII map and legend | Tab | MAP |
| Wait one turn | Period or Enter | WAIT |
| Open or close Help | F1 | HELP |
| Open or close menu | P | MENU |
| Restart from menu or an ending | R | NEW GAME |
| Quit | Q | QUIT |

Moving into a monster strikes it instead of entering its tile. A goblin (`g`) takes one hit; a shade (`s`) takes two. Nearby monsters approach after your turn and attack when adjacent. A potion (`P`) and gold (`$`) are picked up automatically. A wall (`#`) blocks movement without spending a turn. Walking onto `>` descends to the next floor or wins on floor 3. The map marks your position with `@`; it carries all essential location information without relying on color.

The game is deliberately short and replayable. It has no random generation, saved progress, networking, names, sound, or equipment system.

## Development

`lib/world.lua` owns the dungeon, combat, movement, and progression with no terminal, renderer, or clock dependency. `lib/render.lua` builds the Pine3D first-person view and restores the terminal palette. `lib/ui.lua` supplies the ASCII map and large tap targets; `lib/input.lua` translates keys and touch coordinates.

Run `tools/test_craftos.sh RESULT_DIRECTORY` for the pure game, input, and display checks. Run `tools/test_runtime.sh RESULT_DIRECTORY` for complete keyboard and monitor campaigns through the real event loop, including monitor resize and detachment. Both scripts use isolated CraftOS-PC data directories. These emulator checks do not establish Minecraft/ATM10 compatibility.
