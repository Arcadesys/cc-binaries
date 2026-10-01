# Safe branch mining checkpoint

## Contract

Implement the software portion of the 2026-10-01 branch-mining readiness plan. Completion requires current geometry, block-protection, fuel, inventory, recovery, packaging, and rendered-accessibility evidence. Minecraft survival acceptance and multi-turtle operation remain separate gates.

The user subsequently authorized a self-organizing mining orchestration layer and verification using the turtle-tester. That extension is now in progress.

## Route

User explicitly requested Sol workers. Three workers use `gpt-6.1-sol`, medium effort: safety/geometry; lifecycle/persistence; tests/documentation. Coordinator handles integration, packaging, rendered review, and delivery. No switch of the coordinating chat's model is claimed. Provider usage/cost counters are unavailable.

## Source and isolation

- Repository: `Arcadesys/cc-binaries`.
- Base: `7ec462d5ffe3ecfe9769d21e998f4568f8383e55`.
- Branch: `codex/safe-branch-mining`.
- Changes are in a separate Git worktree.
- Existing local checkout and unrelated changes are preserved.

## Current state

Software gates A and B are implemented: a dedicated bounded branch-mining lifecycle, explicit block policy, recorded safe return paths, checked fuel and inventory service, durable recovery, keyboard setup and paged status. Existing builder and farmer behavior stays outside the new lifecycle.

The verified single-turtle foundation is committed as `9ecb597`. The same three Sol workers now own durable fleet coordination, worker/client permits, and multi-turtle testing. The fleet design uses one persistent coordinator, finite preapproved jobs, exclusive occupied-area reservations, compatible verified home bays, and quarantine after lost/expired assignments. It does not infer safe travel across unknown terrain or automatically reassign an occupied region.

Fleet integration now passes all 28 native shared-world cases, including two real mining engines, north/south successor jobs, per-action lease expiry, network correlation, persistence failures, and restart quarantine. Review corrected the runtime protocol, lease-clock handling, and small-terminal status details. All 53 current bundled modules passed both installer readbacks. Eighteen native fleet screen pages passed; six representative PNGs were visually inspected.

The final single-turtle regression rerun is being split into four disjoint parts after whole-suite emulator runs hit the 240-second limit without assertion failures. The harness now binds each simulated turtle to its actual module environment and yields regularly; assertions and production code remain unchanged.

## Foundation evidence (before fleet extension)

- Native CraftOS full suite: 83 passed, zero failures; one additional factory Return Home dispatch case passed separately (84 unique cases verified). Exact results are retained in `tests/validation-results.txt`.
- Existing ArcadeOS regression suite: all 53 passed.
- `tools/verify_distribution.py`: all 47 bundled modules match source and the turtle manifest; both standalone and ArcadeOS turtle-package installers passed native extraction/readback.
- Native status/setup renderer: 16 pages at 39×13, 39×19 and 51×19; selected images are saved under `docs/evidence`. Coordinator inspected small-terminal prompts, preflight, complete error details, and final-state controls.
- Source whitespace and test Python syntax checks passed. Rebuilding also synchronized four previously stale bundled libraries with their unchanged source.

## Remaining gates and next step

Finish fleet integration, run actual mining workers in a shared simulated world with independent state/network failures, and refresh installer/readback and rendered evidence. Then review the implementation and run gate C from `SAFE_MINING.md` once a mining turtle and prepared area are available. Gate D requires separately proven non-overlapping turtle jobs, storage/fuel capacity, and chunk loading. Interrupted action intent deliberately requires manual reconciliation; it is not an automatic-recovery claim. Pack-specific unknown blocks stop until explicitly supported and tested.

No Minecraft world actions are part of these checks. A successful simulator run does not establish physical in-game safety, chunk-loading behavior, or pack-specific recipes.
