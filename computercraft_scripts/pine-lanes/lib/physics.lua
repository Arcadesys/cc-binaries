-- Pine Lanes physics contract over the furball bowling kernel (lib/pindeck.lua).
-- The kernel decides every pin; this module only batches its fixed steps and records
-- 30 Hz playback snapshots in Pine lane coordinates. Independent of CC/render.
local deck = require("lib.pindeck")
local lane = require("lib.lane")
local physics = {
  step = deck.STEP_MS / 1000,
  snapshotInterval = 1 / 30,
  maxBatch = 120,
}
local SNAPSHOT_STEPS = 4 -- 120 Hz kernel steps per 30 Hz snapshot
local PI = math.pi
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

-- Upright pins never move in the furball deck, so a standing rack is just its pin ids.
local function standingIds(rack)
  if type(rack) ~= "table" or #rack > 10 then return nil, "rack must be an array of at most ten pins" end
  local ids, seen = {}, {}
  for _, p in ipairs(rack) do
    if type(p) ~= "table" or not finite(p.id) or p.id % 1 ~= 0 or not deck.pinById[p.id] then return nil, "invalid pin id" end
    if seen[p.id] then return nil, "duplicate pin id" end
    seen[p.id] = true; ids[#ids + 1] = p.id
  end
  table.sort(ids)
  return ids
end

-- Furball poses carry the capsule centre; Pine draws a pin from its foot along its fall direction.
local function pinePose(p)
  local tilt = p.fallAmount * PI / 2
  local dirX, dirZ = -p.fallDirectionZ, p.fallDirectionX
  local X, Z = lane.toPine(p.x, p.z)
  local reach = lane.pinHeight / 2 * math.sin(tilt)
  return {id = p.pinId, x = X - dirX * reach, z = Z - dirZ * reach, angle = atan2(dirZ, dirX), tilt = tilt, down = p.toppled}
end

local function ballSnapshot(tr, timeMs)
  local b = deck.ballPosition(tr, timeMs)
  local X, Z = lane.toPine(b.x, b.z)
  local y = lane.ballRadius
  if b.gutter then y = y - 0.35 end
  if b.progress >= 1 then y = y - 0.8 end -- dropped into the pit behind the deck
  return {x = X, y = y, z = Z, gutter = b.gutter and (b.x < 0 and "left" or "right") or false}
end

local function snapshot(sim)
  local pins = {}
  for i, p in ipairs(deck.poses(sim.kernel, sim.kernel.timeMs or 0)) do pins[i] = pinePose(p) end
  local timeMs = sim.kernel.timeMs or 0
  return {t = timeMs / 1000, ball = ballSnapshot(sim.kernel.trajectory, timeMs), pins = pins}
end

local function fail(sim, message)
  sim.done = true
  sim.result = {deliveryId = sim.shot.deliveryId, status = "error", knocked = {}, standing = {}, duration = (sim.kernel and sim.kernel.timeMs or 0) / 1000, error = message}
end

-- shot: {deliveryId, position, aim, power, hook, seed} in furball control units
-- (position/aim/hook -100..100, power 0..100). Aim is furball's launch angle, hook its spin.
function physics.begin(rack, shot)
  if type(shot) ~= "table" or not finite(shot.seed) then return nil, "shot needs a finite seed" end
  local standing, err = standingIds(rack)
  if not standing then return nil, err end
  local kernel, kerr = deck.beginShot({position = shot.position, angle = shot.aim, spin = shot.hook,
    power = shot.power, seed = shot.seed, standing = standing})
  if not kernel then return nil, kerr end
  local sim = {shot = shot, kernel = kernel, standing = standing, trajectory = {}, done = false, steps = 0}
  sim.trajectory[1] = snapshot(sim)
  return sim
end

function physics.advance(sim, stepBudget)
  if sim.done then return true end
  for _ = 1, math.max(1, math.min(physics.maxBatch, stepBudget or physics.maxBatch)) do
    local ok, finished = pcall(deck.stepPinAction, sim.kernel)
    if not ok then fail(sim, tostring(finished)); return true end
    sim.steps = sim.steps + 1
    if finished or sim.steps % SNAPSHOT_STEPS == 0 then sim.trajectory[#sim.trajectory + 1] = snapshot(sim) end
    if finished then
      local outcome = deck.finishShot(sim.kernel)
      local fresh, standingPoses = lane.newRack(), {}
      for _, id in ipairs(outcome.remaining) do standingPoses[#standingPoses + 1] = fresh[id] end
      local knocked = {}
      for i, id in ipairs(outcome.knockedDown) do knocked[i] = id end
      sim.outcome = outcome
      sim.result = {deliveryId = sim.shot.deliveryId, status = "ok", kind = outcome.kind, knocked = knocked,
        standing = standingPoses, duration = outcome.durationMs / 1000}
      sim.done = true
      return true
    end
  end
  return false
end

-- Synchronous test/calibration helper.
function physics.simulate(rack, shot)
  local sim, err = physics.begin(rack, shot)
  if not sim then return {deliveryId = shot and shot.deliveryId, status = "error", knocked = {}, standing = {}, duration = 0, error = err}, {} end
  while not physics.advance(sim, physics.maxBatch) do end
  return sim.result, sim.trajectory
end

-- Lane-space Z of the ball at release for an approach position.
function physics.releaseZ(position) return deck.releaseX(math.max(-100, math.min(100, position or 0))) end

-- Aim preview for the renderer: lane-space points along the shot path, with no random draw.
function physics.preview(settings, count)
  local tr = deck.preview({position = settings.position, angle = settings.aim, spin = settings.hook, power = settings.power})
  if not tr then return {} end
  local points = {}
  count = count or 12
  for i = 0, count do
    local p = tr.maxProgress * i / count
    local X, Z = lane.toPine(deck.trajectoryX(tr, p), deck.RELEASE_Z + (deck.END_Z - deck.RELEASE_Z) * p)
    points[#points + 1] = {x = X, z = Z, gutter = tr.gutterProgress ~= nil and p >= tr.gutterProgress}
    if X >= lane.headX then break end
  end
  return points
end

return physics
