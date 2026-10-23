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

-- Bad command-line values never reach the kernel: innings are whole and 1-9, seeds unsigned 32-bit.
for given, want in pairs({[0] = 1, [-4] = 1, [2.5] = 2, [42] = 9, [9] = 9}) do
  assert(App.new({seed = 1, innings = given}).innings == want, "innings " .. given)
end
assert(App.new({seed = 1, innings = "x"}).innings == bb.DEFAULT_INNINGS and App.new({seed = 1}).innings == bb.DEFAULT_INNINGS)
assert(App.new({seed = -1}).seed == 4294967295 and App.new({seed = 0 / 0}).seed >= 0, "seed range")
assert(App.new({seed = 1, mode = "bogus"}).mode == "cpu")

-- An arrow released while paused (or in help) still releases: the aim never sticks.
local stuck = App.new({seed = 3}); stuck:action("start"); stuck:action("swing")
stuck:action("hold_left"); stuck:action("pause"); stuck:action("release_left"); stuck:action("pause")
assert(stuck:aim().x == 0, "aim stuck after a release in the menu")
stuck:action("hold_up"); stuck:action("help"); stuck:action("release_up"); stuck:action("help")
assert(stuck:aim().y == 0, "aim stuck after a release in help")
stuck.smallDisplay = true; stuck:action("hold_right"); stuck:action("release_right"); stuck.smallDisplay = nil
assert(stuck:aim().x == 0)

-- Setup: a held Up/Down auto-repeats but flips the mode once per press.
local setup = App.new({seed = 1})
setup:action("hold_up"); setup:action("hold_up"); setup:action("hold_up"); assert(setup.mode == "duel", "repeat flipped mode")
setup:action("release_up"); setup:action("hold_down"); assert(setup.mode == "cpu")
setup:action("release_down"); setup:action("start"); assert(setup:aim().y == 0, "setup keys leaked into the aim")

-- Enter skips the intro as well as Space.
local intro = App.new({seed = 1}); intro:action("start"); assert(intro.phase == "INTRO")
intro:action("start"); assert(intro.phase == "WINDUP", "enter did not skip the intro")

-- Through a result hold the HUD names the batter who just finished, not the next one up.
local hold = App.new({seed = 11}); hold:action("start"); hold:action("swing")
local checked = false
guard = 0
while not checked and guard < 20000 do
  hold:advance(40); guard = guard + 1
  if hold.phase == "RESULT" and hold.pitch and hold.pitch.batter.id ~= hold:batter().id then
    assert(hold:view().batter.id == hold.pitch.batter.id, "HUD jumped to the next batter")
    hold:action("pause"); assert(hold:view().batter.id == hold.pitch.batter.id, "paused HUD jumped batters"); hold:action("pause")
    checked = true
  end
end
assert(checked, "no plate appearance ended")

-- Duel results name the winning player.
local duelEnd = App.new({seed = 2, mode = "duel"}); duelEnd.state.status = "final"; duelEnd.state.score = {light = 2, dark = 5}
duelEnd:afterEvent(); assert(duelEnd.phase == "FINAL" and duelEnd.message:find("P2 DARK WINS 5-2", 1, true), duelEnd.message)
assert(duelEnd:view().batter == nil)
return true
