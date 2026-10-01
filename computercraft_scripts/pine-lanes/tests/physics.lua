-- Pine Lanes physics contract over the furball kernel. Exact kernel parity lives in tests/furball.lua.
local lane=require("lib.lane")
local physics=require("lib.physics")
local deck=require("lib.pindeck")

local function same(a,b,epsilon) return math.abs(a-b)<=(epsilon or 1e-9) end
local function shot(position,aim,power,hook,id,seed)
  return {deliveryId=id or 1,position=position or 0,aim=aim or 0,power=power or 60,hook=hook or 0,seed=seed or 123}
end
local function run(s,rack) return physics.simulate(rack or lane.newRack(),s) end
local function ids(values)
  local out={};for _,v in ipairs(values) do out[#out+1]=tostring(type(v)=="table" and v.id or v) end
  table.sort(out,function(a,b) return tonumber(a)<tonumber(b) end)
  return table.concat(out,",")
end
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function checkSnapshot(sample)
  assert(finite(sample.t) and finite(sample.ball.x) and finite(sample.ball.y) and finite(sample.ball.z))
  for _,p in ipairs(sample.pins) do
    assert(finite(p.id) and finite(p.x) and finite(p.z) and finite(p.angle) and finite(p.tilt))
  end
end

-- The rack is furball's: four rows 0.8 apart, 1.1 between neighbours in a row, head pin on the centreline.
local rack=lane.newRack();local again=lane.newRack()
assert(#rack==10 and rack[1].id==1 and rack[10].id==10)
assert(rack~=again and rack[1]~=again[1])
assert(same(rack[1].x,lane.headX) and same(rack[1].z,0))
assert(same(rack[2].x-rack[1].x,lane.rowDepth) and same(rack[3].z-rack[2].z,lane.pinSpacing))
assert(same(lane.toPine(0,deck.HEAD_PIN_Z),lane.headX))

-- Batch size does not affect deterministic results or snapshots; input racks are never mutated.
local original={};for i,p in ipairs(rack) do original[i]={id=p.id,x=p.x,z=p.z} end
local sim=assert(physics.begin(rack,shot(-10,2,80,0,4,7)))
while not sim.done do physics.advance(sim,1) end
local batched=assert(physics.begin(rack,shot(-10,2,80,0,4,7)))
while not batched.done do physics.advance(batched,17) end
local a,b=sim.result,batched.result
assert(a.status=="ok" and a.deliveryId==4 and ids(a.knocked)==ids(b.knocked) and same(a.duration,b.duration))
assert(#sim.trajectory==#batched.trajectory)
for i,sample in ipairs(sim.trajectory) do
  checkSnapshot(sample)
  local other=batched.trajectory[i]
  assert(same(sample.t,other.t) and same(sample.ball.x,other.ball.x) and same(sample.ball.z,other.ball.z))
  if i>1 then assert(sample.t-sim.trajectory[i-1].t<=1/30+1e-7,"snapshot gap") end
end
assert(sim.trajectory[1].t==0)
for i,p in ipairs(rack) do assert(p.x==original[i].x and p.z==original[i].z,"simulation mutated its input rack") end

-- Knocked and standing ids partition the rack; standing pins return as fresh upright rack poses.
assert(#a.knocked+#a.standing==10)
for _,p in ipairs(a.standing) do
  local spot=lane.newRack()[p.id]
  assert(p.down==false and same(p.x,spot.x) and same(p.z,spot.z) and p.tilt==0)
end

-- Furball's pocket shot strikes for every seed tried; the same seed always replays the same pins.
for seed=1,6 do
  local strike=run(shot(-32,10,100,0,1,1000+seed))
  assert(strike.status=="ok" and #strike.knocked==10 and #strike.standing==0,"pocket shot missed pins at seed "..seed)
end
local first,second=run(shot(30,-6,72,18,2,9)),run(shot(30,-6,72,18,2,9))
assert(ids(first.knocked)==ids(second.knocked),"equal seeds diverged")

-- A spare delivery only sees the pins still standing.
local leave=run(shot(30,-6,72,18,1,9))
assert(#leave.standing>0)
local spare=run(shot(0,0,80,0,2,10),leave.standing)
for _,id in ipairs(spare.knocked) do
  local wasStanding=false
  for _,p in ipairs(leave.standing) do if p.id==id then wasStanding=true end end
  assert(wasStanding,"spare knocked a pin that was already down")
end

-- Positive hook bends right (+Z) and negative hook left, mirroring exactly on an empty deck.
local empty={}
local function endZ(hook)
  local s=assert(physics.begin(empty,shot(0,0,60,hook,1,5)))
  while not s.done do physics.advance(s,120) end
  local last
  for _,sample in ipairs(s.trajectory) do if sample.ball.x<=lane.headX then last=sample end end
  return last.ball.z,s
end
local rightZ,rightSim=endZ(40);local leftZ=endZ(-40);local straightZ,straightSim=endZ(0)
assert(rightZ>0 and leftZ<0 and same(rightZ,-leftZ,1e-9),"hook did not mirror")
for _,sample in ipairs(straightSim.trajectory) do assert(same(sample.ball.z,0),"zero hook/aim drifted sideways") end
assert(#rightSim.result.knocked==0 and rightSim.result.kind=="miss")

-- A gutter is a lockout: the ball cannot hook back in and contact the rack.
local gutter=assert(physics.begin(lane.newRack(),shot(100,30,100,100,1,1)))
while not gutter.done do physics.advance(gutter,120) end
assert(gutter.result.status=="ok" and #gutter.result.knocked==0 and gutter.result.kind=="gutter")
assert(gutter.trajectory[#gutter.trajectory].ball.gutter=="right")

-- Under-powered rolls stop short of the head pin.
local short=run(shot(0,0,10,0,1,2))
assert(short.status=="ok" and short.kind=="short" and #short.knocked==0)

-- The aim preview samples the kernel path without drawing randomness.
local preview=physics.preview({position=-32,aim=10,power=100,hook=0})
assert(#preview>2 and same(preview[1].x,0) and same(preview[1].z,deck.releaseX(-32)))
assert(physics.preview({position=100,aim=30,power=100,hook=100})[#physics.preview({position=100,aim=30,power=100,hook=100})].gutter)

-- Malformed shots are rejected before a simulation exists.
local invalid,err=physics.begin(lane.newRack(),shot(0,0,101,0,14))
assert(invalid==nil and err)
local duplicate,derr=physics.begin({rack[1],rack[1]},shot())
assert(duplicate==nil and derr)
local noSeed,serr=physics.begin(lane.newRack(),{deliveryId=1,position=0,aim=0,power=50,hook=0})
assert(noSeed==nil and serr)

return true
