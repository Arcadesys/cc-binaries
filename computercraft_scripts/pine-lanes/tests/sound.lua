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
s:play("crash"); s:play("nonsense")
s:tick(0); assert(#heard == 0, "notes sounded before their time")
s:tick(math.huge); assert(#heard == #Sound.cues.crash and #s.queue == 0)

-- A speaker that throws never reaches the game.
local noisy = Sound.new({speaker = {playNote = function() error("speaker unplugged") end}})
noisy:play("crash"); noisy:tick(math.huge)

-- No speaker: silent no-ops.
local mute = Sound.new({}); mute.speaker = nil
mute:play("crash"); mute:tick(math.huge)

-- A whole match drives the cues from its own events.
local sp, said = recorder()
local game = App.new({seed = 123, sound = Sound.new({speaker = sp})})
game:action("start"); game:action("mascot_confirm")
assert(#game.sound.queue == #Sound.cues.start, "no start jingle")
local guard = 0
while game.phase ~= "FINAL" and guard < 20000 do
  if game.phase == "AIM" then game:action("roll")
  elseif game.phase == "RESULT" then game:action("continue") end
  game:tick(0.1); game.sound:tick(math.huge); guard = guard + 1
end
assert(game.phase == "FINAL" and #said > 30, "match played almost no sound")
local crashes = 0
for _, h in ipairs(said) do if h == "snare:14" then crashes = crashes + 1 end end
assert(crashes >= 1, "pins fell in silence")
return true
