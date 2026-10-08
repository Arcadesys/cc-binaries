# Daily Wordle

Guess the day's five-letter Minecraft word in six tries. Every computer on the server gets the same word on the same day, so players can compare boards. The day turns over at midnight UTC.

After each guess the tiles turn over one at a time: green for the right letter in the right place, gold for a letter that is in the word somewhere else, dark grey for a letter that isn't in it. A letter guessed twice is only marked as often as the word holds it. The on-screen keyboard keeps the best colour each letter has earned.

The screen is drawn in teletext subpixels. Bevelled letter blocks sit on a stone backdrop under a blocky WORDLE title. Tiles flip over one at a time, a refused guess shakes red, and a solved row hops in turn while confetti falls. Screens under 31 rows get flat tiles with text letters, and under 33 rows the title is one line of text. In the Pine Arcade carousel, Daily Wordle stands on its pedestal as a wooden board of grey, gold and green blocks.

Run `wordle` on an Advanced Computer or Advanced Monitor (39×19 minimum; bigger screens get bigger tiles). `--terminal` or `--monitor NAME` picks the display. It is also in the Pine Arcade menu (`get all`), or install it on its own:

```
wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-arcade/get.lua wordle --startup
```

## Controls

- **Keyboard:** type letters, Enter to guess, Backspace to erase.
- **Touch or click:** the on-screen keys.
- **Cabinet buttons:** LEFT and RIGHT move the lit key along the on-screen keyboard, CENTER presses it.

Guesses must be words: Webster's Second (five-letter words and plurals of four-letter ones) plus a few modern and Minecraft words. When the round ends, the message line says when the next word arrives. NEXT PLAYER clears the board for whoever is next at the cabinet, and QUIT leaves. Nothing is saved between players.

## The words

The 90 answers live in [`words.lua`](words.lua), one per date from 2026-10-08 to 2027-01-05. Past the last date the list starts again from the top, and the puzzle number keeps counting. Halloween is WITCH, Christmas is CHEST and New Year's Day is SPAWN. To add or change days, edit `words.lua` with consecutive dates, run `python3 cc-arcade/wordle/tools/guesses.py` (every answer must also be a valid guess), then `python3 cc-arcade/tools/manifest.py`.

The answers are plain text on every cabinet, so a player who reads the file can see them.

| Date | Word |
| --- | --- |
| 2026-10-08 | STONE |
| 2026-10-09 | BLAZE |
| 2026-10-10 | GHAST |
| 2026-10-11 | SLIME |
| 2026-10-12 | TORCH |
| 2026-10-13 | SPORE |
| 2026-10-14 | ANVIL |
| 2026-10-15 | BRICK |
| 2026-10-16 | SWORD |
| 2026-10-17 | ARROW |
| 2026-10-18 | WHEAT |
| 2026-10-19 | BREAD |
| 2026-10-20 | SHEEP |
| 2026-10-21 | LLAMA |
| 2026-10-22 | PANDA |
| 2026-10-23 | SQUID |
| 2026-10-24 | BIRCH |
| 2026-10-25 | CLOCK |
| 2026-10-26 | FLINT |
| 2026-10-27 | LAPIS |
| 2026-10-28 | GLASS |
| 2026-10-29 | BLOCK |
| 2026-10-30 | CRAFT |
| 2026-10-31 | WITCH |
| 2026-11-01 | STRAY |
| 2026-11-02 | ELDER |
| 2026-11-03 | OCEAN |
| 2026-11-04 | TAIGA |
| 2026-11-05 | SWAMP |
| 2026-11-06 | BIOME |
| 2026-11-07 | MAGMA |
| 2026-11-08 | ENDER |
| 2026-11-09 | PEARL |
| 2026-11-10 | SHELL |
| 2026-11-11 | GOLEM |
| 2026-11-12 | ALLAY |
| 2026-11-13 | LEVER |
| 2026-11-14 | FENCE |
| 2026-11-15 | GRASS |
| 2026-11-16 | PLANK |
| 2026-11-17 | SKULL |
| 2026-11-18 | HORSE |
| 2026-11-19 | CAMEL |
| 2026-11-20 | COCOA |
| 2026-11-21 | MELON |
| 2026-11-22 | BERRY |
| 2026-11-23 | APPLE |
| 2026-11-24 | SUGAR |
| 2026-11-25 | PAPER |
| 2026-11-26 | SHELF |
| 2026-11-27 | STAIR |
| 2026-11-28 | CORAL |
| 2026-11-29 | SHARD |
| 2026-11-30 | GEODE |
| 2026-12-01 | SCULK |
| 2026-12-02 | VAULT |
| 2026-12-03 | TRIAL |
| 2026-12-04 | ARMOR |
| 2026-12-05 | BOOTS |
| 2026-12-06 | TOTEM |
| 2026-12-07 | FANGS |
| 2026-12-08 | TRADE |
| 2026-12-09 | SCUTE |
| 2026-12-10 | WATER |
| 2026-12-11 | BRUTE |
| 2026-12-12 | INGOT |
| 2026-12-13 | CHAIN |
| 2026-12-14 | WORLD |
| 2026-12-15 | BUILD |
| 2026-12-16 | GROVE |
| 2026-12-17 | PEAKS |
| 2026-12-18 | BEACH |
| 2026-12-19 | RIVER |
| 2026-12-20 | LIGHT |
| 2026-12-21 | SMELT |
| 2026-12-22 | FLAME |
| 2026-12-23 | SMITE |
| 2026-12-24 | LEVEL |
| 2026-12-25 | CHEST |
| 2026-12-26 | STEVE |
| 2026-12-27 | NOTCH |
| 2026-12-28 | HONEY |
| 2026-12-29 | TULIP |
| 2026-12-30 | POPPY |
| 2026-12-31 | DAISY |
| 2027-01-01 | SPAWN |
| 2027-01-02 | LILAC |
| 2027-01-03 | SEEDS |
| 2027-01-04 | CROPS |
| 2027-01-05 | STEAK |

## Tests

`python3 cc-arcade/derby/tools/run.py wordle.tests.run` checks the word list and dates, scoring with repeated letters, the layout at every screen size, and a full game through the event loop.
