#!/usr/bin/env python3
"""Generate schema_colosseum.txt: an elliptical sandstone arena for the factory builder.

    python3 cc-factory/tools/colosseum.py           # write the schema
    python3 cc-factory/tools/colosseum.py --plan    # also print a top-down map

The footprint is a set of concentric elliptical rings around the arena floor
(ring 0). Rings 1-2 are the arena wall, rings 3-6 hold the walkway and the two
grandstands, rings 7-8 are the outer wall. The script checks its own output:
20 seats, cacti with free sides, and every trap inside the arena.
"""

import math
import os
import sys

# Arena floor semi-axes; each further ring adds one block to both.
ARENA_A, ARENA_B = 16, 10
RINGS = 8  # outermost ring index -> footprint 49 x 37

BASE_TOP = 1     # layers 0-1: cobblestone podium (gives the spike pits depth)
FLOOR = 2        # arena floor and walkway surface
ARENA_WALL_TOP = 6   # fighters stand at 3, wall top surface at 7: no climbing out
STAND_TOP = {3: 6, 4: 7, 5: 8, 6: 8}   # front row, back row, aisle, aisle
OUTER_WALL_TOP = 10
CRENEL = 11
STAND_HALF_WIDTH = 6  # stands cover |x| <= 6, then ramp down one block per block
SEAT_X = (-4, -2, 0, 2, 4)  # five seats per row, two rows per stand, two stands

LEGEND = [
    ("f", "minecraft:cobblestone", "podium"),
    ("#", "minecraft:sandstone", "walls"),
    ("C", "minecraft:chiseled_sandstone", "crenellations and gate lintels"),
    ("S", "minecraft:smooth_sandstone", "walkway and grandstands"),
    ("n", "minecraft:spruce_slab", "spectator seats (20)"),
    ("L", "minecraft:lantern", "wall lights"),
    ("d", "minecraft:coarse_dirt", "arena floor"),
    ("a", "minecraft:sand", "desert floor"),
    ("c", "minecraft:cactus", "cactus"),
    ("w", "minecraft:cobweb", "cobweb"),
    ("i", "minecraft:packed_ice", "ice rink (packed ice does not melt by lava)"),
    ("l", "minecraft:lava_bucket", "lava (one bucket per block)"),
    ("m", "minecraft:magma_block", "magma"),
    ("r", "minecraft:soul_sand", "soul sand"),
    ("x", "minecraft:campfire", "campfire"),
    ("b", "minecraft:sweet_berries", "sweet berry bush"),
    ("p", "minecraft:pointed_dripstone", "spikes at the bottom of the pits"),
    (".", "minecraft:air", "air"),
]

W = 2 * (ARENA_A + RINGS) + 1
D = 2 * (ARENA_B + RINGS) + 1
CX, CZ = ARENA_A + RINGS, ARENA_B + RINGS


def ring(x, z):
    """Smallest k with (x, z) inside the ellipse with semi-axes A+k, B+k (None if outside)."""
    for k in range(RINGS + 1):
        a, b = ARENA_A + k + 0.5, ARENA_B + k + 0.5
        if (x / a) ** 2 + (z / b) ** 2 <= 1:
            return k
    return None


def jitter(x, z):
    """Deterministic pseudo-random value in [0, 1) for scattering hazards."""
    h = (x * 73856093) ^ (z * 19349663)
    return ((h * 2654435761) & 0xFFFFFFFF) / 2 ** 32


grid = {}  # (x, y, z) -> symbol, centred coordinates


def put(x, y, z, sym):
    grid[(x, y, z)] = sym


def is_gate(x, z):
    return abs(z) <= 1 and abs(x) > ARENA_A - 4


def zone(x, z):
    if is_gate(x, z):
        return "gate"  # clear entry lanes
    if x <= -8:
        return "desert"
    if x >= 8:
        return "ice"
    return "middle"


cells = {(x, z): ring(x, z) for x in range(-CX, CX + 1) for z in range(-CZ, CZ + 1)}
cells = {p: k for p, k in cells.items() if k is not None}
arena = {p for p, k in cells.items() if k == 0}

# --- Podium and floor -------------------------------------------------------
for (x, z), k in cells.items():
    for y in range(BASE_TOP + 1):
        put(x, y, z, "f")
    if k == 0:
        put(x, FLOOR, z, {"desert": "a", "ice": "i"}.get(zone(x, z), "d"))
    else:
        put(x, FLOOR, z, "S")

# --- Arena wall (rings 1-2) with gates east and west ------------------------
for (x, z), k in cells.items():
    if k in (1, 2):
        for y in range(FLOOR + 1, ARENA_WALL_TOP + 1):
            if is_gate(x, z) and y <= FLOOR + 3:
                continue
            put(x, y, z, "C" if is_gate(x, z) and y == FLOOR + 4 else "#")
        if k == 1 and not is_gate(x, z) and abs(x) % 6 == 3 and abs(z) > 2:
            put(x, ARENA_WALL_TOP + 1, z, "L")

# --- Grandstands north and south, ramping down to the walkway ---------------
seats = []
for (x, z), k in cells.items():
    if k not in STAND_TOP or abs(z) < 4:
        continue
    top = STAND_TOP[k] - max(0, abs(x) - STAND_HALF_WIDTH)
    for y in range(FLOOR + 1, top + 1):
        put(x, y, z, "S")
for sz in (-1, 1):
    for k in (3, 4):
        for x in SEAT_X:
            z = next(z for z in range(sz, sz * (CZ + 1), sz) if cells.get((x, z)) == k)
            put(x, STAND_TOP[k] + 1, z, "n")
            seats.append((x, z))

# --- Outer wall (rings 7-8) -------------------------------------------------
for (x, z), k in cells.items():
    if k in (7, 8):
        for y in range(FLOOR + 1, OUTER_WALL_TOP + 1):
            if is_gate(x, z) and y <= FLOOR + 4:
                continue
            put(x, y, z, "C" if is_gate(x, z) and y == FLOOR + 5 else "#")
        if k == 8 and (x + z) % 2 == 0:
            put(x, CRENEL, z, "C")

# --- Arena traps --------------------------------------------------------------
traps = {}  # (x, z) -> (floor symbol or None, list of (y, symbol) above the floor)


def trap(x, z, floor=None, above=()):
    assert (x, z) in arena, f"trap at {(x, z)} is outside the arena"
    traps[(x, z)] = (floor, list(above))


# Middle: lava pool ringed by magma and soul sand.
for x in range(-3, 4):
    for z in range(-3, 4):
        r = max(abs(x), abs(z))
        trap(x, z, "l" if r <= 1 else "m" if r == 2 else "r")

# Middle: spike pits north and south (ring-out: two deep, no way to climb out).
for pz in (-7, 7):
    for x in range(-1, 2):
        for z in range(pz - 1, pz + 2):
            put(x, 1, z, ".")
            put(x, 0, z, "p")
            trap(x, z, ".")

# Middle: campfires and berry thickets around the pits.
for sx in (-1, 1):
    for sz in (-1, 1):
        trap(5 * sx, 4 * sz, None, [(FLOOR + 1, "x")])
        for x, z in ((3, 7), (4, 7), (4, 8), (3, 8), (5, 6)):
            trap(x * sx, z * sz, None, [(FLOOR + 1, "b")])

# Borders between zones: broken magma lines.
for z in range(-ARENA_B, ARENA_B + 1):
    for x in (-7, 7):
        if (x, z) in arena and not is_gate(x, z) and abs(z) % 3 != 0:
            trap(x, z, "m")

# East: ice rink with lava sinkholes.
for x, z in ((10, 4), (10, -4), (11, 4), (11, -4), (12, 6), (12, -6), (14, 3), (14, -3)):
    trap(x, z, "l")

# West: desert of cacti and cobwebs. Cacti need air on all four sides.
for (x, z) in sorted(arena):
    if zone(x, z) != "desert" or (x, z) in traps:
        continue
    if x % 2 or z % 2:
        continue
    if not all((x + dx, z + dz) in arena for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))):
        continue
    j = jitter(x, z)
    if j < 0.6:
        tall = [(FLOOR + 1, "c")] + ([(FLOOR + 2, "c")] if j < 0.3 else [])
        trap(x, z, None, tall)
for x, z in ((-11, 3), (-13, -3), (-9, -5), (-11, -7), (-13, 5)):
    near = [(x + dx, z + dz) for dx, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1))]
    if not any(p in traps for p in near):
        trap(x, z, None, [(FLOOR + 1, "w")])

for (x, z), (floor, above) in traps.items():
    if floor:
        put(x, FLOOR, z, floor)
    for y, sym in above:
        put(x, y, z, sym)

# --- Checks -------------------------------------------------------------------
assert W >= 40, W
assert len(seats) == 20 and len(set(seats)) == 20, seats
for (x, y, z), sym in grid.items():
    if sym == "c":
        assert grid.get((x, y - 1, z)) in ("a", "c"), (x, y, z)
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            assert grid.get((x + dx, y, z + dz), ".") == ".", ("cactus touches a block", x, y, z)
    if sym == "l":
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = grid.get((x + dx, FLOOR, z + dz))
            assert n not in (None, "."), ("lava would spill", x, z)

# --- Output -------------------------------------------------------------------
max_y = max(y for _, y, _ in grid)
known = {s for s, _, _ in LEGEND}
assert {s for s in grid.values()} <= known


def layer_rows(y):
    return [
        "".join(grid.get((x - CX, y, z - CZ), ".") for x in range(W))
        for z in range(D)
    ]


# The text-grid parser has no comment syntax, so the file starts at the legend.
out = ["legend:"]
for sym, name, _ in LEGEND:
    out.append("%s = %s" % (sym, name))
for y in range(max_y + 1):
    out.append("")
    out.append("layer:%d" % y)
    out.extend(layer_rows(y))

here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, "..", "schema_colosseum.txt")
with open(path, "w") as fh:
    fh.write("\n".join(out) + "\n")

counts = {}
for sym in grid.values():
    if sym != ".":
        counts[sym] = counts.get(sym, 0) + 1
print("wrote %s (%d x %d, %d layers)" % (os.path.relpath(path), W, D, max_y + 1))
for sym, name, note in LEGEND:
    if sym in counts:
        print("  %6d  %-30s %s" % (counts[sym], name, note))
print("  %6d  total blocks" % sum(counts.values()))

if "--plan" in sys.argv:
    # Top-down view: the highest block in each column.
    print()
    for z in range(D):
        row = ""
        for x in range(W):
            col = [grid.get((x - CX, y, z - CZ), ".") for y in range(max_y + 1)]
            top = next((s for s in reversed(col) if s != "."), " ")
            row += top
        print(row)
