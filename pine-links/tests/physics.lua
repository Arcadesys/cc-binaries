local physics = require("lib.physics")

local function near(a,b,tol) return math.abs(a-b) <= tol end
local function course(sampleFn, cup, waterLevel)
  return { hole = { cup = cup or {x=107,y=0,z=0}, waterLevel = waterLevel or -100,
    bounds = {minX=-1000,maxX=1000,minZ=-1000,maxZ=1000} }, sample = sampleFn }
end
local flat = course(function() return {height=0,nx=0,ny=1,nz=0,material="fairway"} end)
local function shot(club,power,aim,start)
  return {start=start or {x=0,y=0,z=0},club=club,aim=aim or 0,power=power,wind={x=0,z=0}}
end

-- Fixed stepping and batching produce the same path and final result.
local a = assert(physics.begin(flat, shot("wedge",0.7)))
local b = assert(physics.begin(flat, shot("wedge",0.7)))
while not a.done do physics.advance(a, 1) end
while not b.done do physics.advance(b, 120) end
assert(a.result.outcome == b.result.outcome)
assert(near(a.result.position.x,b.result.position.x,1e-9))
assert(near(a.result.position.z,b.result.position.z,1e-9))
assert(near(a.result.duration,b.result.duration,1e-9))
assert(#a.trajectory == #b.trajectory)

-- Full wedge power carries farther than half power and aim rotates the shot.
local low = physics.simulate(flat,shot("wedge",0.35))
local high = physics.simulate(flat,shot("wedge",0.9))
local right = physics.simulate(flat,shot("wedge",0.6,math.pi/2))
assert(high.position.x > low.position.x + 10)
assert(math.abs(right.position.z) > math.abs(right.position.x))

-- Surface resistance ranks sand above rough above fairway.
local function rollDistance(material)
  local field = course(function() return {height=0,nx=0,ny=1,nz=0,material=material} end,
    {x=107,y=0,z=90})
  local r = physics.simulate(field,shot("putter",1))
  assert(r.outcome == "rest")
  return r.position.x
end
local fairwayDistance, roughDistance, sandDistance = rollDistance("fairway"),rollDistance("rough"),rollDistance("sand")
assert(fairwayDistance > roughDistance and roughDistance > sandDistance)

-- Cross-slope changes the roll direction; a shallow incline eventually rests.
local slope = course(function(x)
  return {height=0.03*x,nx=-0.03,ny=1,nz=0,material="green"}
end,{x=107,y=3.21,z=90})
local sloped = physics.simulate(slope,shot("putter",0.4))
assert(sloped.outcome == "rest" and sloped.position.x > 0.7)
assert(sloped.position.y > 0)
local uphill = physics.simulate(slope,shot("putter",0.3))
local downhillCourse = course(function(x)
  return {height=-0.03*x,nx=0.03,ny=1,nz=0,material="green"}
end,{x=107,y=0,z=90})
local downhill = physics.simulate(downhillCourse,shot("putter",0.3))
assert(downhill.outcome == "rest" and uphill.outcome == "rest")
assert(uphill.position.x < downhill.position.x)
local slowFairway = course(function(x)
  return {height=0.01*x,nx=-0.01,ny=1,nz=0,material="fairway"}
end,{x=107,y=1.07,z=90})
local slowLie = physics.simulate(slowFairway,shot("putter",0.02))
assert(slowLie.outcome=="rest" and slowLie.surface=="fairway" and slowLie.duration<1)

-- The cup check is swept while rolling and respects the capture speed.
local cupCourse = course(function() return {height=0,nx=0,ny=1,nz=0,material="green"} end,{x=4,y=0,z=0})
local inCup = physics.simulate(cupCourse,shot("putter",0.65))
assert(inCup.outcome == "holed", tostring(inCup.outcome).." x="..tostring(inCup.position.x))
local fastCup = physics.simulate(cupCourse,shot("putter",1))
assert(fastCup.outcome ~= "holed")

-- Water is based on actual vertical contact, so a flight over a gap survives.
local gap = course(function(x)
  if x > 10 and x < 90 then return nil end
  return {height=0,nx=0,ny=1,nz=0,material="fairway"}
end,{x=107,y=0,z=0},-1)
local flyover = physics.simulate(gap,shot("test",0.9))
assert(flyover.outcome ~= "water",tostring(flyover.outcome).." x="..tostring(flyover.position.x).." y="..tostring(flyover.position.y).." t="..tostring(flyover.duration))
assert(flyover.position.x > 10)

-- A narrow terrain ridge between widely separated endpoints is still swept.
local ridge = course(function(x)
  local h = x >= 9.9 and x <= 10.2 and 20 or 0
  return {height=h,nx=0,ny=1,nz=0,material="fairway"}
end,{x=107,y=0,z=90})
local ridgeShot = physics.begin(ridge,shot("wedge",0.5))
while not ridgeShot.done do physics.advance(ridgeShot,120) end
assert(ridgeShot.impactCount > 0)

-- A genuinely low flight over the same gap contacts the water.
local waterGap = course(function(x)
  if x > 2 and x < 90 then return nil end
  return {height=0,nx=0,ny=1,nz=0,material="fairway"}
end,{x=107,y=0,z=0},-0.2)
local intoWater = physics.simulate(waterGap,shot("wedge",0.2))
assert(intoWater.outcome == "water")

-- Invalid inputs and numerical runaway yield safe errors instead of a scoreable lie.
local invalid, message = physics.begin(flat,shot("bad",0.5))
assert(invalid == nil and message)
assert(physics.simulate(flat,nil).outcome == "error")
local timeout = physics.begin(flat,shot("putter",1))
local savedMax = physics.maxDuration
physics.maxDuration = 0.02
while not timeout.done do physics.advance(timeout,120) end
physics.maxDuration = savedMax
assert(timeout.result.outcome == "error" and timeout.result.message == "simulation timed out")

return true
