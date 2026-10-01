# Bounded mining fleet

A trusted coordinator assigns a finite catalog of approved jobs to mining turtles. Workers claim compatible work, renew leases, run the actual safe-mining engine, report checked completion, and claim another eligible job or show **WAIT**. Jobs share no excavation cells. A worker can reuse its own known home bay for an approved job facing another heading; it cannot travel to an unknown bay.

These software checks do not establish Minecraft survival or multi-turtle readiness. Complete the supervised gates in [SAFE_MINING.md](SAFE_MINING.md) before scaling.

## Concrete configuration examples

The examples are **serialized data tables**, read with `textutils.unserialize`; they are not Lua programs:

- [Coordinator catalog](examples/fleet-coordinator.config): coordinator ID illustrated as **1**, workers **11** and **12**, fleet `pilot-fleet`.
- [Worker 11](examples/fleet-worker-11.config): home `0,64,0`, initially north; jobs `left` north and then `south` south.
- [Worker 12](examples/fleet-worker-12.config): home `30,64,0`, north; job `right`.

Each example job is a tiny spine 6 / branch interval 3 / branch length 2 / torch interval 3 mine. Output is **below** each turtle, supply **above** it. The examples include explicit world bounds, complete job footprints and registered bay bounds. The tests parse these exact files and validate coordinator/worker catalog compatibility.

Replace the illustrated IDs, coordinates, dimension, modem side and bounds with the actual prepared setup **consistently in all three files**. The examples do not choose a mining Y-level for your pack. Obtain the actual computer/turtle IDs and confirm the real physical home and heading before use. Worker `workerId` must match `os.getComputerID()`; worker `coordinatorId` must identify the chosen coordinator. Keep a world backup, supplies, free output capacity, loaded routes and a rescue path.

The coordinator derives exact excavation, neighbour and lighting cells from the approved mining plan. Those work cells cannot overlap another job or another registered bay/storage. Completed work cells remain retired. Only the same worker can reuse its known home and storage cells. Broad bounding boxes may overlap for north/south jobs at one home; exact work cells decide that compatibility. Up/down storage supports heading changes; storage in a planned corridor is rejected.

## Stage and start

Build and transfer the reviewed installer as described in [SAFE_MINING.md](SAFE_MINING.md). Both the standalone package and ArcadeOS turtle package include the fleet programs. Transfer the appropriate example data separately; installer execution does not invent a local fleet configuration.

On the selected coordinator, save the edited coordinator data as `fleet-coordinator.config`. Attach/open an available modem through the program, then run:

```text
fleet_coordinator fleet-coordinator.config
```

On each turtle, save its matching edited worker data as `fleet-worker.config`. Supply the configured modem, mining tool, fuel, torches and permitted fill blocks. Then run:

```text
fleet_worker fleet-worker.config
```

The worker shows its configured home, saved home pose, dimension, fleet and coordinator before accepting **ENTER**. Verify the turtle physically matches the **saved** pose and dimension; a saved record alone does not establish that it is home. No worker mining action occurs before this local confirmation.

Worker controls: **ENTER** confirms preflight and starts; **UP/DOWN** or **PAGE UP/PAGE DOWN** show complete details; **Q** stops an active worker in place and reports it to the coordinator. On **NEEDS_HELP** or **STOPPED**, **Q** closes the screen. A stopped assignment remains reserved for reconciliation. There is no automatic travel to a different bay.

Coordinator controls: **LEFT/RIGHT** or **PAGE UP/PAGE DOWN** show details; **Q** stops the coordinator. Workers cannot instantly know it has stopped. They stop before the next mutation after learning that authorization changed, or when their previously acknowledged local lease expires. Reservations remain durable throughout that window and are not reassigned.

The native terminal UI uses white text on black, explicit labels and keyboard pages. Inspect the [39×13 worker preflight](docs/evidence/fleet-worker-preflight-39x13-page1.png), [remaining preflight checks](docs/evidence/fleet-worker-preflight-39x13-page2.png) and [complete help reason](docs/evidence/fleet-worker-needs-help-39x13-page2.png). The actual Minecraft display still needs a readable font size and physical accessibility check.

## Ownership and restart behavior

Native leases use the monotonic `os.clock()` clock; wall-clock time only seeds increasing request IDs. Regressed lease clocks or stale request IDs stop the worker and require reconciliation. A backwards wall clock is not permission to clear coordinator records.

The shared protocol is `cc-safe-mining-fleet-v1`. One trusted coordinator is supported. Registered numeric sender IDs, matching fleet/session/request IDs and local job catalogs reject mismatched, stale and unsolicited messages. **Rednet sender identity is not cryptographic authentication.** Use the protocol inside the trusted setup; this change adds no cryptographic security layer or multi-coordinator consensus.

Every native movement, turn, dig, placement and inventory mutation in the mining transaction checks current worker authorization. A lease expiring halfway through a multi-action instruction blocks the next mutation. Duplicate replies advertise only their remaining original lease time. A lost grant does not free its area for another turtle.

The coordinator persists assignment, generation, token, request deduplication and job retirement. Restarting it advances its epoch and quarantines occupied assignments. Expired, stopped or failed areas remain reserved; expiry is not evidence that a turtle has left. Full storage, low fuel and unknown blocks produce stop reports rather than successful completion.

Workers retain the safe-mining journal and a separate home-orientation journal. Turning at the known home uses write-ahead intent. A crash during that turn or another ambiguous physical action refuses automatic recovery. Do not delete `.checkpoint`, `.position` or `.next` files to make an error disappear. Preserve records and reconcile the physical turtle, inventory and world before an operator decides how to retire or repair the assignment. There is no automatic quarantine-release command.

Catalogs are finite and configured locally. The coordinator does not discover unexplored areas, pick pack-specific ores, add new jobs, or create remote bays. Changing a catalog requires an explicit maintenance decision and reconciliation with the durable reservations.

## Reproduce software checks

From the repository root, with CraftOS-PC installed:

```sh
for part in 1 2 3 4; do
  python3 cc-factory/tests/run.py --part "$part/4" || exit 1
done
python3 cc-factory/tests/run.py --fleet
python3 cc-factory/tests/run.py --fleet-screens
python3 cc-factory/tools/verify_distribution.py
```

The 84 single-turtle cases run in four disjoint ordinal parts, with 21 cases per part. This keeps each native emulator invocation within its 240-second harness budget; a whole-suite timeout is a harness limit, not evidence of product safety or failure.

Set `CRAFTOS_BIN` if its executable is outside the default macOS application path. Every run uses an isolated emulator directory and prints its evidence directory. Failed assertions, missing reports, crashes and bounded emulator timeouts exit nonzero. These commands do not open Minecraft or connect to a live server.

The fleet tests load actual coordinator, worker, adapter and safe-mining modules. Two workers have independent globals, module caches, sixteen-slot inventories and persisted disks while sharing a physical block map, fake network and clock. A test-owned action oracle checks owner, lease deadline, region and collision independently of the worker's progress flags. The tests cover north→south successor mining beside a second worker, protocol faults, lease loss during a scan and home turn, restarts, quarantine, receiver/fuel/block failures, serialized examples and actual native adapter protocol agreement.

Current native fleet integration: **28 passed, zero failures**, with exit status 0. Native rendering produced **18 checked screen pages** across the three display sizes. [Retained output](tests/fleet-validation-results.txt) records the commands and results; the coordinator also inspected the rendered images and verified both installers against all 53 packaged source modules.

The simulation does not reproduce pack recipes, fluid flow, falling-block timing, chunk unloading, modem range, real-world latency, physical turtle motion or the user's actual screen. Supervised in-world gates C and D remain unverified.
