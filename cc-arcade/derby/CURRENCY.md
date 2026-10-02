# Configurable item-backed credits (ledger version 2)

Production implementation, opt-in. This changes the host/cashier currency adapter,
not game pricing, prizes, multiplayer pots, rake or blackjack UI. All games and
accounts still use one integer credit unit (`creditScale=1`). Existing diamond
balances and reservations are never multiplied, rounded or reset. No fractional
credit rates, recipe conversion, automatic substitutions or exchange spreads.

## Configuration

`house setup host` writes a `currency` object in `/house-config.json`:

```json
{
  "schema": "pine-currency-policy",
  "schemaVersion": 1,
  "policyId": "pine-house-credits",
  "revision": 1,
  "creditScale": 1,
  "maxTransferUnits": 1000000000,
  "entries": {
    "diamond": {
      "itemId": "minecraft:diamond",
      "depositEnabled": true,
      "redeemEnabled": true,
      "unitsPerItem": 1,
      "identity": {"allowNoNbt": true, "nbtHashes": [], "metadata": {}}
    },
    "gold": {
      "itemId": "minecraft:gold_ingot",
      "depositEnabled": false,
      "redeemEnabled": false,
      "identity": {"allowNoNbt": true, "nbtHashes": [], "metadata": {}}
    },
    "ender_eye": {
      "itemId": "minecraft:ender_eye",
      "depositEnabled": false,
      "redeemEnabled": false,
      "identity": {"allowNoNbt": true, "nbtHashes": [], "metadata": {}}
    }
  }
}
```

Gold and eyes of ender have **no preset rate** and cannot be accepted or redeemed
until the operator sets a positive integer `unitsPerItem`, chooses the independent
flags, and explicitly applies a new revision. Other exact namespaced registry IDs
can be added with the same entry structure. One entry per registry ID; no wildcards,
tags, display-name matching or automatic ingot/block equivalence. Enable only
identities tested in the actual modpack. Synthetic rates in tests are not advice.

To change an active policy, keep its `policyId`, increase `revision`, edit the
configuration while the host is stopped, restart paused, and use **M** to apply.
Config edits alone never change the saved policy. Existing receipts retain their
original item/rate/revision. Priced entries with both flags false retain their
accounting value; deleting/unpricing an entry or reducing a rate removes/reduces
its stock valuation and is rejected if liabilities would become unbacked.
A bank-value limit of 1,000,000,000 credits and a per-transfer cap are enforced.

`identity.allowNoNbt` explicitly admits stacks without a fingerprint; `nbtHashes`
admits only exact hashes observed from the actual peripheral. Scalar metadata
allowlists support `damage`, `maxDamage` and `unbreakable`. Every configured field
must be present and allowed, and every observed scalar metadata field must be
configured. Example: `"metadata":{"damage":[0],"maxDamage":[1561]}`. This is a
shape example, not an enabled pickaxe currency. Unknown detail fields fail item
admission until the adapter is reviewed and extended.

## Safe migration and deployment

1. Update host and cashier together, leaving the host paused. Keep a separate
   offline copy of the entire existing bank directory and configuration. Stop
   customer access and hoppers/automation to all three distinct inventories.
2. Resolve every pending physical transfer under the original v1 system. Audit
   diamonds, account balances, open rounds, original receipts and outstanding
   maximum liabilities. The migration rejects a mismatched legacy diamond count.
3. For the default migration, leave policy revision 1 unchanged: plain diamond
   remains one credit. Nonplain diamonds need explicit verified identity rules;
   excluded stock contributes no backing. Inspect actual classified inventory
   before approving any alternative policy. No deployment inventory was inspected
   by this change.
4. Press **M** on the paused host to apply the policy. It preserves both exact old
   generation files as `state.backup-v1.0` and `.1`, verifies the copies, writes a
   version/revision guard, and commits both v2 generations. Later policy changes
   use `state.backup-v2-r<old revision>.<slot>`. Existing different backup bytes
   are never overwritten. Balances, open rounds and old transaction receipts
   remain intact.
5. Verify the saved bank is weighted credit value, inspect each item stock and
   liability, and exercise the disposable-world checklist below before restarting
   paid operation. The cashier queries the authoritative saved policy, cycles items
   with Up/Down (or touches the item line), and reviews the item count, value and
   expected balance. Actual partial movement can differ from the quoted maximum.
6. Only after verification press **P** to resume games. **F** recognizes added
   classified house stock; it refuses a shortage of any recorded item, even when
   another item could offset its value.

The wire envelope remains `pine-derby-house-v1` for unchanged integer-credit game
operations. The new cashier operation is explicitly `op=exchange, apiVersion=2`,
with `direction`, `entryId`, `requestedItems`, `policyId` and `policyRevision`.
Legacy deposit/withdraw requests are rejected on a migrated host. Old durable
receipts can still replay unchanged. New cashiers can use an updated host still
in v1 mode; they fail closed if the currency capability cannot be read. Do not
mistake this additive operation gate for support for a different wire protocol.

## Physical transfers, backing and uncertainty

Before moving anything the host durably records the original account, exact
request, immutable entry/rate snapshot, policy revision, inventory peripheral
names, classified counts in bank/intake/output, and any redemption hold. It then
checks the observations again. Completed receipts record requested and confirmed
item quantities, signed credits, original identity/rate/revision and balance.

The inventory adapter selects admitted stacks and validates each numeric
`pushItems` return. The service independently verifies the complete classified
before/after deltas for source, destination and the untouched third inventory.
Credit/debit is exactly actual items times the pinned rate; unused redemption
hold is released on partial/zero movement. An identical request replays its
receipt; changed request content under the same ID is rejected.

A failed move, mismatched delta, lost return or crash leaves an uncertain intent.
**No physical transfer is automatically retried, even when it appears no items
moved.** Financial mutations/round ticks freeze while a transfer is pending.
Use **R** only after inspecting and isolating the original three inventories;
enter the verified actual item count. All classified deltas must match the saved
observations. If customers/hoppers changed the evidence, restore verified
consistency or keep the transfer pending; do not infer movement from a scalar
bank total. This tool cannot reconstruct unknowable physical history.

Weighted backing is `sum(admitted item count * configured integer rate)`. It must
cover balances, maximum open-round returns and pending redemption holds. That is
solvency, **not specific-item liquidity**: a diamond-rich bank cannot redeem gold
it does not hold. Deposit-only stock has value but no output route; the operator
must deliberately approve that liquidity policy.

## Persistence recovery tradeoff

Version 2 saves pin a fail-closed exact sequence/revision and payload checksum
**before** every new generation. A corrupt or interrupted latest generation is not silently replaced
with an older financial state: that could erase a transfer intent and replay
physical movement. This sacrifices availability for conservation. A missing,
invalid or ahead-of-state guard stops startup; it does not create a fresh bank.
Legacy v1's historical two-generation fallback remains unchanged.

Recovery is offline and operator-reviewed: keep original files, backups, guard,
configuration and physical evidence; determine the latest coherent transactions
and actual inventory movements before restoring a mutually consistent v2 state
and guard. Never delete the guard merely to make an old save load. Restoring a
pre-migration backup without accounting for later physical transfers can duplicate
or lose credits. Older binaries do not understand this guard; do not roll back
runtime code against a migrated bank. This implementation supplies no automatic
financial-history reconstruction or one-click downgrade.

## CC:Tweaked API evidence and limitations

Official sources checked 2026-10-01:

- [Generic inventory peripheral](https://tweaked.cc/generic_peripheral/inventory.html):
  sparse `list()` results, detail lookup, named wired-network destination and
  numeric actual-moved return from `pushItems`
- [Item details](https://tweaked.cc/reference/item_details.html): registry name,
  count, optional NBT fingerprint, top-level damage/durability fields and known
  display projections

`list` and detail must agree on name/count/NBT during inspection. Presentation
fields do not set a price; unknown detail fields are rejected. The documented
name/NBT identity is the basis for variant matching, with explicit scalar rules
where configured. The API offers no atomic compare-and-transfer lock: controlled
physical access is mandatory, and before/after checks cannot distinguish all
coordinated outside changes. Actual modpack behavior, chunk unloads, concurrent
hoppers and storage power-loss durability still require witnessed acceptance.

## Verification

```sh
python3 cc-arcade/tools/test_contracts.py
python3 cc-arcade/tools/test_contracts.py --suite tests/currency_identity.lua
python3 cc-arcade/tools/test_contracts.py --suite tests/currency_runtime.lua
python3 cc-arcade/tools/test_contracts.py --suite tests/currency_wire.lua
python3 cc-arcade/derby/tools/bundle.py
```

The suites exercise actual production modules with fictional local inventory and
filesystem doubles. They are not Minecraft, CraftOS rendering, or real peripheral
acceptance. Before live use in a disposable world, record installed commit,
CC/modpack versions and every enabled registry/NBT/metadata identity. Exercise:
plain and rejected variants; every enabled deposit/redemption direction; empty
stock and full/partly full output; disconnected push and loss after movement;
client/host restarts before and after intent/receipt; old-client rejection; card
swaps; rate revision/stale quote; migration backups and stopped corrupt-state
recovery. For every case record starting/ending physical classified stock, account
units, reservations, holds and durable receipt; assert exact conservation. Keep
bank/intake/output isolated throughout. Do not release merely because mocks pass.
