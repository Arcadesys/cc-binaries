# Pine Arcade attraction contract matrix

`consumer_contracts.lua` loads production source unchanged, in isolated Lua module
environments. It substitutes recording renderers/audio and a recording credits
adapter, then drives the **actual** casino game event loops and free-attraction
controllers. A separate integrated regression runs the real wallet and credits
module through the fake-Rednet host, including lost acknowledgements and client
recreation. The recording-adapter scenarios alone do not test persistence,
authentication, packet loss, or the real host ledger.

## Current source and exercised contracts

| Attraction | Current money mode | Executed consumer coverage |
| --- | --- | --- |
| Pine Slots | Live account rounds when station/cashier is configured; local exhibition otherwise | Game ID, 5-credit MAX bet with 206-credit maximum, settlement before animation, ignored second pull during spin, pending-payout cashout guard, failed/successful retries, cashout after acknowledgement |
| Pine Jack | One player versus dealer, with one optional split | Opening 3:2 reservation, double and split/double maximum increases, aggregate settlement, rejected increase rollback |
| Pine Shut the Box | Solo against house; 2–4 seats ante into a shared pot | Solo 13x reservation/loss, cancelled ante refund, two seats sharing one account/round, two separate cards and account-specific tie settlements |
| Pine Lanes (Furball bowling) | Free local gameplay | Setup/mascot selection, actual physics roll and scored result, exit, no money/network API access |
| Pine Links (Furball golf) | Free local gameplay | Start, actual physics shot and stroke accounting, exit, no money/network API access |
| Pine Ball (Furball baseball) | Free local gameplay | Start, actual pitch/outcome commit, exit, no money/network API access |
| Pine Dungeon | Free local gameplay | Actual world turn, exit, no money/network API access |

The shared wallet coverage additionally checks card removal, replacement of a card
at the same mount path, account ownership of later settlements/refunds, failed
lookup cleanup, rejected reservations, ejection suppression, launcher role/demo
selection, practice-meter reset, and cardless Slots attract animation. The retry
regression preserves a replacement card's balance and unrelated open round; the
credits adapter returns the account from the persisted request alongside the
receipt, so ownership also survives lost begin/increase replies and restart.

Free-game tests reject any access to credits/wallet, disk, filesystem, peripherals,
HTTP or Rednet during the exercised controller paths, and reject house-module
imports. They test the gameplay boundary, not complete launcher/UI behavior. The
production command-line entry points may legitimately write explicitly requested
`--log` files. Full rendering, physical hardware and user-visible layout require
the existing CraftOS-PC/rendered suites or hardware verification.

## Requested policy versus current implementation

The requested direction is: single-player house games targeting about 2% house
edge; player-versus-player games paying the ante pool minus a one-credit rake;
multiplayer blackjack remaining individual hands versus the house under normal
blackjack rules; arcade games charging admission. Those requirements are **not**
already implemented by the current source or by these tests.

| Requested behavior | Current evidence / gap |
| --- | --- |
| Approximately 2% house edge | `pineslots/reels.lua` exact enumeration returns RTP `0.95068359375`, a 4.931640625% house edge per credit. `pinebox/rules.lua` best-play clear probability is approximately `0.071431622305606`; the current 13x payout yields RTP `0.92861108997288`, a 7.1388910027% edge. Paytable/rules changes need their own calibration and reservation updates. |
| One-credit multiplayer rake | `pinebox/game.lua` currently divides the **whole** pot among winners; odd credits go to the first tied seat. No one-credit deduction is present. Changing this requires settlement and displayed-pot agreement, including ties and multiple seats sharing an account. |
| Multiplayer blackjack versus house | `pinejack/game.lua` has one active player; its split-hand array represents that player's hands, not separate players. `pinejack/rules.lua` defines the current six-deck, S17, 3:2, double/split rules. No validated strategy/house-edge calculation or multi-seat account controller is present. |
| Pay-to-play arcade admission | Lanes, Links, Ball and Dungeon controllers currently start and restart locally with no wallet. No paid admission API is assumed or fabricated by the harness. |

These numeric results are calculated from the checked-in deterministic math, not
marketing estimates or a simulation confidence interval. The blackjack edge has
not been calculated by this harness.

## Remaining interrupted-raise limitation

Receipt ownership and the displayed account balance are covered after a lost
`increase` acknowledgement. Full gameplay recovery for that case is **not**
certified: the current credits adapter does not reconcile the caller's captured
round stake/maximum or its saved round entry when replaying an increase receipt.
For example, reserving 4 then increasing by 2 with a lost reply can leave a captured
stake of 4 while the host reservation is 6. The host remains authoritative and
blocks a new round while the old one is open, but the game's rolled-back raise
and refund meter require a separate recovery change and regression before live
acceptance. This is an existing limitation, not fixed by the receipt-account guard.


The separate, non-default release gate reproduces this against the real wallet,
credits adapter, client, host and saved bytes:

```sh
python3 cc-arcade/tools/test_contracts.py --suite tests/known_recovery_gap.lua
```

**Expected today: exit 1. This failure blocks live readiness.** It is intentionally
excluded from the passing regression suite, not waived or counted as a passing
expected-failure assertion. The minimal sequence is reserve 4/10, lose the reply
for an increase of 2 with maximum 12, attempt a settlement while that increase is
pending, then retry. Current error:

```text
KNOWN RECOVERY GAP: interrupted increase metadata did not converge: captured stake=4, host=6; persisted stake=4, host=6; captured maximum=10, host=12; persisted maximum=10, host=12
```

The reproducer also prints the real diagnostic that settlement was blocked,
retry acknowledged `increase`, and the host round remains `open`. It does not
claim to drive the full blackjack event loop for that diagnostic.

To unblock: reconcile authoritative round stake/maximum after recovering an
increase, preserve the intended gameplay action through acknowledgement loss,
and distinguish an increase receipt from a settlement/refund receipt before
allowing gameplay to resume or showing a payout as confirmed. Add actual Jack
lost-double/lost-split event-loop regressions, correct refund/display checks, and
restart coverage. This requires a separately reviewed continuation change; do
not fix it by allowing a second charge, forgetting the open round, guessing the
new stake, or making this gate accept stale metadata.

## Integration seams for a later paid-mode implementation

1. Keep the existing transport boundary: `casino/wallet.lua` calls
   `credits.beginRound`, `increaseRound`, `settleRound`, `refundRound` and `retry`.
   The host validates every reservation and result. Do not restore local balance
   edits or put balances on disks.
2. Model arcade admission as an injectable adapter around the **game's new-session
   transition**, not only `pinearcade/app.lua`'s menu launch. Direct command-line
   launches and replay/restart paths bypass the menu. The relevant transitions are
   Lanes setup/restart (`lib/app.lua`: `action`, `resetMatch`), Links
   `restart`/`action`, Ball `start`/`action`, and Dungeon initial `new` and new-run
   action. Pure constructors should remain usable by freeplay tests; the adapter
   should authorize a new paid session before live play starts.
3. Existing ledger operations can represent a non-refundable consumed admission
   with `reserve(stake=fee, maximum=fee)` followed by `settle(amount=0)`. The
   maximum cannot be zero because the current ledger requires maximum at least
   stake, preserving refundability before consumption. This is a proposed use of
   existing operations, not an implemented admission policy. Persisted session
   identity, retry after reboot, when admission is consumed, and which cancellations
   refund must be specified and tested before enabling it.
4. A multiplayer settlement should calculate the distributable pot once, apply the
   one-credit rake once per completed match, allocate ties deterministically, then
   aggregate payments **by account** before settling each account's reservation.
   A cancelled match should follow an explicit refund/rake policy. Test shared-card
   seats, card swaps/removals, partial ante collection, and interrupted multi-account
   settlement. At present the host ledger is per-round, not an atomic multi-account
   pot settlement service.
5. Blackjack multi-seat play needs per-seat account ownership with independent
   house payouts. It should not reuse the player-versus-player winner-pool rules.
   For all paid modes, a rejected reservation must prevent starting, and a pending
   result must prevent a new charge until acknowledged or reviewed.

Changing payout policy, admitting paid sessions or adding multiplayer modes is
outside these harness and narrowly scoped hardening changes. The current free boundary assertions intentionally
make a future migration explicit: update them together with approved production
admission logic and transport/recovery tests, rather than silently relabeling a
free controller as paid.
