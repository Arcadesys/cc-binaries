# Configurable item-backed credits: proposed contract

Status: design acceptance fixtures only. `contracts/currency_policy.lua` does not
implement a new cashier, inventory adapter, wallet, network protocol or migration.
Its synthetic rates are examples for integer arithmetic, not selected production
exchange rates. The user has requested configurable backing items; actual rates,
redemption choices and treatment of existing balances remain undecided.

## Current production boundary

- `derby/inventory.lua:count/move` explicitly matches `minecraft:diamond`. Other
  registry IDs are ignored. Current matching does not distinguish diamond NBT
  variants; the proposed identity rules below are stricter and undeployed
- `derby/ledger.lua` stores `version=1` and a scalar `bank`. That field means a
  diamond count. One diamond deposits one credit, and one credit withdraws one
  diamond. `amount`, `moved`, `pending.amount`, and `pending.beforeBank` have this
  same denomination. Reserve/settle APIs use integer credits
- `derby/service.lua` compares physical diamond counts with that scalar bank,
  persists transfer intent before moving items, and credits/debits confirmed
  movement. An uncertain transfer requires operator reconciliation
- `derby/store.lua` provides checksummed two-generation persistence. It has no
  currency-policy migration or semantic schema validation. Changing its input
  tables does not by itself migrate accounts, reservations or outstanding receipts

The real v1 integration tests continue to cover these diamond-only paths. Passing
the separate proposed-policy fixtures proves only their stated design invariants.
Do not claim that gold, eyes of ender or modded items are accepted by a live host.

## Concrete proposed policy schema

Illustrative JSON; every value/rate below is SYNTHETIC TEST DATA:

```json
{
  "schema": "pine-currency-policy-proposal",
  "schemaVersion": 1,
  "policyId": "SYNTHETIC-TEST-ONLY",
  "revision": 7,
  "creditScale": 1,
  "maxTransferUnits": 1000000000,
  "entries": {
    "diamond": {
      "itemId": "minecraft:diamond",
      "depositEnabled": true,
      "redeemEnabled": true,
      "unitsPerItem": 12,
      "identity": {"allowNoNbt": true, "nbtHashes": [], "metadata": {}}
    },
    "gold": {
      "itemId": "minecraft:gold_ingot",
      "depositEnabled": true,
      "redeemEnabled": true,
      "unitsPerItem": 3,
      "identity": {"allowNoNbt": true, "nbtHashes": [], "metadata": {}}
    },
    "eye": {
      "itemId": "minecraft:ender_eye",
      "depositEnabled": true,
      "redeemEnabled": false,
      "unitsPerItem": 24,
      "identity": {"allowNoNbt": true, "nbtHashes": [], "metadata": {}}
    }
  }
}
```

The executable fixture also includes a hypothetical `examplemod:arcade_token`
with redeem-only permission, one explicitly allowlisted synthetic NBT fingerprint,
and metadata rule `damage: [0]`. This is not an assertion that that mod/item exists
in the user's world.

Policy properties:

1. Registry IDs are exact, namespaced, lowercase strings. No display-name,
   substring, wildcard, tag, ore-dictionary or automatic block/ingot equivalence
2. One entry per registry ID prevents overlapping identity/rate rules from
   valuing a stack twice. The proposed adapter supports multiple allowed NBT
   fingerprints for that entry, all at its one explicit rate
3. Deposit permission and redemption permission are independent. Turning deposits
   on does not imply that customers can redeem that item, or vice versa. Both
   flags may be false for a retained but exchange-disabled entry
4. A policy ID/revision is immutable. Transactions retain the complete applicable
   entry/identity/value snapshot or an immutable revision reference plus integrity
   digest. A rate edit creates a new revision; retries never reprice a transaction
5. `creditScale` is the number of integer atomic units per displayed credit.
   All ledger balances, reservations, holds, prizes and fees must use that same
   unit. Example only: scale 100 and value 25 represent a quarter-credit item;
   three items are 75 units. Value 0.25 atomic units is rejected, never rounded
6. `maxTransferUnits` caps count × value before multiplication. Arithmetic must
   remain in the exact integer range supported by all deployed Lua/CC runtimes;
   these proposal tests reject values above 2^53−1 and test aggregate overflow

No exchange spread is proposed here: the same immutable item value applies to
both directions when enabled. Distinct buy/sell rates, bonuses, taxes and dynamic
market prices would require new explicit policy and accounting tests.

## Identity and inventory admission

The proposal validates a normalized record:

```json
{"name":"minecraft:diamond","count":3,"metadata":{}}
```

`nbt` is absent for a plain item or contains an exact peripheral-supplied
fingerprint. A nonplain fingerprint must appear in `nbtHashes`. Each configured
metadata field is required and must match one of its allowed scalar values; extra
metadata fields are rejected. Unknown fields on the normalized record are also
rejected. Do not feed a raw peripheral detail table directly into this validator.

A future adapter must explicitly normalize the actual CC/modpack item detail
format, document which meaningful component/NBT/metadata fields it covers, and
fail closed when required identity information is unavailable. Display names and
icons are presentation, not identities. Fingerprints must be observed in the
specific deployment; this proposal does not prescribe or guess their algorithm.
Accepting every NBT variant or every item sharing a tag requires a separate policy
choice. If identity cannot be verified from `list`, obtain and validate detailed
slot data before counting or moving it.

A move receipt counts only admitted items of the pinned entry. Concurrent
insertion/replacement, stale slot details and changes between inspection and
`pushItems` remain real-world adapter risks. Require controlled access during
transfer/reconciliation and validate what is actually in the bank/output. An
item-count receipt alone cannot establish item identity.

## Proposed transaction and durable receipt

A new versioned API would distinguish `requestedItems` from `requestedUnits` and
pin `id`, `account`, `policyId`, `policyRevision`, `entryId` and `direction`
(`deposit`/`redeem`). The cashier should display the exact item, count, exchange
value and expected balance before committing. No new API version is implemented
or assigned by this harness.

Durable intent records the immutable identity/value policy, requested item count,
starting classified inventory counts, source/destination identities, original
account, and any redemption hold. The account is captured before card removal.

- Deposit: save intent before movement. Credit only `confirmedItems ×
  unitsPerItem` after actual movement and the durable receipt are established
- Redemption: reserve the requested units before movement. Final debit is only
  `confirmedItems × unitsPerItem`. Release the unused reservation; do not charge
  for requested items which a full chest or empty bank could not deliver
- Zero movement: complete a zero-credit/zero-debit receipt and release any hold
- Partial movement: commit the exact moved count and value, not the requested
  count. A repeated identical transaction returns the original receipt
- Uncertain movement or crash after durable intent and before durable receipt:
  retain the intent/hold and require reconciliation. Never automatically execute
  the physical transfer again. This includes a crash apparently before movement
- Lost reply after a durable receipt: replay the same receipt without repricing,
  moving items, or applying the account delta again
- Reconciliation: freeze affected transfers, inspect the specific classified
  bank/source/output counts and identity, confirm actual movement, then commit
  the receipt. If evidence cannot distinguish movement from outside changes,
  remain pending rather than infer an amount from a total scalar alone

A final receipt identifies the original transaction/account/item/policy, requested
and confirmed item counts, integer units per item, signed units delta, resulting
balance, and completed state. An uncertain response must not assert a completed
quantity or apply speculative credit. Changed content under the same transaction
ID is an error, even if its nominal credit value happens to match.

## Backing, liquidity and migration

Classified inventory valuation is `sum(count[entry] × unitsPerItem[entry])`.
Unconfigured or unverified items contribute no assumed backing. Compare validated
backing with account units + open maximum-return reservations + pending redemption
holds, using independent conservation checks.

Solvency and item availability are different. A bank can have enough aggregate
value and still have no diamonds to redeem. Every redemption must check the
specific permitted item inventory. No automatic substitution or conversion is
implied. Deposit-only stock may have assigned accounting value while offering no
immediate output route; the operator must approve that liability/liquidity policy.

Changing rates changes the value assigned to existing physical stock. Disabling
an item, reducing its value, or changing scale must not silently erase backing or
reprice already-issued credits. Safe implementation needs a versioned ledger,
explicit inventory classification, immutable policy history, and a reviewed
migration procedure. At minimum:

1. Pause, snapshot/backup both saved generations, and record physical counts and
   identities. Resolve outstanding physical transfers before migration
2. Record all balances, open rounds, maximum liabilities and original receipts.
   Preserve old idempotent receipts and their original units
3. Select real rates, redemption flags, scale and admitted identities with the
   operator. Verify the resulting bank valuation still covers all liabilities
4. Explicitly map old diamond units, accounts and reservations to the new unit
   scale without rounding; leave every active round with a coherent maximum
5. Keep old clients from interpreting item quantities as credit units. Require an
   explicit protocol/version compatibility gate and coordinated deployment
6. Validate restored migrated state and item stock before resuming. A fallback to
   an older generation must not downgrade into a different currency interpretation

## Executable acceptance scope

`require('tests.contracts.currency_policy').test(check, eq)` runs independent
policy validation, exact identity matching, quote arithmetic, weighted inventory
valuation, and golden event traces for partial/zero moves, duplicate receipts,
crashes, immutable revisions and operator reconciliation. Negative mutations
attempt early credit, double movement, double credit, changed recipients/rates,
wrong items, incorrect reconciliation and unreleased redemption holds.

These observations are test-owned input to a design oracle. They do not invoke
real `derby.service`, implement physical movement, or prove an adapter is safe.
A future implementation must replay this corpus through actual production APIs,
then pass the real-world gates in `README.md` with each enabled registry/NBT rule.
