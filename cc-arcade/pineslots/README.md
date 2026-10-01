# Pine Slots

A three-reel, five-line Pine3D slot machine built for a cabinet with a physical pull arm and three buttons. The screen shows the reels, marquee lamps and payline lamps. The arm and buttons are real redstone controls in the world.

Run `pineslots` on an Advanced Computer or with an attached Advanced Monitor (39×19 or larger). `--terminal` or `--monitor NAME` picks the display.

## Cabinet controls

| Control | Does | Keyboard / touch fallback |
|---|---|---|
| Pull arm | Spin | Space or Enter / tap the reels |
| BET ONE | Bet 1 → 5 credits, one payline per credit, wraps to 1 | 1 or B / left of the bottom bar |
| MAX BET | Bet 5, all lines | 2 or M / middle of the bottom bar |
| CASH OUT | Eject the house card (exhibition: reset the practice meter) | 3 or C / right of the bottom bar |

Wire each control to a redstone input, then run `pineslots setup` and use each one when prompted. Inputs can be computer sides or the sides of a **Redstone Relay** on the wired network. Relays help when the monitor, disk drive and house modem take up the computer's sides. Only rising edges count. A lever that stays on spins once per pull, and a held button does not repeat. Defaults before setup: arm `right`, BET ONE `left`, MAX BET `top`, CASH OUT `back`.

## Money

On a computer configured as a house station (`house setup station <modem> <host-id>`), Pine Slots uses the same house accounts as the Derby and the other arcade games. Insert a house card. Each pull reserves the stake plus the largest possible return for that bet (200–206 credits), picks the stops, and settles with the host before the reels start. The animation only reveals a result that is already settled, so pulling the card or losing power mid-spin cannot change a payout. If the host misses the settlement, the machine holds. Cash out is refused until a later pull confirms the payout. CASH OUT ejects the card, and the balance stays on the account for the cashier or another game. With no card inserted, the cabinet runs free attract spins.

Without a house configuration, or with `--demo`, it runs in exhibition mode with a 100-credit practice meter and no money.

## Paytable (per credit on a lit line)

| Line | Pays |
|---|---:|
| 💎 💎 💎 | 200 |
| 7 7 7 | 80 |
| BAR BAR BAR | 30 |
| BELL BELL BELL | 15 |
| PLUM PLUM PLUM | 10 |
| CHERRY CHERRY CHERRY | 10 |
| CHERRY CHERRY (from the left) | 3 |
| CHERRY (left reel) | 1 |

Lines: 1 centre, 2 top, 3 bottom, 4 and 5 the diagonals. Each reel has 16 equally likely stops, so the figures are exact: about 95% return per credit, and about 23% of lines pay.

## Development

`python3 derby/tools/run.py pineslots.tests.run` runs the paytable math, reel landing, controls, the live-wallet money path and the real event loop driven by fake inputs. `pineslots.tests.rendered` dumps screens. `python3 casino/tools/screens.py DIR` turns the dumps into PNGs.
