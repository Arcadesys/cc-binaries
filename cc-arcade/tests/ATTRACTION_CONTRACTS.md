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
| Pine Jack | One player versus dealer, with one optional split | Opening 3:2 reservation, double and split/double maximum increases, aggregate settlement, definite-decline rollback, real-wire lost double/split hold/retry and exactly-once continuation |
| Pine Shut the Box | Solo against house; 2–4 seats ante into a shared pot | Solo 13x reservation/loss, cancelled ante refund, two seats sharing one account/round, two separate cards and account-specific tie settlements; real-wire lost ante/increase recovery and cancellation |
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

## Interrupted-round recovery regression coverage

The original failure is fixed: reserve 4/10, commit an increase of 2/12 while
losing its reply, then retry. Captured and persisted terms now converge to host
stake 6 / maximum 12. The receipt remains bound to its operation, account and
round; acknowledging the increase cannot count as acknowledging a blocked payout.

`known_recovery_gap.lua` retains this exact regression and is included in the
default suite as well as a separate blocking CI job. It must exit zero:

```sh
python3 cc-arcade/tools/test_contracts.py --suite tests/known_recovery_gap.lua
```

The consumer tests also run **actual Jack and Box event loops with the real
wallet, credits adapter, client and host**. Rendering/audio remain stubs. Tests
cover:

- Jack double/split with a lost request or lost reply, repeated same-ID retries,
  ignored gameplay/Q controls while the financial action is unresolved, exactly
  one continuation and settlement, and rollback after a definite host decline
- Authoritative metadata lookup loss, missing legacy-host fields, durable recovery
  marker after client recreation, and blocked new mutations until reconciliation
- Operator-closed rounds, interrupted terminal balance lookup, correct captured
  account display, and valid aggregate balances above the per-transaction cap
- Box first-ante reservation and shared-card later increase with request/reply
  loss, one seat/pot increment, exact recovered-stake cancellation refund and a
  completed shared-card tie
- CC nil/string event-filter forwarding through both gameplay coroutines, frame
  progress during transport waits, and no competing card-refresh network call

A cashier/host update must precede clients for the new additive `roundStatus`
terms. A new client will hold recovery rather than guess when an older host omits
stake/maximum. Restart reconciles ledger state; it does not restore a vanished
shoe, hand or game world. Already-open interrupted games still require the
existing cashier review/refund path before another round begins. General
reservation failures outside the covered ante/raise continuation retain their
existing station-retry/operator-review flow. None of these results replaces the
real CC:Tweaked/peripheral acceptance checklist.

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
