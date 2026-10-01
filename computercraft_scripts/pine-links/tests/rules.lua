local rules=require('lib.rules')
assert(rules.scoreName(1,3)=='Hole in one' and rules.scoreName(3,3)=='Par' and rules.scoreName(4,3)=='Bogey')
assert(rules.scoreName(6,3)=='3 over par' and rules.scoreName(1,0)=='Unknown')
local round=rules.new()
assert(not rules.apply(round,0,{state=round.hole}),'zero shot id')
assert(not rules.apply(round,1,{state={phase='moving'}}),'moving ball committed')
return true
