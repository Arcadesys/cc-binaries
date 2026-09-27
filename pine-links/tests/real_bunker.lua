-- Regression for a real hole-07 bunker lie and a playable wedge recovery.
local course=require("lib.course")
local physics=require("lib.physics")
local rules=require("lib.rules")
local hole=course.hole
local tee=hole.tee
local first=physics.simulate(course,{start=tee,club="wedge",aim=math.rad(-3),power=0.70,wind={x=0,z=0}})
assert(first.outcome=="rest","tee shot did not settle: "..tostring(first.outcome))
assert(first.surface=="bunker","tee shot surface was "..tostring(first.surface))

local state=rules.new(tee)
assert(rules.apply(state,1,first,tee))
local lie=first.position
local aim=math.atan2(hole.cup.z-lie.z,hole.cup.x-lie.x)
local recovery,recoveryPower
for i=1,100 do
  local power=i/100
  local result=physics.simulate(course,{start=lie,club="wedge",aim=aim,power=power,wind={x=0,z=0}})
  if result.outcome=="holed" then
    recovery,recoveryPower=result,power
    break
  end
  if result.outcome=="rest" and result.surface~="bunker" and result.surface~="sand" then
    recovery,recoveryPower=result,power
    break
  end
end
assert(recovery,"no wedge power escaped the bunker safely")
assert(rules.apply(state,2,recovery,lie))
assert(state.strokes==2 and state.penalties==0)
print(string.format("bunker sequence: wedge 0.70 aim -3 deg -> (%.2f, %.2f, %.2f); wedge %.2f toward cup -> %s at (%.2f, %.2f, %.2f)",
  lie.x,lie.y,lie.z,recoveryPower,recovery.outcome,recovery.position.x,recovery.position.y,recovery.position.z))
return true
