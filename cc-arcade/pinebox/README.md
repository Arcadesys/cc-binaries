# Pine Shut the Box

A Pine3D take on the grand prize round of the old DOS game-show *High Rollers*. Nine big number tiles stand behind a felt dice tray. Roll two dice, knock down tiles that add up to the roll, and clear the board for the grand prize. If no remaining tiles can make a roll, the round is over.

Run `pinebox` on an Advanced Computer or Advanced Monitor (39×19 minimum, 100×40 or larger recommended). `--terminal` or `--monitor NAME` picks the display.

## The dice

The dice are thrown, not faked. Each roll runs a small rigid-body simulation: gravity, eight corner contacts against the felt and the rails, bounce, friction and die-to-die knocks. The recorded tumble plays back while a chase camera follows the dice. When they settle, the camera snap-zooms onto them, holds the result, then eases back to the board. Every impact clicks through a speaker, louder for harder hits.

The values are drawn first (uniform 1–6 each). When physics leaves a face on top, the die's pips are turned with a rotation of the cube so that face shows the drawn value. The motion is real physics, the odds are exactly fair, and the die always lands flat on the right number.

## Rules and odds

- Tiles 1–9. Always two dice, even late in the round.
- Take any set of standing tiles that adds up to the roll, e.g. a 7 can be 7, 1+6, 2+5, 3+4 or 1+2+4.
- A roll that no standing tiles can make ends the round. The stake is lost.
- Clear all nine and you win 13× the stake.

The game solves the board exactly. Each pick starts on the best play, marked **(BEST)**, and the info line shows your chance to clear from the current board. With perfect play the board clears 7.14% of the time, so the 13× grand prize returns about 93%.

## Controls

The arcade's three cabinet buttons (LEFT, CENTER, RIGHT from `.button_config`):

| When | LEFT | CENTER | RIGHT |
|---|---|---|---|
| Between rounds | BET (1 → 2 → 5 → 10) | PLAY | CASH OUT (eject card) |
| Before a roll | | ROLL | |
| After a roll | < OTHER way to make it | TAKE | OTHER > |

Keyboard: 1/2/3 or ←/↑/→, Space/Enter for CENTER, plus R (roll), T (take), B (bet) and C (cash out). Touch the bottom bar on a monitor. Q leaves between rounds.

## Money

On a house station, PLAY reserves the stake plus the grand prize with the house, using the same accounts as Pine Slots, Pine Jack and the Derby. The round settles once: the prize on a clear, nothing on a dead roll. If the host misses the settlement, the table holds on RETRY until the payout is confirmed. Without a house configuration, or with `--demo`, it uses a 100-credit practice meter.

## Development

`python3 derby/tools/run.py pinebox.tests.run` checks the solver against the known 7.14% and plays a forced grand prize, a dead roll and an OTHER pick through the real event loop. `pinebox.tests.physics` throws 200 dice pairs and checks every one settles flat inside the tray showing the drawn value. `pinebox.tests.rendered` dumps the throw frame by frame for `casino/tools/screens.py`.
