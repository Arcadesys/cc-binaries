-- Parity with furball-simulator: fixtures are generated from src/sports/golf/{course,golf-core}.ts
-- and must be reproduced exactly by lib/course + lib/golf.
local course = require("lib.course")
local golf = require("lib.golf")

local root = shell and shell.dir() or ""
local h = assert(fs.open(fs.combine(root, "tests/fixtures/furball_golf.json"), "r"))
local fixtures = textutils.unserializeJSON(h.readAll()); h.close()

local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) * math.max(1, math.abs(a), math.abs(b)) end

for i, case in ipairs(fixtures.lies) do
  assert(course.lieAt(case.x, case.z) == case.lie, "lie " .. i)
end

local shots = 0
for round, states in ipairs(fixtures.golf) do
  local s = golf.newHole()
  for n, expected in ipairs(states) do
    local ok = golf.strike(s, expected.shot)
    assert(ok == expected.ok, ("round %d shot %d strike accepted"):format(round, n))
    local ticks, path = 0, {}
    while s.phase == "moving" do
      golf.step(s); ticks = ticks + 1
      if ticks % 60 == 0 then path[#path + 1] = {s.ball.x, s.ball.y, s.ball.z} end
    end
    local where = ("round %d shot %d"):format(round, n)
    assert(s.phase == expected.phase, where .. " phase " .. s.phase .. " vs " .. expected.phase)
    assert(s.lie == expected.lie and s.strokes == expected.strokes and s.penalties == expected.penalties
      and s.ticks == expected.ticks, where .. " lie/strokes/penalties/ticks")
    assert(near(s.ball.x, expected.ball.x, 1e-7) and near(s.ball.z, expected.ball.z, 1e-7)
      and near(s.lastCarry, expected.lastCarry, 1e-7), where .. " ball rest")
    assert(s.message == expected.message, where .. " message '" .. s.message .. "' vs '" .. expected.message .. "'")
    assert(#path == #expected.path, where .. " path length")
    for k, p in ipairs(expected.path) do
      assert(near(path[k][1], p[1], 1e-7) and near(path[k][2], p[2], 1e-7) and near(path[k][3], p[3], 1e-7), where .. " path " .. k)
    end
    shots = shots + 1
  end
end
print(("furball parity: %d lies, %d golf shots"):format(#fixtures.lies, shots))
return true
