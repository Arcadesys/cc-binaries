-- Deterministic, renderer-free Pine Links shot simulation.
local physics = {}

physics.step = 1 / 60
physics.maxDuration = 30
physics.maxBatch = 120
physics.gravity = 9.81
physics.captureRadius = 0.6
physics.captureSpeed = 2.0

physics.clubs = {
  { id = "wedge", name = "Wedge", carry = 110, launch = 42 },
  { id = "putter", name = "Putter", carry = 12, launch = 0 },
  { id = "test", name = "Test club", carry = 180, launch = 35 },
}

local clubById = {}
for _, club in ipairs(physics.clubs) do clubById[club.id] = club end

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function copyPos(p, t)
  return { x = p.x, y = p.y, z = p.z, t = t }
end

local function terrain(course, x, z)
  local hole = course.hole or course
  local sample = course.sample or hole.sample
  if type(sample) ~= "function" then return nil end
  local ok, result
  if course.sample then
    ok, result = pcall(sample, x, z)
  else
    ok, result = pcall(sample, x, z)
  end
  if not ok or type(result) ~= "table" or not finite(result.height) then return nil end
  local ny = finite(result.ny) and result.ny or 1
  local nx = finite(result.nx) and result.nx or 0
  local nz = finite(result.nz) and result.nz or 0
  local length = math.sqrt(nx * nx + ny * ny + nz * nz)
  if length < 0.000001 then nx, ny, nz, length = 0, 1, 0, 1 end
  return { height = result.height, nx = nx / length, ny = ny / length,
    nz = nz / length, material = result.material or "fairway" }
end

local function outcome(sim, kind, position, extra)
  if sim.trajectory and position and finite(position.x) and finite(position.y) and finite(position.z) then
    local last = sim.trajectory[#sim.trajectory]
    if not last or last.x ~= position.x or last.y ~= position.y or last.z ~= position.z then
      sim.trajectory[#sim.trajectory + 1] = copyPos(position, sim.time or 0)
    end
  end
  sim.done = true
  sim.phase = "done"
  local result = { position = { x = position.x, y = position.y, z = position.z },
    outcome = kind, duration = sim.time }
  if extra then for k, v in pairs(extra) do result[k] = v end end
  sim.result = result
  return true
end

local function errorResult(sim, message)
  local p = sim.position or sim.start
  return outcome(sim, "error", p, { message = message })
end

local function appendTrajectory(sim)
  local p = sim.position
  local last = sim.trajectory[#sim.trajectory]
  if not last or math.abs(last.t - sim.time) >= 0.049 then
    sim.trajectory[#sim.trajectory + 1] = copyPos(p, sim.time)
  end
end

local function surfaceDrag(material)
  -- Values are rolling deceleration and static-rest threshold. The latter
  -- must exceed dynamic rolling friction or a slowed ball can never settle.
  if material == "sand" or material == "bunker" then return 4.2, 4.3 end
  if material == "rough" then return 2.45, 2.5 end
  if material == "green" then return 0.83, 0.9 end
  return 1.3, 1.4
end

local function cupOf(course)
  local hole = course.hole or course
  return hole.cup or course.cup
end

local function boundsOf(course)
  local hole = course.hole or course
  return hole.bounds or course.bounds
end

local function sweptCup(sim, before, after, speed)
  local cup = cupOf(sim.course)
  if type(cup) ~= "table" or not finite(cup.x) or not finite(cup.z) then return false end
  local cy = finite(cup.y) and cup.y or 0
  if speed > physics.captureSpeed then return false end
  local dx, dz = after.x - before.x, after.z - before.z
  local denom = dx * dx + dz * dz
  local u = 0
  if denom > 0 then u = clamp(((cup.x - before.x) * dx + (cup.z - before.z) * dz) / denom, 0, 1) end
  local x, z = before.x + u * dx, before.z + u * dz
  local y = before.y + u * (after.y - before.y)
  return (x - cup.x) ^ 2 + (z - cup.z) ^ 2 <= physics.captureRadius ^ 2
    and math.abs(y - cy) <= 0.75
end

local function segmentGroundContact(course, a, b)
  -- Sweep the full step in short spatial intervals so a narrow ridge cannot
  -- hide between two clear endpoints. Refine the first crossing by bisection.
  local function clearance(u)
    local x, z = a.x + (b.x - a.x) * u, a.z + (b.z - a.z) * u
    local g = terrain(course, x, z)
    if not g then return nil end
    return a.y + (b.y - a.y) * u - g.height, g
  end
  local distance = math.sqrt((b.x-a.x)^2 + (b.y-a.y)^2 + (b.z-a.z)^2)
  local intervals = math.max(1, math.ceil(distance / 0.25))
  local previousU, previousClearance = nil, nil
  for i = 0, intervals do
    local u = i / intervals
    local c, g = clearance(u)
    if c and c <= 0 then
      -- A shot begins exactly on the tee surface. Do not count that initial
      -- zero-clearance sample as an impact while it is rising away from it.
      if i == 0 and c == 0 then
        previousU, previousClearance = u, c
      else
      local lo = previousU or u
      local hi = u
      if previousClearance and previousClearance > 0 then
        for _ = 1, 12 do
          local mid = (lo + hi) / 2
          local cm = clearance(mid)
          if cm and cm > 0 then lo = mid else hi = mid end
        end
      end
      local hit = hi
      local _, ground = clearance(hit)
      if not ground then ground = g end
      return { x=a.x+(b.x-a.x)*hit, y=ground.height, z=a.z+(b.z-a.z)*hit },ground
      end
    end
    if c then previousU, previousClearance = u, c end
  end
  return nil
end

function physics.begin(course, shot)
  if type(course) ~= "table" or type(shot) ~= "table" then return nil, "course and shot are required" end
  local start, club = shot.start, clubById[shot.club]
  if type(start) ~= "table" or not finite(start.x) or not finite(start.y) or not finite(start.z) then
    return nil, "shot start must contain finite x, y, z"
  end
  if not club then return nil, "unknown club" end
  if not finite(shot.aim) then return nil, "shot aim must be finite" end
  if not finite(shot.power) or shot.power < 0 or shot.power > 1 then return nil, "shot power must be between 0 and 1" end
  local wind = shot.wind or { x = 0, z = 0 }
  if not finite(wind.x or 0) or not finite(wind.z or 0) then return nil, "wind must be finite" end
  local angle = math.rad(club.launch)
  local maxSpeed = math.sqrt(club.carry * physics.gravity / math.max(math.sin(2 * angle), 0.15))
  local speed = maxSpeed * shot.power
  local sim = { course = course, shot = shot, club = club, start = { x=start.x,y=start.y,z=start.z },
    position = { x=start.x,y=start.y,z=start.z }, velocity = { x=0,y=0,z=0 },
    phase = "rolling", time = 0, done = false, trajectory = {}, wind = { x=wind.x or 0,z=wind.z or 0 },
    impactCount = 0 }
  local onGround = terrain(course, start.x, start.z)
  if onGround then sim.position.y = math.max(start.y, onGround.height) end
  if club.id == "putter" then
    -- carry is the nominal roll distance on a level green, not a speed.
    local greenDrag = surfaceDrag("green")
    local speed = math.sqrt(2 * greenDrag * club.carry) * shot.power
    sim.velocity.x = math.cos(shot.aim) * speed
    sim.velocity.z = math.sin(shot.aim) * speed
  else
    sim.phase = "airborne"
    sim.velocity.x = math.cos(shot.aim) * speed * math.cos(angle)
    sim.velocity.z = math.sin(shot.aim) * speed * math.cos(angle)
    sim.velocity.y = speed * math.sin(angle)
  end
  sim.trajectory[1] = copyPos(sim.position, 0)
  if not finite(speed) then errorResult(sim, "non-finite launch speed") end
  return sim
end

local function step(sim)
  local dt, course = physics.step, sim.course
  local p, v = sim.position, sim.velocity
  local before = { x=p.x,y=p.y,z=p.z }
  if sim.phase == "airborne" then
    v.x = v.x + sim.wind.x * 0.025 * dt
    v.z = v.z + sim.wind.z * 0.025 * dt
    v.y = v.y - physics.gravity * dt
    local nextp = { x=p.x + v.x * dt, y=p.y + v.y * dt, z=p.z + v.z * dt }
    local cupSpeed = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
    if nextp.y <= (cupOf(course) and cupOf(course).y or 0) + 0.5 and sweptCup(sim, before, nextp, cupSpeed) then
      return outcome(sim, "holed", cupOf(course))
    end
    local contact, ground = segmentGroundContact(course, before, nextp)
    p.x, p.y, p.z = nextp.x, nextp.y, nextp.z
    if contact then
      p.x,p.y,p.z = contact.x,contact.y,contact.z
      sim.surface = ground.material
      sim.impactCount = sim.impactCount + 1
      local vn = v.x*ground.nx + v.y*ground.ny + v.z*ground.nz
      if vn < 0 then
        local restitution = sim.club.id == "test" and 0.42 or 0.22
        v.x,v.y,v.z = v.x-(1+restitution)*vn*ground.nx,
          v.y-(1+restitution)*vn*ground.ny, v.z-(1+restitution)*vn*ground.nz
      end
      -- Landing transitions into rolling and removes most residual vertical energy.
      local landingGrip = 0.18
      if ground.material == "green" then landingGrip = 0.15 end
      if ground.material == "rough" then landingGrip = 0.22 end
      if ground.material == "sand" or ground.material == "bunker" then landingGrip = 0.10 end
      v.x, v.z = v.x * landingGrip, v.z * landingGrip
      v.y = math.max(0, v.y * 0.18)
      sim.phase = "rolling"
    else
      local hole = course.hole or course
      if finite(hole.waterLevel) and p.y <= hole.waterLevel then return outcome(sim,"water",p) end
      local bounds = boundsOf(course)
      if bounds and (p.x < bounds.minX or p.x > bounds.maxX or p.z < bounds.minZ or p.z > bounds.maxZ) then
        return outcome(sim,"ob",p)
      end
      if terrain(course,p.x,p.z) == nil and finite(hole.waterLevel) and p.y <= hole.waterLevel then
        return outcome(sim,"water",p)
      end
    end
  else
    local ground = terrain(course,p.x,p.z)
    if not ground then
      local hole = course.hole or course
      if finite(hole.waterLevel) and p.y <= hole.waterLevel then return outcome(sim,"water",p) end
      local bounds = boundsOf(course)
      if bounds and (p.x < bounds.minX or p.x > bounds.maxX or p.z < bounds.minZ or p.z > bounds.maxZ) then
        return outcome(sim,"ob",p)
      end
      -- An unsupported ball still travels ballistically through a gap.
      sim.phase = "airborne"
      v.y = math.min(v.y, 0)
    else
      p.y = ground.height
      sim.surface = ground.material
      local drag, static = surfaceDrag(ground.material)
      local ax, az = physics.gravity * ground.nx * ground.ny,
        physics.gravity * ground.nz * ground.ny
      local amag = math.sqrt(ax*ax+az*az)
      local speed = math.sqrt(v.x*v.x+v.z*v.z)
      if speed < 0.08 and amag <= static then
        v.x,v.z,v.y = 0,0,0
        local cup = cupOf(course)
        if cup and sweptCup(sim,before,p,0) then return outcome(sim,"holed",cup,{surface=ground.material}) end
        sim.phase = "resting"
        return outcome(sim,"rest",p,{surface=ground.material})
      end
      v.x = v.x + ax * dt
      v.z = v.z + az * dt
      local newSpeed = math.sqrt(v.x*v.x+v.z*v.z)
      if newSpeed > 0 then
        local reduction = math.min(newSpeed, drag * dt)
        v.x = v.x * (newSpeed-reduction)/newSpeed
        v.z = v.z * (newSpeed-reduction)/newSpeed
      end
      local nextp = { x=p.x+v.x*dt, y=p.y, z=p.z+v.z*dt }
      local distance = math.sqrt((nextp.x-p.x)^2+(nextp.z-p.z)^2)
      local intervals = math.max(1,math.ceil(distance/0.25))
      local nextGround
      for i=1,intervals do
        local u=i/intervals
        local x,z=p.x+(nextp.x-p.x)*u,p.z+(nextp.z-p.z)*u
        nextGround=terrain(course,x,z)
        if not nextGround then
          nextp.x,nextp.z=x,z
          sim.phase="airborne"
          v.y=0
          break
        end
        nextp.y=nextGround.height
      end
      local rollSpeed = math.sqrt(v.x*v.x+v.z*v.z)
      if sweptCup(sim,before,nextp,rollSpeed) then return outcome(sim,"holed",cupOf(course),{surface=ground.material}) end
      p.x,p.y,p.z = nextp.x,nextp.y,nextp.z
      local bounds = boundsOf(course)
      if bounds and (p.x < bounds.minX or p.x > bounds.maxX or p.z < bounds.minZ or p.z > bounds.maxZ) then
        return outcome(sim,"ob",p,{surface=ground.material})
      end
    end
  end
  sim.time = sim.time + dt
  if not finite(p.x) or not finite(p.y) or not finite(p.z) or not finite(v.x) or not finite(v.y) or not finite(v.z) then
    return errorResult(sim,"non-finite simulation state")
  end
  if sim.time >= physics.maxDuration then return errorResult(sim,"simulation timed out") end
  appendTrajectory(sim)
  return false
end

function physics.advance(sim, steps)
  if type(sim) ~= "table" or type(steps) ~= "number" or steps < 0 then return true end
  if sim.done then return true end
  steps = math.floor(steps)
  if steps > physics.maxBatch then steps = physics.maxBatch end
  for _ = 1, steps do
    if step(sim) then return true end
  end
  return sim.done
end

function physics.simulate(course, shot)
  local sim, err = physics.begin(course, shot)
  if not sim then
    local start = type(shot) == "table" and shot.start or nil
    local p = type(start) == "table" and finite(start.x) and finite(start.y) and finite(start.z)
      and {x=start.x,y=start.y,z=start.z} or {x=0,y=0,z=0}
    return { outcome="error", message=err, duration=0, position=p }
  end
  while not sim.done do physics.advance(sim, physics.maxBatch) end
  sim.result.trajectory = sim.trajectory
  return sim.result
end

return physics
