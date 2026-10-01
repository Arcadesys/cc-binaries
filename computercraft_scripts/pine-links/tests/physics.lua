-- Shot contract over the furball kernel; exact kernel parity lives in tests/furball.lua.
local golf=require('lib.golf')
local physics=require('lib.physics')
local rules=require('lib.rules')
local hole=golf.newHole()
local shot={club='5i',aim=0,power=94}
local sim=assert(physics.begin(hole,shot))
assert(hole.phase=='ready' and hole.strokes==0,'begin mutated the hole state')
while not physics.advance(sim,1) do end
local batched=assert(physics.begin(hole,shot))
while not physics.advance(batched,37) do end
assert(sim.result.outcome=='rest' and sim.result.surface=='green')
assert(sim.result.position.x==batched.result.position.x and sim.result.position.z==batched.result.position.z)
assert(#sim.trajectory==#batched.trajectory)
for i=2,#sim.trajectory do assert(sim.trajectory[i].t-sim.trajectory[i-1].t<=physics.sampleTicks*golf.STEP+1e-9) end
local points,finish=golf.forecast(hole,shot)
assert(finish.ball.x==sim.result.position.x and finish.ball.z==sim.result.position.z and #points>2)
-- Rules commit once and in order.
local round=rules.new()
assert(rules.apply(round,1,sim.result))
assert(round.hole.strokes==1 and round.hole.lie=='green')
assert(not rules.apply(round,1,sim.result),'duplicate shot applied')
local putt=assert(physics.begin(round.hole,{club='putter',aim=golf.aimToCup(round.hole),power=9.5}))
while not physics.advance(putt) do end
assert(putt.result.outcome=='holed' and rules.apply(round,2,putt.result) and round.hole.phase=='finished')
assert(not rules.apply(round,3,putt.result),'shot after hole complete')
assert(rules.scoreName(2,3)=='Birdie' and golf.scoreLabel(2)=='Birdie!' and golf.scoreLabel(5)=='+2 over par')
-- Out of bounds, sand recovery suggestion, invalid shots.
local wild=physics.simulate(golf.newHole(),{club='5i',aim=-60,power=100})
assert(wild.outcome=='ob' and wild.state.penalties==1 and wild.state.strokes==2)
local sand=golf.newHole(); sand.ball.x=-12; sand.ball.z=151; sand.lie='sand'
assert(golf.suggestion(sand,{club='7i',power=50}).club=='wedge')
assert(physics.begin(golf.newHole(),{club='driver',aim=0,power=50})==nil)
assert(physics.begin(golf.newHole(),{club='5i',aim=0,power=0})==nil)
assert(physics.begin(round.hole,shot)==nil,'finished hole accepted a shot')
return true
