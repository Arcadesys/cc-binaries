-- Pine Links shot contract over the furball golf kernel (lib/golf.lua).
-- A shot runs on a copy of the hole state in bounded batches of fixed ticks; the
-- controller commits the copy's end state once. Skipping playback never changes it.
local golf = require("lib.golf")
local physics = {}

physics.step = golf.STEP
physics.maxBatch = 240
physics.sampleTicks = 6 -- 20 Hz playback samples

physics.clubs = {}
for i, id in ipairs(golf.CLUB_ORDER) do physics.clubs[i] = golf.CLUBS[id] end

local function sample(state)
  local b = state.ball
  return {x = b.x, y = b.y, z = b.z, t = state.ticks * golf.STEP}
end

-- shot: {club, aim (degrees), power (0.5..100)}. Returns a simulation, or nil/error.
function physics.begin(state, shot)
  if type(state) ~= "table" or state.phase ~= "ready" then return nil, "ball is not ready" end
  local copy = golf.copy(state)
  if not golf.strike(copy, shot) then return nil, "invalid shot" end
  local sim = {before = state, state = copy, shot = shot, trajectory = {}, done = false}
  sim.trajectory[1] = {x = state.ball.x, y = state.ball.y, z = state.ball.z, t = 0}
  return sim
end

function physics.advance(sim, stepBudget)
  if sim.done then return true end
  local s = sim.state
  for _ = 1, math.max(1, math.min(physics.maxBatch, stepBudget or physics.maxBatch)) do
    golf.step(s)
    if s.phase ~= "moving" or s.ticks % physics.sampleTicks == 0 then sim.trajectory[#sim.trajectory + 1] = sample(s) end
    if s.phase ~= "moving" then
      local outcome = s.phase == "finished" and "holed" or s.penalties > sim.before.penalties and "ob" or "rest"
      sim.result = {outcome = outcome, state = s, position = {x = s.ball.x, y = 0, z = s.ball.z},
        surface = s.lie, carry = s.lastCarry, duration = s.ticks * golf.STEP, message = s.message}
      sim.done = true
      return true
    end
  end
  return false
end

function physics.simulate(state, shot)
  local sim, err = physics.begin(state, shot)
  if not sim then return nil, err end
  while not physics.advance(sim) do end
  return sim.result, sim.trajectory
end

return physics
