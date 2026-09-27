-- End-to-end physics calibration against the authored 107-yard sample hole.
local course = require("lib.course")
local physics = require("lib.physics")
local rules = require("lib.rules")
local hole = course.hole
local best

for step=72,84 do
  local power=step/100
  local result=physics.simulate(course,{start=hole.tee,club="wedge",aim=0,power=power,wind={x=0,z=0}})
  if result.outcome=="rest" then
    local distance=math.sqrt((hole.cup.x-result.position.x)^2+(hole.cup.z-result.position.z)^2)
    if not best or distance<best.distance then best={power=power,result=result,distance=distance} end
  elseif result.outcome=="holed" then
    print(string.format("real hole sequence: wedge %.2f (holed)",power))
    return true
  end
end

assert(best,"no safe wedge lie found on hole 7")
assert(best.distance<=physics.clubs[2].carry,
  string.format("best wedge %.2f left %.2f yd from cup",best.power,best.distance))
local state=rules.new(hole.tee)
assert(rules.apply(state,1,best.result,hole.tee))
local from=best.result.position
local aim=math.atan2(hole.cup.z-from.z,hole.cup.x-from.x)
for step=1,100 do
  local power=step/100
  local result=physics.simulate(course,{start=from,club="putter",aim=aim,power=power,wind={x=0,z=0}})
  if result.outcome=="holed" then
    assert(rules.apply(state,2,result,from) and state.complete and state.strokes==2 and state.penalties==0)
    print(string.format("real hole sequence: wedge %.2f to (%.2f, %.2f, %.2f), putter %.2f; score %d, %s",
      best.power,from.x,from.y,from.z,power,state.strokes,rules.scoreName(state.strokes,hole.par)))
    return true
  end
end
error(string.format("wedge %.2f left %.2f yd, but no putt captured",best.power,best.distance))
