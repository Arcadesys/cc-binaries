# Pine entertainment-complex contract harness

Run from any directory (Python resolves the repository paths):

```sh
python3 cc-arcade/tools/test_contracts.py
python3 cc-arcade/tools/test_contracts.py --suite tests/support_contracts.lua
```

Requires Python 3 and Lua 5.3 or 5.4. An existing LuaTeX installation works too.
Use `--lua /path/to/lua` or `PINE_LUA` to choose a runtime. No package download,
Minecraft installation, credentials, modem, or inventory is required. Exit status
is nonzero on an assertion failure or timeout. CI runs the support and contract
suites on both Lua versions. This does **not** replace the existing CraftOS suites.

## Interrupted-raise recovery gate

The default suite includes this recovery regression. To run it alone:

```sh
python3 cc-arcade/tools/test_contracts.py --suite tests/known_recovery_gap.lua
```

This reproduces the original lost-increase bug and now requires captured and
persisted stake/maximum to converge to authoritative host terms. It also asserts
that acknowledging an earlier increase cannot count as completing a later blocked
settlement. The separate CI release-recovery job remains a required behavioral
check; it has not been disabled or marked optional.

Recovery persists a marker before querying host terms, blocks new mutations until
reconciliation finishes, and matches the exact operation/account/round. Jack holds
a tentative double/split through uncertain acknowledgments instead of rolling it
back and continuing. Definite declines still roll back. Jack and Box forward actual
CC event waits from their game scripts, so wallet Rednet replies and timeouts reach
the waiting code without a competing card refresh consuming them.

Update the house host before clients: successful v1 roundStatus responses now
include additive stake and maximum fields. Existing clients ignore these extras;
new clients fail closed during recovery if an old host cannot supply them. A
program restart reconciles financial terms, not a vanished blackjack shoe or game
state. An interrupted open hand still requires the documented cashier
review/refund path before a new game starts. Native CC/peripheral acceptance below
is still required; local/CI green does not imply in-game verification.

## What actually runs

The router boots independent virtual computers and loads the **production**
`derby.client`, `derby.server`, `derby.config`, `derby.service`, `derby.ledger`,
`derby.house`, and `derby.store` unchanged. Server dispatch is not copied into a
fake handler. Each computer gets its own module cache, in-memory filesystem and
timer table. Messages are serialized/deserialized before delivery so sender and
receiver cannot accidentally share mutable tables. Restart tests discard modules
and rebuild from persisted JSON bytes. The store's two-generation/checksum logic
runs for real. Only hardware, time, event scheduling and host-screen drawing are
replaced. All fixture accounts, credits and inventory diamonds are fictional.

`contracts/house_v1.lua` is an independently authored fixture/shape corpus.
`support/hub.lua` supplies deterministic routing and faults; `rednet_contracts.lua`
asserts wire and accounting behavior. Consumer tests drive actual attraction
logic with presentation/input doubles, rather than awarding credits directly.
`support_contracts.lua` checks the test doubles themselves, including real JSON
bytes, malformed JSON, filesystem isolation and persistence behavior.

Coverage includes:

- Actual v1 request/reply envelopes, token correlation and sender/protocol filters
- Clean timeout for incompatible protocol or malformed envelope; malformed inner
  requests return errors without killing the host
- Unregistered computers, display read-only role, cashier-only operations,
  transaction ownership and captured round ownership
- Dropped requests/replies, duplicate packets, reordered requests, delayed stale
  replies, client restart, host restart and exactly-once receipt replay
- Simultaneous stations using one account, no overspend, no settlement beyond a
  reservation, refund/settlement once, and bank liability remaining backed
- Virtual inventory transfers, lost cashier acknowledgments, uncertain transfer
  reconciliation markers, and no automatic second item movement
- Damaged latest persistence generation fallback and fail-closed total corruption
- Current attraction wallet contracts and freeplay boundaries

### Important distinctions

A green result proves the named deterministic scenarios under these doubles. It
is **not** Minecraft/CC:Tweaked in-game acceptance, a complete Rednet emulator,
a security audit, or a statistical certification of a payout table. The virtual
hub does not simulate modem range, channels, chunk unloads, peripheral API quirks,
real filesystem power loss, or actual UI rendering. A timer only advances when a
test asks it to; the host race loop does not run unattended in the background.

Role/ID checks are current application policy, not cryptographic authentication.
The standalone JSON implementation covers the contract data used here; native CC
serialization behavior still needs the acceptance checks below.

Uncertain physical transfers intentionally require an operator to inspect the
actual bank/intake/output and reconcile; the suite does not pretend this case can
be recovered automatically. A corrupt latest generation can roll back to the
previous one, so real inventory counts must still be reconciled after corruption.

## Requested play modes: acceptance target versus implementation

`contracts/play_modes.lua` contains **proposed acceptance fixtures**, not a new
wire protocol or deployed match coordinator. No game pricing or payout tables
are changed by this harness. See [payout-analysis.md](payout-analysis.md) for
source-derived whole-credit tables and their exact expected returns.

| Mode | Accounting invariant | Current implementation boundary |
| --- | --- | --- |
| Single player against house | Reserve before play; payout inside maximum; target expected total return is 98% of stake | Existing house ledger/paid games work; each game's payout calibration and strategy assumptions require separate review |
| Multiplayer versus | Escrow every ante; distribute pot minus exactly one credit per completed match; settle once | No atomic multi-account match/pot/rake primitive exists in v1; fixtures alone do not implement it |
| Multiplayer versus house, blackjack only | Independent player reservations and normal blackjack payouts; no PvP rake | Existing blackjack rules and per-account house rounds exist; multiplayer table/session coordination does not |
| Single-player arcade admission | Charge exactly once; no prize payout | Existing reserve then zero-return settlement can express admission; currently-free attractions still need admission wiring |

The executable admission test uses a reservation followed by a zero payout and
replays a lost settlement receipt: it charges one fee only. It does not claim the
freeplay attractions are already connected to that flow.

A two-player 5-credit ante match pays the winner 9 credits and the house 1; four
players at 5 pay the winner 19 and the house 1. A tied net pot must conserve every
credit; the fixture's 5/4 split of a 9-credit pot illustrates conservation only.
Tie priority/odd-credit recipient, abandoned matches, partial ante collection,
refunds before start and disconnect/rejoin policy must be decided before building
the match coordinator. The one-credit rake is per completed match, not per
player or per retry. Do not implement multiplayer as unrelated `settle` calls:
a crash between player payouts would violate atomicity.

For a 2% single-player house edge, require an evidence-backed payout table per
game: `sum(probability(outcome) * totalReturn(outcome)) / stake = 0.98` under the
specified player strategy. “Total return” includes the original stake. Integer
credit denominations can make an exact 98% target unattainable at a given stake.
Slots can be enumerated; skill games and blackjack require explicit strategy and
rules assumptions. Blackjack does not guarantee house profit every round.

## Configurable item currency: next implementation boundary

The deployed v1 cashier still accepts and redeems only diamonds, one diamond per
credit. Current wire tests prove partial movement, full output, duplicate/lost
receipts and verified reconciliation for that actual implementation; they also
prove gold and eyes of ender are currently ignored rather than silently credited.

[The proposed currency contract](CURRENCY_CONTRACT.md) and
`contracts/currency_policy.lua` define separately enabled deposit/redemption items,
exact registry/NBT identities, integer atomic-unit rates, immutable policy revisions
and actual-movement receipt invariants. Rates in its fixtures are synthetic test
values, not configured economic prices. This acceptance oracle does **not** add
multi-item currency support to production. A versioned inventory/ledger/cashier
migration and in-game acceptance are still required, after recovery is corrected.

## Protocol compatibility admission gate

The implemented protocol remains `pine-derby-house-v1`; neither `pine-house-v2`
nor player/score protocols are introduced or silently accepted.

| Producer → consumer | Checked behavior |
| --- | --- |
| Current v1 client → current v1 host | Accepted valid requests; canonical response shapes |
| Wrong/future protocol → v1 host | Ignored without ledger mutation; client times out with retry retained |
| Foreign protocol/sender/token → v1 client | Ignored; only correlated host response completes request |
| Future version/adapter | Unsupported; add deliberate fixtures and producer/consumer matrix before shipping |

Pine Face's separate multiplayer protocol is not a wallet protocol. Its existing
network suite remains the source for gameplay-network compatibility. Future
identity/mascot and score services should have their own small contracts instead
of being folded into the money protocol.

## Real CraftOS / Minecraft release gate (not performed by this suite)

Use a disposable test world and dedicated test computers/inventories. Record CC
version, modpack, computer IDs, wired modem names, installed commit, starting bank
count, every account balance and open reservation. Never run destructive test
setup against a live bank. The host already starts paused for live acceptance.

1. Run existing installation/renderer/game suites in an isolated CraftOS instance:
   `python3 cc-arcade/derby/tools/run.py derby.tests.run` and
   `python3 cc-arcade/derby/tools/run.py pinearcade.tests.run`. The existing runner
   currently assumes the macOS CraftOS-PC path; select a suitable installation or
   adapt it separately rather than claiming the headless harness covers rendering.
2. Install the same commit on a house host, cashier and two stations. Register only
   those IDs and a display. Confirm wrong IDs and the display cannot mutate funds.
3. With fictional test credits, create/deposit to one shared account; start rounds
   simultaneously on both stations. Verify the second request cannot overspend.
4. Interrupt a wired connection after a reservation and after a settlement; retry
   on the original station and reboot it. Verify one debit/one payout and the same
   round/transaction receipts. Reboot the house between commit and response.
5. Disconnect an inventory during a cashier transfer. Inspect physical movement,
   reconcile once using verified counts, then check bank equals the physical
   diamond count and covers balances plus open maximum liabilities.
6. Exercise real card swaps, monitor/keyboard input, game return to launcher,
   startup selection, unavailable monitor/speaker, and all installed game loads.
7. For future multiplayer modes, do not release until all antes are escrowed
   atomically, the winner pot and one-credit rake settle once across crashes, ties
   conserve odd credits, and every disconnect/refund policy has a passing case.
8. Keep the release gate open until both the automated result and these witnessed
   in-game checks are recorded. Store starting/ending balances, bank counts and
   receipts with the version tested; a screenshot alone is insufficient evidence.
