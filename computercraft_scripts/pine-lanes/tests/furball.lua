-- Parity with furball-simulator: fixtures are generated from the TypeScript kernels
-- (src/sim/rng.ts, src/sports/bowling/sim/*) and must be reproduced by lib/rng + lib/pindeck.
local rng = require("lib.rng")
local deck = require("lib.pindeck")

local root = shell and shell.dir() or ""
local h = assert(fs.open(fs.combine(root, "tests/fixtures/furball_bowling.json"), "r"))
local fixtures = textutils.unserializeJSON(h.readAll()); h.close()

local function near(a, b, tol)
  if a == nil or b == nil then return a == b end
  return math.abs(a - b) <= (tol or 1e-9) * math.max(1, math.abs(a), math.abs(b))
end
local function list(t) local o = {}; for i, v in ipairs(t or {}) do o[i] = tostring(v) end; return table.concat(o, ",") end

for _, case in ipairs(fixtures.rng) do
  local next = rng.create(case.seed)
  for i, value in ipairs(case.values) do
    assert(next() == value, ("rng seed %d draw %d"):format(case.seed, i))
  end
end

for _, case in ipairs(fixtures.previews) do
  local tr = assert(deck.preview(case.controls))
  assert(near(tr.maxProgress, case.maxProgress), "preview maxProgress")
  assert(near(tr.gutterProgress, case.gutterProgress), "preview gutterProgress")
  assert(tr.gutterSide == case.gutterSide, "preview gutterSide")
end

local failures = {}
for index, case in ipairs(fixtures.bowling) do
  local result = assert(deck.resolveShot(case.input))
  local function fail(what) failures[#failures + 1] = ("shot %d %s"):format(index, what) end
  if result.kind ~= case.kind then fail("kind " .. result.kind .. "~=" .. case.kind) end
  if list(result.knockedDown) ~= list(case.knockedDown) then fail("knocked " .. list(result.knockedDown) .. " vs " .. list(case.knockedDown)) end
  if not near(result.durationMs, case.durationMs) then fail("duration " .. result.durationMs .. " vs " .. case.durationMs) end
  if #result.events ~= case.eventCount then fail("events " .. #result.events .. " vs " .. case.eventCount) end
  if list(result.contactPinIds) ~= list(case.contactPinIds) then fail("contacts") end
  if result.firstContactRow ~= case.firstContactRow then fail("first row") end
  for i, p in ipairs({0, 0.2, 0.5, 0.8, 1}) do
    if not near(deck.trajectoryX(result.trajectory, p), case.samples[i], 1e-12) then fail("path sample " .. i) end
  end
  for i, e in ipairs(case.events) do
    local got = result.events[i]
    if not got or got.pinId ~= e.pinId or got.source ~= e.source or got.toppled ~= e.toppled
      or not near(got.timeMs, e.timeMs) or not near(got.impulse, e.impulse, 1e-9) then fail("event " .. i); break end
  end
  local final = deck.poses({bodies = select(2, deck.resolveShot(case.input)).bodies}, result.durationMs)
  for i, p in ipairs(case.finalPins) do
    local got = final[i]
    if got.pinId ~= p.pinId or got.toppled ~= p.toppled or not near(got.x, p.x, 1e-7) or not near(got.z, p.z, 1e-7)
      or not near(got.fallAmount, p.fall, 1e-7) then fail("final pin " .. p.pinId); break end
  end
end
assert(#failures == 0, #failures .. " bowling parity failures:\n" .. table.concat(failures, "\n"))
print(("furball parity: %d rng seeds, %d previews, %d shots"):format(#fixtures.rng, #fixtures.previews, #fixtures.bowling))
return true
