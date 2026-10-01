# Proposed single-house payout calibration

This is analysis only. No production paytable is changed or certified. Gross
return means the total settlement credit, after the stake has already been debited.

Reproduce with:

```sh
python3 cc-arcade/tools/test_contracts.py --suite tests/payout_analysis.lua
```

The script enumerates every PineSlots stop tuple and independently checks PineBox's
optimal decisions and clearance probabilities on all 512 board states. The result
passes 30,686 assertions on Lua 5.3 and 5.4.

## PineSlots

Sources: `pineslots/reels.lua` and the reservation/settlement flow in
`pineslots/machine.lua`. The strips have 16 stops each, sampled uniformly and
independently, giving 4,096 equally likely outcomes. Each active line costs one
credit; there are one through five active lines.

| Winning line | Current gross | Proposed gross | Single-line outcomes |
| --- | ---: | ---: | ---: |
| Diamond triple | 200 | 300 | 1 |
| Seven triple | 80 | 100 | 1 |
| Bar triple | 30 | 30 | 8 |
| Bell triple | 15 | 15 | 48 |
| Plum triple | 10 | 10 | 125 |
| Cherry triple | 10 | 10 | 36 |
| Two left cherries, third not cherry | 3 | 3 | 156 |
| One left cherry, second not cherry | 1 | 1 | 576 |
| No winning line | 0 | 0 | 3,145 |

- Current expected gross return: 3,894 / 4,096 = **95.068359375% RTP**
- Proposed expected gross return: 4,014 / 4,096 = **97.998046875% RTP**
- Proposed theoretical house edge: **2.001953125%**, identical per credit for
  every supported line count
- Exact 98% is not representable by a deterministic whole-credit paytable on
  these strips: 4,096 × 49/50 is not an integer

The only payout changes are Diamond +100 and Seven +20. Symbol frequencies,
paylines, cherry rules, and hit probabilities stay unchanged. The reservation must
cover the exact largest simultaneous payout:

| Bet / active lines | Current maximum gross | Proposed maximum gross |
| ---: | ---: | ---: |
| 1 | 200 | 300 |
| 2 | 203 | 303 |
| 3 | 204 | 304 |
| 4 | 205 | 305 |
| 5 | 206 | 306 |

This proposal increases required bank backing. It is near-98% theoretical return,
not a promise about finite-session winnings.

## PineBox solo

Sources: `pinebox/rules.lua` and `pinebox/game.lua`. Rules are tiles 1–9, always
two fair independent dice, remove any remaining subset summing to the roll, lose
on a roll with no legal subset, and win only by clearing every tile.

The independent dynamic program gives **7.143162230561%** optimal-clear chance.
The existing 13× gross prize therefore returns **92.861108997288%** under optimal
play. A 98% optimal-play benchmark would require **13.719414012568× gross**.

Keeping integer credits and choosing the largest fixed clear prize that stays at
or below 98% optimal-play RTP gives:

| Stake | Ideal clear prize | Proposed whole-credit gross | Optimal-play RTP | Optimal-play house edge |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 13.719414012568 | 13 | 92.861108997% | 7.138891003% |
| 2 | 27.438828025136 | 27 | 96.432690113% | 3.567309887% |
| 5 | 68.597070062840 | 68 | 97.147006336% | 2.852993664% |
| 10 | 137.194140125681 | 137 | 97.861322559% | 2.138677441% |

These are stake-specific gross prizes, not a common integer multiplier. Rounding
up at stake 1 would pay 14, yielding **100.004271227848%** optimal-play RTP, so
ordinary nearest-integer rounding would create a small player advantage there.

**Skill caveat:** poorer decisions reduce clearance probability and return. A
fixed “2% edge for everyone” is not valid for this skill game. The conservative
table above means at least 2% theoretical edge under the stated dice model, with
larger edge at coarse stakes and/or less-than-optimal play.

A theoretical 98% optimal-play benchmark needs a separately designed fractional
credit system or a clearly disclosed, host-controlled randomized prize on a clear:
pay `floor(ideal)` and add one with probability `ideal - floor(ideal)`. Such a
design needs its own payout disclosure, randomness, reservation (the upper prize),
durable outcome, and retry tests; it is not implemented here. Current multiplayer
PineBox distributes the player-funded pot; this solo analysis neither adds nor
certifies a match fee.

## Blackjack and skill attractions

Pine Jack currently uses six decks, stands on soft 17, peeks for blackjack, pays
3:2 naturals, permits double on any first two cards and after a split, permits one
split, and gives split aces one card. Even bets preserve whole-credit naturals.
Its standard returns are: normal win 2× total, natural 2.5× total, push 1×, loss 0;
split/doubled hands are paid on their respective reserved stakes. These rules are
preserved. They do not mean the house wins every round or certify a particular
long-run edge without a strategy/shoe analysis. Multiplayer-versus-house means
independent seat settlements under these rules, not a winner-takes-all pot.

Human skill in golf, bowling, baseball or dungeon play cannot be assigned a fixed
2% edge by a universal payout multiplier. Their intended pay-to-play mode should
have an explicit admission price with no winnings. The price, replay fee and
interrupted-session refund policy remain decisions, and admission integration is
not implemented by this harness.

## Pine Derby still needs separate calibration

The current `derby/odds.lua` table was calibrated over 100,000 simulation seeds.
This report does not retune or certify those race payouts at a 2% edge. A race-table
change needs a documented seed model, renewed calibration/error bounds, stake
rounding policy and reservation tests. Do not extrapolate the exact Slots result
to horse racing or other attractions.

## Multiplayer versus

Keep this separate from the solo house tables: winning payouts plus exactly one
credit of house rake must equal the ante pot. Two players anteing 5 produce a
9-credit winner payout; four produce 19. Ties must conserve the odd credit, and
shared-account seats must aggregate by account. Current Pine Box pays its entire
pot with no rake, and v1 has no atomic multi-account match settlement. An approved
match/rake implementation and crash recovery tests are needed before claiming the
requested mode is deployed.
