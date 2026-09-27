local lane=require("lib.lane")
local physics=require("lib.physics")

local function same(a,b,epsilon) return math.abs(a-b)<=(epsilon or 1e-9) end
local function shot(position,aim,power,hook,id)
  return {deliveryId=id or 1,position=position or 0,aim=aim or 0,power=power or .75,hook=hook or 0}
end
local function run(s,rack) return physics.simulate(rack or lane.newRack(),s) end
local function ids(values)
  local out={};for _,v in ipairs(values) do out[#out+1]=tostring(type(v)=="table" and v.id or v) end
  return table.concat(out,",")
end
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function checkSnapshot(sample)
  assert(finite(sample.t) and finite(sample.ball.x) and finite(sample.ball.y) and finite(sample.ball.z))
  for _,p in ipairs(sample.pins) do
    assert(finite(p.id) and finite(p.x) and finite(p.z) and finite(p.angle) and finite(p.tilt))
  end
end
local function samePath(a,b,mirrorZ)
  assert(#a==#b,"trajectory sample count changed")
  for i=1,#a do
    local x,y=a[i],b[i]
    checkSnapshot(x);checkSnapshot(y)
    assert(same(x.t,y.t) and same(x.ball.x,y.ball.x) and same(x.ball.y,y.ball.y))
    assert(same(x.ball.z,(mirrorZ and -1 or 1)*y.ball.z))
    local expected=x.ball.gutter
    if mirrorZ then expected=expected=="left" and "right" or expected=="right" and "left" or false end
    assert(expected==y.ball.gutter,"mirrored gutter state diverged")
    assert(#x.pins==#y.pins)
    for j=1,#x.pins do
      local p,q=x.pins[j],y.pins[j]
      assert(p.id==q.id and same(p.x,q.x) and same(p.z,(mirrorZ and -1 or 1)*q.z))
      assert(same(p.angle,(mirrorZ and -1 or 1)*q.angle) and same(p.tilt,q.tilt) and p.down==q.down)
    end
  end
end

-- Standard rack geometry is close-packed equilateral triangles with fresh state.
local rack=lane.newRack();local again=lane.newRack()
assert(#rack==10 and rack[1].id==1 and rack[10].id==10)
assert(rack~=again and rack[1]~=again[1])
assert(same(rack[1].x+lane.pinSpacing*math.sqrt(3)/2,rack[2].x))
assert(same(math.sqrt((rack[2].x-rack[1].x)^2+(rack[2].z-rack[1].z)^2),lane.pinSpacing))

-- Midpoint and batch size do not affect deterministic results or snapshots.
local original={};for i,p in ipairs(rack) do original[i]={id=p.id,x=p.x,z=p.z,angle=p.angle,tilt=p.tilt,down=p.down} end
local sim=assert(physics.begin(rack,shot(0,0,.9,0,4)))
local first=sim.trajectory[1];local firstX=first.ball.x
while not sim.done do physics.advance(sim,1) end
local a,trajectory=sim.result,sim.trajectory
local b,other=run(shot(0,0,.9,0,4))
local batched=assert(physics.begin(rack,shot(0,0,.9,0,4)))
while not batched.done do physics.advance(batched,17) end
assert(a.status=="ok" and b.status==a.status and a.deliveryId==4)
assert(#a.knocked==#b.knocked and ids(a.knocked)==ids(b.knocked))
assert(same(a.duration,b.duration) and same(a.duration,batched.result.duration))
samePath(trajectory,other);samePath(trajectory,batched.trajectory)
assert(first.ball.x==firstX and first.t==0,"cached initial snapshot was mutated")
for i=2,#trajectory do assert(trajectory[i].t-trajectory[i-1].t<=1/30+1e-7) end
for i,p in ipairs(rack) do
  local q=original[i]
  assert(p.id==q.id and p.x==q.x and p.z==q.z and p.angle==q.angle and p.tilt==q.tilt and p.down==q.down,
    "simulation mutated its input rack")
end

-- Reproducible physical strike and two-delivery spare fixtures.
local strike,strikePath=run(shot(-.08,0,1,0,1))
local partial,partialPath=run(shot(.27,0,.8,0,2))
for _,sample in ipairs(strikePath) do checkSnapshot(sample) end
for _,sample in ipairs(partialPath) do checkSnapshot(sample) end
-- Maximum-power strike and off-center glancing delivery exercise fast impact and pin-chain transfer.
assert(strike.status=="ok" and #strike.knocked==10 and #strike.standing==0,"calibrated strike missed pins")
local spare=run(shot(-.38,0,.4,0,3),partial.standing)
assert(partial.status=="ok" and ids(partial.knocked)=="1,3,5,6,9,10" and #partial.standing==4,"glancing-contact fixture changed")
assert(spare.status=="ok" and #spare.knocked==4 and #spare.standing==0,"calibrated spare missed survivors")

-- A fresh delivery starts from the exact surviving poses supplied by the prior result.
local retained=assert(physics.begin(partial.standing,shot(.38,math.pi/2,.25,0,17)))
local initial=retained.trajectory[1]
assert(#initial.pins==#partial.standing)
for i,p in ipairs(partial.standing) do
  local q=initial.pins[i]
  assert(q.id==p.id and same(q.x,p.x) and same(q.z,p.z) and same(q.angle,p.angle) and same(q.tilt,p.tilt) and q.down==p.down)
end
while not retained.done do physics.advance(retained,120) end
assert(retained.result.status=="ok" and #retained.result.standing==#partial.standing)
for i,p in ipairs(partial.standing) do
  local q=retained.result.standing[i]
  assert(q.id==p.id and same(q.x,p.x) and same(q.z,p.z) and same(q.angle,p.angle) and same(q.tilt,p.tilt) and q.down==p.down)
end

-- Opposite hook inputs curve to opposite sides; hook stops on first pin impact.
local empty={}
local straight=run(shot(0,0,.75,0,8),empty)
local right=run(shot(0,0,.75,1,9),empty)
local left=run(shot(0,0,.75,-1,10),empty)
assert(straight.status=="ok" and right.status=="ok" and left.status=="ok")
-- The public result intentionally carries pin partitions only; trajectory is the ball receipt.
local rightSim=assert(physics.begin(empty,shot(0,0,.75,1,9)))
while not rightSim.done do physics.advance(rightSim,120) end
local leftSim=assert(physics.begin(empty,shot(0,0,.75,-1,10)))
while not leftSim.done do physics.advance(leftSim,120) end
assert(rightSim.trajectory[#rightSim.trajectory].ball.z>leftSim.trajectory[#leftSim.trajectory].ball.z)
local straightSim=assert(physics.begin(empty,shot(0,0,.75,0,8)))
while not straightSim.done do physics.advance(straightSim,7) end
for _,sample in ipairs(straightSim.trajectory) do assert(same(sample.ball.z,0),"zero hook/aim drifted sideways") end
samePath(rightSim.trajectory,leftSim.trajectory,true)

-- Hook force is disabled on the first physical pin contact.
local hookedContact=assert(physics.begin(lane.newRack(),shot(-.08,0,1,1,16)))
for _=1,2000 do
  if hookedContact.hitAny then break end
  physics.advance(hookedContact,1)
end
assert(hookedContact.hitAny and hookedContact.hookActive==false,"hook continued after first pin impact")

-- The gutter is a lockout: the curved ball cannot re-enter and contact a rack.
local gutterSim=assert(physics.begin(lane.newRack(),shot(.38,0,1,1,11)))
while not gutterSim.done do physics.advance(gutterSim,120) end
assert(gutterSim.result.status=="ok" and #gutterSim.result.knocked==0)
assert(gutterSim.trajectory[#gutterSim.trajectory].ball.gutter=="right")

-- Separated collinear capsules and a standing pin do not collide spontaneously.
local separated={
  {id=1,x=5,z=0,angle=0,tilt=math.pi/2,down=true},
  {id=2,x=5.6,z=0,angle=0,tilt=0,down=false},
}
local still=assert(physics.begin(separated,shot(.38,0,.25,0,12)))
while not still.done do physics.advance(still,120) end
assert(#still.result.knocked==1 and still.result.knocked[1]==1)
assert(#still.result.standing==1 and still.result.standing[1].id==2)
assert(still.result.standing[1].tilt==0,"stationary separated pin gained energy")

-- A fallen pin remains a capsule collider that can absorb ball momentum.
local fallen={{id=1,x=5,z=0,angle=0,tilt=math.pi/2,down=true}}
local pinHit,pinHitPath=run(shot(0,0,.75,0,13),fallen)
local noPins,noPinPath=run(shot(0,0,.75,0,13),empty)
assert(pinHit.status=="ok" and noPins.status=="ok")
local function ballXNear(path,t)
  local best=path[1]
  for _,sample in ipairs(path) do if math.abs(sample.t-t)<math.abs(best.t-t) then best=sample end end
  return best.ball.x
end
assert(ballXNear(pinHitPath,.6)<ballXNear(noPinPath,.6),"fallen capsule did not absorb ball momentum")

-- Malformed shots and bounded-time runaway return cancellable errors.
local invalid,err=physics.begin(lane.newRack(),shot(0,0,1.1,0,14))
assert(invalid==nil and err)
local oldMax=physics.maxDuration;physics.maxDuration=.01
local timed=assert(physics.begin(lane.newRack(),shot(0,0,.75,0,15)))
while not timed.done do physics.advance(timed,120) end
physics.maxDuration=oldMax
assert(timed.result.status=="error" and timed.result.error=="simulation timed out")

return true
