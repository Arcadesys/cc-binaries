# Pine Jack

Pine3D blackjack at a felt table. Cards fly out of the shoe and flip face up, the dealer's hole card turns over on the reveal, and chips slide to and from the tray. Run `pinejack` on an Advanced Computer or Advanced Monitor (39×19 minimum, 100×40 or larger so card ranks read in 3D). The text lines under the table always spell out each hand. Use `--terminal` or `--monitor NAME` to pick the display.

## Controls

Play uses the same three cabinet buttons as the arcade's other games (LEFT, CENTER, RIGHT from `.button_config`, as for Blackjack). The bottom bar labels what each button does right now.

| When | LEFT | CENTER | RIGHT |
|---|---|---|---|
| Between hands | BET (2 → 4 → 10 → 20 → 50) | DEAL | CASH OUT (eject card) |
| Your turn | HIT | STAND | DOUBLE or SPLIT, or MORE… when both are allowed |
| MORE… | DOUBLE | SPLIT | BACK |

Keyboard: 1/2/3 or ←/↑/→ for the three buttons, Space/Enter for CENTER, and the shortcuts H, S, D, P, B and C. Touch the bottom bar on a monitor. Q leaves between hands.

## Rules

Six-deck shoe, reshuffled once 75% has been dealt. The dealer stands on soft 17 and peeks for blackjack under an ace or ten. Blackjack pays 3:2, and bets are even so payouts are always whole credits. You can double on any first two cards, including after a split. One split is allowed, and split aces get one card each. A split 21 pays even money. There is no insurance or surrender.

## Money

On a house station, Pine Jack uses the same house accounts as the Derby and Pine Slots. DEAL reserves the stake plus the most the hand can return. Double and split raise the stake and the reservation before the card comes. The hand settles once, when it ends. If the host misses that settlement, the table holds on RETRY until the payout is confirmed. A crash mid-hand leaves the round open at the host for the operator to refund, as with the other arcade games. Without a house configuration, or with `--demo`, play uses a 100-credit practice meter.

## Development

`python3 derby/tools/run.py pinejack.tests.run` plays whole hands through the real event loop with stacked shoes: blackjack, dealer blackjack, bust, double, split with double after, split aces, and an offline settlement. `pinejack.tests.rendered` dumps screens for `casino/tools/screens.py`.
