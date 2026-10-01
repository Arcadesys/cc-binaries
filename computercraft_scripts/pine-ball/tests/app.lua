-- Controller flow on the pausable game clock; outcomes come from the kernel.
local App = require("lib.app")
local bb = require("lib.baseball")
local function run(app, ms) for _ = 1, math.ceil(ms / 20) do app:advance(20) end end
local function toPitch(app)
  local guard = 0
  while app.phase ~= "PITCH" and guard < 2000 do app:advance(20); guard = guard + 1 end
  assert(app.phase == "PITCH", "never reached a pitch: " .. app.phase)
end

-- Setup: mode and innings, then intro; Space skips the intro.
local a = App.new({seed = 7})
assert(a.phase == "SETUP" and a.mode == "cpu" and a.innings == 3)
a:action("innings_up"); a:action("innings_down"); a:action("innings_down"); assert(a.innings == 2)
a:action("mode"); assert(a.mode == "duel"); a:action("mode")
a:action("start"); assert(a.phase == "INTRO")
a:action("swing"); assert(a.phase == "WINDUP" and a.pitch)

-- A perfectly timed swing (input + 80 ms = arrival) resolves through the kernel with the same RNG.
toPitch(a)
local p = a.pitch
while a.clock < p.arrivesAt - 80 - 20 do a:advance(20) end
a:advance(p.arrivesAt - 80 - a.clock); a:action("swing")
assert(a.swing.offset == 0 and bb.contactTier(p.pitch.location, 0) ~= nil or a.swing.tier == nil)
local copy = App.new({seed = 7}); copy:action("start"); copy:action("swing")
local expected = bb.resolvePitch(p.pitch, {timingOffsetMs = 0, aim = {x = 0, y = 0}, bats = "R"},
  (function() local r = require("lib.rng").create(7); bb.cpuPitch(r); return r end)())
assert(a.swing.event.kind == expected.kind and a.swing.event.result == expected.result, "swing diverged from kernel")
local events = 0
a.options.record = function(kind) if kind == "commit" then events = events + 1 end end
run(a, 6000)
assert(events >= 1, "play never committed")

-- Taking every pitch: balls and called strikes only, ending each plate appearance by walk or strikeout.
local take = App.new({seed = 11}); take:action("start"); take:action("swing")
local guard = 0
while take.state.inning == 1 and take.state.half == "top" and guard < 20000 do take:advance(40); guard = guard + 1 end
assert(take.state.half == "bottom" or take.state.inning > 1, "half inning never ended")

-- Pausing freezes the clock and every deadline.
local paused = App.new({seed = 3}); paused:action("start"); paused:action("swing")
local clock = paused.clock; paused:action("pause"); paused:advance(200); assert(paused.clock == clock)
paused:action("pause"); assert(paused.phase == "WINDUP")

-- Held aim keys and touch toggles share one aim state.
paused:action("hold_left"); assert(paused:aim().x == -1); paused:action("release_left"); assert(paused:aim().x == 0)
paused:action("aim_x"); assert(paused:aim().x == -1); paused:action("aim_x"); assert(paused:aim().x == 1); paused:action("aim_x"); assert(paused:aim().x == 0)
paused:action("aim_y"); assert(paused:aim().y == -1)

-- Duel: the pitching player's choice is validated and thrown as chosen.
local duel = App.new({seed = 5, mode = "duel"}); duel:action("start"); duel:action("swing")
assert(duel.phase == "PITCH_SELECT" and duel:roles().pitcher == "P2 DARK")
duel:action("pitch_3"); for _ = 1, 10 do duel:action("pitch_right") end; duel:action("pitch_down")
assert(duel.draft.x == bb.PITCH_LOCATION_LIMIT and duel.draft.y == -bb.PITCH_AIM_STEP)
duel:action("throw"); assert(duel.phase == "WINDUP" and duel.pitch.pitch.type == "curve_left" and duel.pitch.pitch.location.x == 1.5)

-- A whole CPU game with random swings always reaches FINAL with a winner.
local full = App.new({seed = 99, innings = 2}); full:action("start"); full:action("swing")
math.randomseed(4)
guard = 0
while full.phase ~= "FINAL" and guard < 200000 do
  if full.phase == "PITCH" and not full.swing and math.random() < 0.06 then full:action("swing") end
  full:advance(40); guard = guard + 1
end
assert(full.phase == "FINAL" and full.state.status == "final" and full.state.score.light ~= full.state.score.dark)
full:action("swing"); assert(full.phase == "INTRO", "play again")
full:action("pause"); full:action("quit"); assert(not full.running)
return true
