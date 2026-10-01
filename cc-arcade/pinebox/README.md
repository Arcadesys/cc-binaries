# Pine Shut the Box

A Pine3D take on the grand prize round of the old DOS game-show *High Rollers*. Nine big number tiles stand behind a felt dice tray. Roll two dice, knock down tiles that add up to the roll, and clear the board for the grand prize. If no remaining tiles can make a roll, the turn is over. Built for 2–4 players taking turns at one cabinet; solo play is still there.

Under the 3D view, a strip of nine chips repeats the board so the numbers read from across the room: white for standing, gold for the tiles you're about to take, dark for shut. On taller screens the chips draw big block digits (2 rows tall from 24 rows, 4 rows tall from 34).

Run `pinebox` on an Advanced Computer or Advanced Monitor (39×19 minimum, 100×40 or larger recommended). `--terminal` or `--monitor NAME` picks the display.

## The dice

The dice are thrown, not faked. Each roll runs a small rigid-body simulation: gravity, eight corner contacts against the felt and the rails, bounce, friction and die-to-die knocks. The recorded tumble plays back while a chase camera follows the dice. When they settle, the camera snap-zooms onto them, holds the result, then eases back to the board. Every impact clicks through a speaker, louder for harder hits.

The values are drawn first (uniform 1–6 each). When physics leaves a face on top, the die's pips are turned with a rotation of the cube so that face shows the drawn value. The motion is real physics, the odds are exactly fair, and the die always lands flat on the right number.

## Matches

PLAY opens the seat screen: < FEWER and MORE > set 1–4 players (two by default), and START begins.

A 2–4 player match is played for a pot. Each player in turn inserts their house card and presses ANTE (the bet). Then they pass the slot to the next player. CANCEL before everyone has anted returns every ante. Each player then takes one turn on a fresh board. When a roll can't be made, the tiles still standing are that player's score; shutting the box scores 0. When everyone has played, the lowest score takes the whole pot. A tie splits it, with any odd credit going to the first tied seat. The house takes no cut and pays no grand prize in a match. The info row shows every player's score, with the player whose turn it is lit in their colour (cyan, orange, lime, pink). Banners use the names on the cards.

One player plays the solo grand prize round described below.

## Rules and odds

- Tiles 1–9. Always two dice, even late in the round.
- Take any set of standing tiles that adds up to the roll, e.g. a 7 can be 7, 1+6, 2+5, 3+4 or 1+2+4.
- A roll that no standing tiles can make ends the turn. The stake is lost.
- Clear all nine and you win 13× the stake.

The game solves the board exactly. Each pick starts on the best play, marked **(BEST)**, and the info line shows your chance to clear from the current board. With perfect play the board clears 7.14% of the time, so the 13× grand prize returns about 93%.

## Controls

The arcade's three cabinet buttons (LEFT, CENTER, RIGHT from `.button_config`):

| When | LEFT | CENTER | RIGHT |
|---|---|---|---|
| Between rounds | BET (1 → 2 → 5 → 10) | PLAY | CASH OUT (eject card) |
| Seat screen | < FEWER players | START | MORE > players |
| Antes (match) | CANCEL (refund antes) | ANTE | |
| Before a roll | | ROLL | |
| After a roll | < OTHER way to make it | TAKE | OTHER > |

Keyboard: 1/2/3 or ←/↑/→, Space/Enter for CENTER, plus R (roll), T (take), B (bet), S (start) and C (cash out). Touch the bottom bar on a monitor. Q leaves between rounds.

## Money

On a house station, a solo round reserves the stake plus the grand prize with the house, using the same accounts as Pine Slots, Pine Jack and the Derby. It settles once: the prize on a clear, nothing on a dead roll. In a match, each card's ante reserves the whole pot as its maximum return. When the match ends, every card's round settles: the winner's with the pot and the others' with nothing. A match pays out to the accounts that anted even if a different card is in the drive at the end. Two seats on the same card share one round. If the host misses the settlement, the table holds on RETRY until the payout is confirmed. Without a house configuration, or with `--demo`, it uses a 100-credit practice meter.

## Development

`python3 derby/tools/run.py pinebox.tests.run` checks the solver against the known 7.14% and plays a forced grand prize, a dead roll, an OTHER pick, a 2-card pot match, a split pot and a cancelled ante through the real event loop. `pinebox.tests.physics` throws 200 dice pairs and checks every one settles flat inside the tray showing the drawn value. `pinebox.tests.rendered` dumps the throw frame by frame for `casino/tools/screens.py`.
