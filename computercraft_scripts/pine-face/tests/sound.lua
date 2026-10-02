-- Speaker cues: every note is playable, play-by-play reaches the speaker, and no speaker is silence.
local Sound = require("lib.sound")
local App = require("lib.app")

local INSTRUMENTS = {harp = true, basedrum = true, snare = true, hat = true, bass = true, flute = true, bell = true,
  guitar = true, chime = true, xylophone = true, iron_xylophone = true, cow_bell = true, didgeridoo = true, bit = true,
  banjo = true, pling = true}
for name, notes in pairs(Sound.cues) do
  for _, n in ipairs(notes) do
    assert(n[1] >= 0 and INSTRUMENTS[n[2]] and n[3] > 0 and n[3] <= 3 and n[4] >= 0 and n[4] <= 24, "bad note in cue " .. name)
  end
end

local function recorder()
  local heard = {}
  return {playNote = function(instrument, volume, pitch) heard[#heard + 1] = instrument .. ":" .. pitch; return true end}, heard
end

-- Notes wait for their time, then drain; an unknown cue is ignored.
local speaker, heard = recorder()
local s = Sound.new({speaker = speaker})
s:play("fire"); s:play("nonsense")
s:tick(0); assert(#heard == 0, "notes sounded before their time")
s:tick(math.huge); assert(#heard == #Sound.cues.fire and #s.queue == 0)

-- A speaker that throws never reaches the game.
local noisy = Sound.new({speaker = {playNote = function() error("speaker unplugged") end}})
noisy:play("fire"); noisy:tick(math.huge)

-- No speaker: silent no-ops.
local mute = Sound.new({}); mute.speaker = nil
mute:play("fire"); mute:tick(math.huge)

-- A solo host hears its own world: events become cues from this seat's point of view.
local function game()
  local sp, said = recorder()
  local app = App.new({solo = true, seed = 1, sound = Sound.new({speaker = sp})})
  return app, said
end
local function drain(app) app.sound:tick(math.huge) end
local function names(cue) local out = {}; for i, n in ipairs(Sound.cues[cue]) do out[i] = n[2] .. ":" .. n[4] end; return out end
local function heard(said, cue)
  local want = names(cue)
  for i = 1, #said - #want + 1 do
    local ok = true
    for j = 1, #want do if said[i + j - 1] ~= want[j] then ok = false; break end end
    if ok then return true end
  end
  return false
end
local function stage(app, tick, events)
  app.session.state.tick = tick; app.session.state.events = events
  app:hearEvents(); drain(app)
end

local app, said = game()
app:command("start"); drain(app)
assert(heard(said, "start"), "no start jingle")
stage(app, 1001, {{kind = "fire", seat = 1}, {kind = "fire", seat = 3}})
assert(heard(said, "fire") and heard(said, "fire_far"), "own and distant shots should differ")
local n = #said
stage(app, 1001, {{kind = "fire", seat = 1}})
assert(#said == n, "the same tick must not sound twice")
stage(app, 1002, {{kind = "hit", seat = 1, by = 2}, {kind = "hit", seat = 2, by = 1}, {kind = "block", seat = 3, by = 1}})
assert(heard(said, "hit") and heard(said, "hitmark") and heard(said, "block"), "hits and blocks")
stage(app, 1003, {{kind = "hit", seat = 2, by = 1}, {kind = "tag", seat = 2, by = 1}})
assert(heard(said, "tag"), "my tag")
local before = #said
stage(app, 1004, {{kind = "hit", seat = 1, by = 3}, {kind = "tag", seat = 1, by = 3}, {kind = "spawn", seat = 1}})
assert(heard(said, "tagged") and heard(said, "spawn"), "being tagged and respawning")
assert(not heard({table.unpack(said, before + 1, before + 2)}, "hit"), "a tag should not also sound as a plain hit")
stage(app, 1005, {{kind = "tag", seat = 2, by = 3}})
assert(heard(said, "tag_far"), "other seats' tags are quiet")

-- Game over: the winner hears the fanfare, everyone else the defeat.
local won, wonSaid = game()
won:command("start"); won.session.state.winner = 1; won.session.phase = "over"; won:hearPhase(); drain(won)
assert(heard(wonSaid, "win"), "winner fanfare")
local lost, lostSaid = game()
lost:command("start"); lost.session.state.winner = 3; lost.session.phase = "over"; lost:hearPhase(); drain(lost)
assert(heard(lostSaid, "lose"), "defeat sound")

-- Bots shooting at each other through the real update loop make noise without any input.
local live, liveSaid = game()
live:command("start")
local clock = 0
for _ = 1, 400 do clock = clock + 100; live:update(clock); drain(live) end
assert(#liveSaid > 4, "a running match was silent")
return true
