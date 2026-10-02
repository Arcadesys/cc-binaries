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
s:play("single"); s:play("nonsense")
s:tick(0); assert(#heard == 0, "notes sounded before their time")
s:tick(math.huge); assert(#heard == #Sound.cues.single and #s.queue == 0)

-- A speaker that throws never reaches the game.
local noisy = Sound.new({speaker = {playNote = function() error("speaker unplugged") end}})
noisy:play("homerun"); noisy:tick(math.huge)

-- No speaker: silent no-ops.
local mute = Sound.new({}); mute.speaker = nil
mute:play("homerun"); mute:tick(math.huge)

-- A whole game drives the cues from its own events.
local sp, said = recorder()
local game = App.new({seed = 99, innings = 1, sound = Sound.new({speaker = sp})})
game:action("start")
assert(#game.sound.queue == #Sound.cues.playball, "no play-ball fanfare")
game:action("swing")
math.randomseed(4)
local guard = 0
while game.phase ~= "FINAL" and guard < 200000 do
  if game.phase == "PITCH" and not game.swing and math.random() < 0.06 then game:action("swing") end
  game:advance(40); game.sound:tick(math.huge); guard = guard + 1
end
assert(game.phase == "FINAL" and #said > 30, "game played almost no sound")
return true
