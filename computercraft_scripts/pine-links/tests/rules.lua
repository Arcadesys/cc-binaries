local rules = require("lib.rules")

local tee = {x=0,y=1,z=0}
local state = rules.new(tee)
assert(state.strokes == 0 and state.penalties == 0 and not state.complete)
local pre = {x=12,y=0,z=4}
local water = {outcome="water",position={x=30,y=-1,z=4}}
local ok = rules.apply(state,1,water,pre)
assert(ok and state.strokes == 2 and state.penalties == 1)
assert(state.ball.x == 12 and state.ball.z == 4 and not state.complete)
local duplicate = rules.apply(state,1,water,pre)
assert(not duplicate and state.strokes == 2 and state.penalties == 1)

-- Errors consume the id but never change stroke or penalty totals.
local beforeStrokes,beforePenalties = state.strokes,state.penalties
assert(rules.apply(state,2,{outcome="error",message="timeout"},pre))
assert(state.strokes == beforeStrokes and state.penalties == beforePenalties)
assert(not rules.apply(state,2,{outcome="rest",position={x=0,y=0,z=0}},pre))

assert(rules.apply(state,3,{outcome="rest",position={x=20,y=0,z=5}},pre))
assert(state.strokes == 3 and state.penalties == 1 and state.ball.x == 20)
assert(rules.apply(state,4,{outcome="ob"},state.ball))
assert(state.strokes == 5 and state.penalties == 2 and state.ball.x == 20)
assert(rules.apply(state,5,{outcome="holed",position={x=107,y=0,z=0}},state.ball))
assert(state.strokes == 6 and state.complete and state.ball.x == 107)
assert(not rules.apply(state,6,{outcome="rest",position={x=30,y=0,z=0}},state.ball))

assert(rules.scoreName(1,3) == "Hole in one")
assert(rules.scoreName(2,5) == "Albatross")
assert(rules.scoreName(3,5) == "Eagle")
assert(rules.scoreName(4,5) == "Birdie")
assert(rules.scoreName(5,5) == "Par")
assert(rules.scoreName(6,5) == "Bogey")
assert(rules.scoreName(7,5) == "Double bogey")

return true
