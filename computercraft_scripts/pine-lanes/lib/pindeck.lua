-- Furball bowling kernel, ported line-for-line from furball-simulator
-- src/sports/bowling/sim/{shot,trajectory,pinAction}.ts. Scene units: X across the
-- lane (+ right), Z along it (release at +5.7, head pin at -5, pit at -9).
-- Pure Lua: no terminal, peripheral, renderer or wall-clock dependencies.
local rng = require("lib.rng")
local deck = {}

deck.PINS = {
  {id=1, x=0, row=0},
  {id=2, x=-0.55, row=1}, {id=3, x=0.55, row=1},
  {id=4, x=-1.1, row=2}, {id=5, x=0, row=2}, {id=6, x=1.1, row=2},
  {id=7, x=-1.65, row=3}, {id=8, x=-0.55, row=3},
  {id=9, x=0.55, row=3}, {id=10, x=1.65, row=3},
}
deck.STEP_MS = 1000 / 120
deck.BALL_TRAVEL_MS = 1650
deck.DECK_BOUNDS = {minX=-3.1, maxX=3.1, minZ=-9.7, maxZ=-4.2}
deck.PIN_RADIUS = 0.2
deck.FALLEN_PIN_HALF_LENGTH = 0.48
deck.BALL_RADIUS = 0.3055
deck.TOPPLE_IMPULSE = 0.65
deck.PIN_MAX_SPEED = 8
deck.MAX_MS = 5000
deck.POSITION_REACH = 1.9
deck.ANGLE_REACH = 4.8
deck.HOOK_REACH = 3.4
deck.HOOK_START = 0.35
deck.GUTTER_EDGE = 2.45
deck.GUTTER_CENTER = 3.32
deck.MIN_ROLL_POWER = 20
deck.RELEASE_Z = 5.7
deck.END_Z = -9
deck.HEAD_PIN_Z = -5
deck.PIN_ROW_DEPTH = 0.8

local STEP = deck.STEP_MS / 1000
local FALL_MS = 300
local STOP_SPEED = 0.045
local DRAG = 2.5
local PI = math.pi
local sin, cos, sqrt, abs, exp = math.sin, math.cos, math.sqrt, math.abs, math.exp
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local HUGE = math.huge

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function sign(v) if v > 0 then return 1 elseif v < 0 then return -1 end return 0 end
local function hypot(x, z) return sqrt(x * x + z * z) end
local function finite(n) return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE end
local function dot(a, b) return a.x * b.x + a.z * b.z end

local pinById = {}
for _, pin in ipairs(deck.PINS) do pinById[pin.id] = pin end
deck.pinById = pinById

-- Trajectory -----------------------------------------------------------------

local function validSigned(v) return finite(v) and abs(v) <= 100 end

function deck.validateControls(c)
  if type(c) ~= "table" or not validSigned(c.position) or not validSigned(c.angle) or not validSigned(c.spin)
    or not finite(c.power) or c.power < 0 or c.power > 100 then
    return nil, "Invalid bowling shot controls"
  end
  return true
end

function deck.releaseX(position) return position / 100 * deck.POSITION_REACH end

function deck.pinProgress(row)
  return (deck.RELEASE_Z - deck.HEAD_PIN_Z + row * deck.PIN_ROW_DEPTH) / (deck.RELEASE_Z - deck.END_Z)
end

local function freePathX(c, progress)
  local hook = math.max(0, progress - deck.HOOK_START) / (1 - deck.HOOK_START)
  return deck.releaseX(c.position) + c.angle / 100 * deck.ANGLE_REACH * progress
    + c.spin / 100 * deck.HOOK_REACH * hook * hook
end

-- Split the quadratic at its turning point so even a brief out-and-back is caught.
local function firstGutter(c, maxProgress)
  local cuts = {0, maxProgress}
  if deck.HOOK_START < maxProgress then cuts[#cuts + 1] = deck.HOOK_START end
  local hookCoefficient = c.spin / 100 * deck.HOOK_REACH / (1 - deck.HOOK_START) ^ 2
  if hookCoefficient ~= 0 then
    local turningPoint = deck.HOOK_START - c.angle / 100 * deck.ANGLE_REACH / (2 * hookCoefficient)
    if turningPoint > deck.HOOK_START and turningPoint < maxProgress then cuts[#cuts + 1] = turningPoint end
  end
  table.sort(cuts)
  for index = 2, #cuts do
    local low, high = cuts[index - 1], cuts[index]
    local endX = freePathX(c, high)
    if abs(endX) > deck.GUTTER_EDGE then
      local side = sign(endX)
      for _ = 1, 48 do
        local middle = (low + high) / 2
        if freePathX(c, middle) * side > deck.GUTTER_EDGE then high = middle else low = middle end
      end
      return {progress = (low + high) / 2, side = side}
    end
  end
  return nil
end

-- Safe aim preview: uses controls only, with no random draw or pin outcome.
function deck.preview(c)
  local ok, err = deck.validateControls(c)
  if not ok then return nil, err end
  local controls = {position = c.position, angle = c.angle, power = c.power, spin = c.spin}
  local maxProgress = c.power < deck.MIN_ROLL_POWER
    and deck.pinProgress(0) * 0.88 * c.power / deck.MIN_ROLL_POWER or 1
  local gutter = firstGutter(controls, maxProgress)
  return {controls = controls, releaseX = deck.releaseX(c.position), maxProgress = maxProgress,
    gutterProgress = gutter and gutter.progress or nil, gutterSide = gutter and gutter.side or 0}
end

-- The resolver and animation sample this same path. A gutter cannot hook back in.
function deck.trajectoryX(tr, progress)
  local t = math.max(0, math.min(tr.maxProgress, progress))
  if tr.gutterProgress ~= nil and t >= tr.gutterProgress then
    local settle = math.min(1, (t - tr.gutterProgress) / 0.12)
    return tr.gutterSide * (deck.GUTTER_EDGE + (deck.GUTTER_CENTER - deck.GUTTER_EDGE) * settle)
  end
  return freePathX(tr.controls, t)
end

-- Ball centre at a release-relative time, for playback (never nil while on the lane).
function deck.ballPosition(tr, timeMs)
  local progress = math.max(0, timeMs / deck.BALL_TRAVEL_MS)
  local p = math.min(progress, tr.maxProgress)
  return {x = deck.trajectoryX(tr, p), z = deck.RELEASE_Z + (deck.END_Z - deck.RELEASE_Z) * p,
    progress = p, gutter = tr.gutterProgress ~= nil and p >= tr.gutterProgress}
end

-- Pin action -----------------------------------------------------------------

local function axis(pin)
  local half = deck.FALLEN_PIN_HALF_LENGTH * sin(pin.fall * PI / 2)
  local x, z = sin(pin.heading) * half, cos(pin.heading) * half
  return {x = pin.x - x, z = pin.z - z}, {x = pin.x + x, z = pin.z + z}
end

local function closestPoint(point, a, b)
  local dx, dz = b.x - a.x, b.z - a.z
  local length = dx * dx + dz * dz
  local t = length ~= 0 and clamp(((point.x - a.x) * dx + (point.z - a.z) * dz) / length, 0, 1) or 0
  return {x = a.x + dx * t, z = a.z + dz * t}
end

-- In two dimensions, nonintersecting segments are closest at an endpoint.
local function closestAxes(first, second)
  local la, lb = axis(first)
  local ra, rb = axis(second)
  local candidates = {
    {a = la, b = closestPoint(la, ra, rb)},
    {a = lb, b = closestPoint(lb, ra, rb)},
    {a = closestPoint(ra, la, lb), b = ra},
    {a = closestPoint(rb, la, lb), b = rb},
  }
  local lx, lz = lb.x - la.x, lb.z - la.z
  local rx, rz = rb.x - ra.x, rb.z - ra.z
  local cross = lx * rz - lz * rx
  if abs(cross) > 1e-10 then
    local dx, dz = ra.x - la.x, ra.z - la.z
    local t, u = (dx * rz - dz * rx) / cross, (dx * lz - dz * lx) / cross
    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
      local point = {x = la.x + t * lx, z = la.z + t * lz}
      return point, point, 0
    end
  end
  local best, distance = candidates[1], HUGE
  for _, candidate in ipairs(candidates) do
    local d = hypot(candidate.b.x - candidate.a.x, candidate.b.z - candidate.a.z)
    if d < distance then best, distance = candidate, d end
  end
  return best.a, best.b, distance
end

local function limitSpeed(pin)
  local speed = hypot(pin.vx, pin.vz)
  if speed > deck.PIN_MAX_SPEED then
    pin.vx = pin.vx * deck.PIN_MAX_SPEED / speed
    pin.vz = pin.vz * deck.PIN_MAX_SPEED / speed
  end
  pin.turn = clamp(pin.turn, -8, 8)
  pin.roll = clamp(pin.roll, -12, 12)
end

local function boundPin(pin)
  local b = deck.DECK_BOUNDS
  local half = deck.FALLEN_PIN_HALF_LENGTH * sin(pin.fall * PI / 2)
  local reachX = deck.PIN_RADIUS + abs(sin(pin.heading)) * half
  local reachZ = deck.PIN_RADIUS + abs(cos(pin.heading)) * half
  local x = clamp(pin.x, b.minX + reachX, b.maxX - reachX)
  local z = clamp(pin.z, b.minZ + reachZ, b.maxZ - reachZ)
  if x ~= pin.x then pin.vx = (x > pin.x and 1 or -1) * abs(pin.vx) * 0.12; pin.x = x end
  if z ~= pin.z then pin.vz = (z > pin.z and 1 or -1) * abs(pin.vz) * 0.12; pin.z = z end
end

local function velocityAt(pin, point)
  local dx, dz = point.x - pin.x, point.z - pin.z
  local expansion = (pin.toppleTime ~= nil and pin.fall < 1)
    and deck.FALLEN_PIN_HALF_LENGTH * PI / 2 / (FALL_MS / 1000) * cos(pin.fall * PI / 2) or 0
  local side = sign(dx * sin(pin.heading) + dz * cos(pin.heading))
  return {x = pin.vx + dz * pin.turn + side * sin(pin.heading) * expansion,
    z = pin.vz - dx * pin.turn + side * cos(pin.heading) * expansion}
end

local function poses(sim, timeMs)
  local out = {}
  for i, pin in ipairs(sim.bodies) do
    local fallAmount
    if pin.toppleTime == nil then
      fallAmount = (pin.wobble > 0 and timeMs - pin.wobbleTime < 250)
        and pin.wobble * math.max(0, 1 - (timeMs - pin.wobbleTime) / 250) * abs(sin((timeMs - pin.wobbleTime) / 40)) or 0
    else fallAmount = pin.fall end
    out[i] = {pinId = pin.id, x = pin.x, z = pin.z, fallAmount = fallAmount, yaw = pin.yaw,
      fallDirectionX = sin(pin.heading), fallDirectionZ = cos(pin.heading), toppled = pin.toppleTime ~= nil}
  end
  return out
end
deck.poses = poses

local function impact(sim, target, source, sourcePinId, impulse, normal, point, timeMs)
  local toppled = target.toppleTime == nil and impulse >= deck.TOPPLE_IMPULSE
  if toppled then
    target.toppleTime = timeMs
    target.heading = atan2(normal.x, normal.z)
    target.roll = normal.x * 3.5
  elseif target.toppleTime == nil then
    target.wobbleTime = timeMs
    target.wobble = math.min(0.09, impulse * 0.12)
    target.heading = atan2(normal.x, normal.z)
  end
  sim.events[#sim.events + 1] = {timeMs = timeMs, pinId = target.id, source = source, sourcePinId = sourcePinId,
    impulse = impulse, toppled = toppled, x = point.x, z = point.z}
  return toppled
end

-- input: {standing={ids}, seed, power, ballAt=function(timeMs) -> {x,z} | nil}
function deck.newPinAction(input)
  if not finite(input.seed) or not finite(input.power) or input.power < 0 or input.power > 100 then
    return nil, "Invalid bowling pin action input"
  end
  local standing = {}
  for _, id in ipairs(input.standing) do
    if standing[id] or not pinById[id] then return nil, "Invalid bowling pin action input" end
    standing[id] = true
  end
  local next = rng.create(input.seed)
  local bodies = {}
  -- Draw properties for the full rack so removing a dead pin never changes another's material.
  for _, pin in ipairs(deck.PINS) do
    local body = {id = pin.id, x = pin.x, z = -5 - pin.row * 0.8, vx = 0, vz = 0,
      heading = PI, turn = 0, yaw = 0, roll = 0, fall = 0,
      toppleTime = nil, wobbleTime = -HUGE, wobble = 0, bounce = 0.28 + next() * 0.1}
    if standing[pin.id] then bodies[#bodies + 1] = body end
  end
  return {input = input, bodies = bodies, events = {}, touchedByBall = {}, touching = {},
    step = 0, maxStep = deck.MAX_MS / deck.STEP_MS, durationMs = deck.BALL_TRAVEL_MS, finished = false}
end

-- Advance one fixed step. Returns true once the deck has settled.
function deck.stepPinAction(sim)
  if sim.finished then return true end
  sim.step = sim.step + 1
  if sim.step > sim.maxStep then error("Bowling pin action did not settle within its bounded timeline", 0) end
  local timeMs = sim.step * deck.STEP_MS
  local bodies, input = sim.bodies, sim.input
  for _, pin in ipairs(bodies) do
    if pin.toppleTime ~= nil then
      pin.fall = clamp((timeMs - pin.toppleTime) / FALL_MS, 0, 1)
      local damping = exp(-DRAG * STEP)
      pin.vx = pin.vx * damping; pin.vz = pin.vz * damping; pin.turn = pin.turn * damping; pin.roll = pin.roll * damping
      pin.x = pin.x + pin.vx * STEP; pin.z = pin.z + pin.vz * STEP
      pin.heading = pin.heading + pin.turn * STEP; pin.yaw = pin.yaw + pin.roll * STEP
      boundPin(pin)
    end
  end
  local ball, previousBall = input.ballAt(timeMs), input.ballAt(timeMs - deck.STEP_MS)
  if ball and previousBall then
    local ballVelocity = {x = (ball.x - previousBall.x) / STEP, z = (ball.z - previousBall.z) / STEP}
    for _, pin in ipairs(bodies) do
      if not sim.touchedByBall[pin.id] then
        local a, b = axis(pin)
        local point = closestPoint(ball, a, b)
        local dx, dz = point.x - ball.x, point.z - ball.z
        local distance = hypot(dx, dz)
        if distance <= deck.BALL_RADIUS + deck.PIN_RADIUS then
          local normal = distance > 1e-8 and {x = dx / distance, z = dz / distance} or {x = 0, z = -1}
          local velocity = velocityAt(pin, point)
          local closing = math.max(0, dot({x = ballVelocity.x - velocity.x, z = ballVelocity.z - velocity.z}, normal))
          local impulse = closing * (1 + pin.bounce) * 0.8 * (0.2 + input.power / 100 * 0.8)
          if impulse > 0.001 then
            sim.touchedByBall[pin.id] = true
            impact(sim, pin, "ball", nil, impulse, normal, point, timeMs)
            if pin.toppleTime ~= nil then
              pin.vx = pin.vx + normal.x * impulse; pin.vz = pin.vz + normal.z * impulse
              pin.turn = pin.turn + (normal.x * ballVelocity.z - normal.z * ballVelocity.x) * 0.22
              limitSpeed(pin)
            end
          end
        end
      end
    end
  end
  local nextTouching = {}
  for left = 1, #bodies do for right = left + 1, #bodies do
    local a, b = bodies[left], bodies[right]
    -- Causal sources must have visibly started falling in a previous step.
    if (a.toppleTime ~= nil or b.toppleTime ~= nil) and a.toppleTime ~= timeMs and b.toppleTime ~= timeMs then
      local ca, cb, cdist = closestAxes(a, b)
      if cdist <= deck.PIN_RADIUS * 2 then
        local key = a.id .. ":" .. b.id
        nextTouching[key] = true
        local dx, dz = cb.x - ca.x, cb.z - ca.z
        local distance = hypot(dx, dz)
        if distance < 1e-8 then dx = b.x - a.x; dz = b.z - a.z; distance = hypot(dx, dz); if distance == 0 then distance = 1 end end
        local normal = {x = dx / distance, z = dz / distance}
        local va, vb = velocityAt(a, ca), velocityAt(b, cb)
        local closing = dot({x = va.x - vb.x, z = va.z - vb.z}, normal)
        local leverA = (ca.z - a.z) * normal.x - (ca.x - a.x) * normal.z
        local leverB = (cb.z - b.z) * normal.x - (cb.x - b.x) * normal.z
        -- Include rotational inertia so spinning bodies cannot create unbounded energy.
        local impulse = math.max(0, closing) * (1 + math.min(a.bounce, b.bounce))
          / (2 + 2 * (leverA ^ 2 + leverB ^ 2))
        if impulse > 0.001 then
          local point = {x = (ca.x + cb.x) / 2, z = (ca.z + cb.z) / 2}
          local was = sim.touching[key]
          if a.toppleTime == nil then
            if not was or impulse >= deck.TOPPLE_IMPULSE then impact(sim, a, "pin", b.id, impulse, {x = -normal.x, z = -normal.z}, point, timeMs) end
          elseif b.toppleTime == nil then
            if not was or impulse >= deck.TOPPLE_IMPULSE then impact(sim, b, "pin", a.id, impulse, normal, point, timeMs) end
          elseif not was then
            impact(sim, b, "pin", a.id, impulse, normal, point, timeMs)
          end
          if a.toppleTime ~= nil then
            a.vx = a.vx - normal.x * impulse; a.vz = a.vz - normal.z * impulse
            a.turn = a.turn - leverA * impulse * 2
            limitSpeed(a)
          end
          if b.toppleTime ~= nil then
            b.vx = b.vx + normal.x * impulse; b.vz = b.vz + normal.z * impulse
            b.turn = b.turn + leverB * impulse * 2
            limitSpeed(b)
          end
        end
        -- Correct only overlapping movable bodies. Upright pins remain planted until toppled.
        local movable = (a.toppleTime ~= nil and 1 or 0) + (b.toppleTime ~= nil and 1 or 0)
        local correction = math.max(0, deck.PIN_RADIUS * 2 - cdist) * 0.6 / movable
        if a.toppleTime ~= nil then a.x = a.x - normal.x * correction; a.z = a.z - normal.z * correction; boundPin(a) end
        if b.toppleTime ~= nil then b.x = b.x + normal.x * correction; b.z = b.z + normal.z * correction; boundPin(b) end
      end
    end
  end end
  sim.touching = nextTouching
  local settled = true
  for _, pin in ipairs(bodies) do
    if pin.toppleTime == nil then
      if timeMs - pin.wobbleTime < 250 then settled = false end
    elseif pin.fall < 1 or hypot(pin.vx, pin.vz) > STOP_SPEED or abs(pin.turn) > STOP_SPEED or abs(pin.roll) > STOP_SPEED then
      settled = false
    else pin.vx = 0; pin.vz = 0; pin.turn = 0; pin.roll = 0 end
  end
  sim.timeMs = timeMs
  sim.durationMs = timeMs
  if timeMs >= deck.BALL_TRAVEL_MS and settled then
    sim.finished = true
    local knocked, remaining = {}, {}
    for _, pin in ipairs(bodies) do
      if pin.toppleTime ~= nil then knocked[#knocked + 1] = pin.id else remaining[#remaining + 1] = pin.id end
    end
    sim.knockedDown, sim.remaining = knocked, remaining
  end
  return sim.finished
end

-- Controlled shot: {position, angle, spin, power, seed, standing}. Returns a resumable
-- simulation; call deck.stepPinAction until true, then deck.finishShot.
function deck.beginShot(shot)
  local tr, err = deck.preview(shot)
  if not tr then return nil, err end
  local function ballAt(timeMs)
    local progress = timeMs / deck.BALL_TRAVEL_MS
    if shot.power < deck.MIN_ROLL_POWER or progress < 0 or progress > tr.maxProgress
      or (tr.gutterProgress ~= nil and progress >= tr.gutterProgress) then return nil end
    return {x = deck.trajectoryX(tr, progress), z = deck.RELEASE_Z + (deck.END_Z - deck.RELEASE_Z) * progress}
  end
  local sim, perr = deck.newPinAction({standing = shot.standing, seed = shot.seed, power = shot.power, ballAt = ballAt})
  if not sim then return nil, perr end
  sim.trajectory = tr
  return sim
end

function deck.finishShot(sim)
  local tr = sim.trajectory
  local contactPinIds, firstContact = {}, nil
  for _, e in ipairs(sim.events) do
    if e.source == "ball" then
      contactPinIds[#contactPinIds + 1] = e.pinId
      firstContact = firstContact or e
    end
  end
  local kind = #sim.knockedDown > 0 and "hit" or tr.gutterProgress ~= nil and "gutter"
    or sim.input.power < deck.MIN_ROLL_POWER and "short" or "miss"
  return {kind = kind, knockedDown = sim.knockedDown, remaining = sim.remaining, durationMs = sim.durationMs,
    events = sim.events, contactPinIds = contactPinIds,
    firstContactRow = firstContact and pinById[firstContact.pinId].row or nil, trajectory = tr}
end

-- Synchronous helper for tests and calibration.
function deck.resolveShot(shot, onStep)
  local sim, err = deck.beginShot(shot)
  if not sim then return nil, err end
  repeat
    local done = deck.stepPinAction(sim)
    if onStep then onStep(sim) end
  until done
  return deck.finishShot(sim), sim
end

return deck
