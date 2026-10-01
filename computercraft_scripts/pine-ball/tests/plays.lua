-- Furball's fielding layer: who chases, catch plans, conversions and runner paths.
local plays = require("lib.plays")
local bb = require("lib.baseball")
local roster = require("lib.roster")
local rng = require("lib.rng")
local teams = {light = roster.light, dark = roster.dark}
local game = bb.createGame(teams)
-- Centre-field fly: the centre fielder (5th spot) is 2 m away and almost always catches.
local f = plays.aimFielder(game, teams, "FLY_OUT_CENTER", bb.DEFAULT_FIELDING, function() return 0.5 end)
assert(f.pos == "CF" and f.plan.outcome == "caught")
local dropped = plays.resolveInPlay(game, teams, "FLY_OUT_CENTER", bb.DEFAULT_FIELDING, function() return 0.99 end)
assert(dropped.resolved == "ERROR_CENTER" and dropped.pending.state.bases.first == "light-1")
local slow = {reactionMs = 180, runSpeed = 0.1, catchChance = 1}
local late = plays.resolveInPlay(game, teams, "FLY_OUT_LEFT", slow, function() return 0 end)
assert(late.resolved == "SINGLE_LEFT")
-- Grounders get a throw: to first with nobody on, to second for the force.
local ground = plays.resolveInPlay(game, teams, "GROUND_OUT_LEFT", bb.DEFAULT_FIELDING, rng.create(1))
assert(ground.groundThrow.base == 1 and ground.pending.state.outs == 1)
local on = bb.applyPitchEvent(game, {kind = "IN_PLAY", result = "SINGLE_CENTER"}).state
local force = plays.resolveInPlay(on, teams, "GROUND_OUT_RIGHT", bb.DEFAULT_FIELDING, rng.create(1))
assert(force.groundThrow.base == 2)
local moves = plays.runnerMoves(on, force.pending, bb.currentBatter(on))
assert(#moves == 2 and moves[1].to == 1 and moves[2].out)
-- Headlines match furball's wording, including the earned grand slam.
assert(plays.headline({"HOME_RUN", "RUN_SCORED"}, 4) == "GRAND SLAM!" and plays.headline({"HOME_RUN"}, 1) == "HOME RUN!!")
assert(plays.headline({"WALK_OFF", "GAME_OVER"}, 1) == "WALK-OFF!!" and plays.headline({"FOUL"}, 0) == "FOUL")
local p = plays.basepathPoint(1.5)
assert(math.abs(p.x - (plays.BASES[2].x + plays.BASES[3].x) / 2) < 1e-9)
return true
