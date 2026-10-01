-- Parity with furball-simulator: fixtures are generated from src/sim/*.ts and must be
-- reproduced exactly by lib/rng + lib/baseball.
local rng = require("lib.rng")
local bb = require("lib.baseball")

local root = shell and shell.dir() or ""
local h = assert(fs.open(fs.combine(root, "tests/fixtures/furball_baseball.json"), "r"))
local fx = textutils.unserializeJSON(h.readAll()); h.close()

local function list(t) local o = {}; for i, v in ipairs(t or {}) do o[i] = tostring(v) end; return table.concat(o, ",") end

for _, case in ipairs(fx.rng) do
  local next = rng.create(case.seed)
  for i, v in ipairs(case.values) do assert(next() == v, "rng " .. case.seed .. ":" .. i) end
end
local wg = rng.create(9)
for i, key in ipairs(fx.weightedCases) do
  assert(rng.weighted(wg, {{"a", 1}, {"b", 2.5}, {"c", 0}, {"d", 4}}) == key, "weighted " .. i)
end

local cg = rng.create(31337)
for i, p in ipairs(fx.cpuPitches) do
  local got = bb.cpuPitch(cg)
  assert(got.type == p.type and got.location.x == p.location.x and got.location.y == p.location.y, "cpu pitch " .. i)
end

for i, c in ipairs(fx.pitchCases) do
  local swing = {timingOffsetMs = c.offset, aim = c.aim, bats = c.bats}
  local event = bb.resolvePitch(c.pitch, swing, rng.create(c.seed))
  assert(event.kind == c.event.kind and event.result == c.event.result,
    ("pitch case %d: %s %s vs %s %s"):format(i, event.kind, tostring(event.result), c.event.kind, tostring(c.event.result)))
  if c.offset ~= nil then assert(bb.contactTier(c.pitch.location, c.offset) == c.tier, "tier " .. i) end
end

local queue = {light = {"l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9"}, dark = {"d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9"}}
local steps = 0
for _, game in ipairs(fx.games) do
  local state = bb.createGame(queue)
  for i, step in ipairs(game.steps) do
    local t = bb.applyPitchEvent(state, step.event)
    local s, e = t.state, step.state
    local where = ("game %d step %d"):format(game.seed, i)
    assert(list(t.callouts) == list(step.callouts), where .. " callouts " .. list(t.callouts) .. " vs " .. list(step.callouts))
    assert(list(t.scored) == list(step.scored) and t.plateAppearanceOver == step.pae, where .. " scored/pae")
    assert(s.inning == e.inning and s.half == e.half and s.outs == e.outs and s.balls == e.balls and s.strikes == e.strikes
      and s.status == e.status, where .. " count")
    assert(s.score.light == e.score.light and s.score.dark == e.score.dark, where .. " score")
    assert(s.bases.first == e.bases.first and s.bases.second == e.bases.second and s.bases.third == e.bases.third, where .. " bases")
    assert(s.batterIndex.light == e.batterIndex.light and s.batterIndex.dark == e.batterIndex.dark, where .. " batter index")
    state = s; steps = steps + 1
  end
end

for i, c in ipairs(fx.catches) do
  local plan = bb.planCatch(c.distance, 1800, bb.DEFAULT_FIELDING, c.roll)
  assert(plan.outcome == c.plan.outcome and plan.arrivalMs == c.plan.arrivalMs, "catch " .. i)
end
local fieldNext = rng.create(bit32.bxor(123, 0x9e3779b9))
assert(fieldNext() == fx.fieldingRng.unsigned[1] and fieldNext() == fx.fieldingRng.unsigned[2], "fielding seed salt")

print(("furball parity: %d pitches, %d cpu pitches, %d reducer steps, %d catch plans"):format(#fx.pitchCases, #fx.cpuPitches, steps, #fx.catches))
return true
