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
s:play("step"); s:play("nonsense")
s:tick(0); assert(#heard == 0, "notes sounded before their time")
s:tick(math.huge); assert(#heard == #Sound.cues.step and #s.queue == 0)

-- A speaker that throws never reaches the game.
local noisy = Sound.new({speaker = {playNote = function() error("speaker unplugged") end}})
noisy:play("step"); noisy:tick(math.huge)

-- No speaker: silent no-ops.
local mute = Sound.new({}); mute.speaker = nil
mute:play("step"); mute:tick(math.huge)

-- Playing the dungeon makes the right noises. Each scene is an empty floor 1 room plus what it needs.
local sp, said
local function scene(x, z, facing, monsters)
  sp, said = recorder()
  local app = App.new({sound = Sound.new({speaker = sp})})
  app.state.monsters = monsters or {}
  app.state.player.x, app.state.player.z, app.state.player.facing = x, z, facing
  return app
end
local function zombie(x, z) return {x = x, z = z, kind = "z", hp = 2, maxHp = 2} end
local function heardCue(app, name)
  local want = {}
  for i, n in ipairs(Sound.cues[name]) do want[i] = n[2] .. ":" .. n[4] end
  app.sound:tick(math.huge)
  for i = 1, #said - #want + 1 do
    local ok = true
    for j = 1, #want do if said[i + j - 1] ~= want[j] then ok = false; break end end
    if ok then return true end
  end
  return false
end

local walker = scene(2, 2, "east")
walker:action("forward"); assert(heardCue(walker, "step"), "no footstep")
walker:action("turn_left"); assert(heardCue(walker, "turn"), "no turn tick")
walker:action("attack"); assert(heardCue(walker, "whiff"), "no whiff")
local wall = scene(2, 2, "west")
wall:action("forward"); assert(heardCue(wall, "blocked"), "no wall bump")
local victim = scene(2, 2, "east", {zombie(3, 2)})
victim:action("attack"); assert(heardCue(victim, "kill"), "no kill sound")
local struck = scene(2, 2, "east", {{x = 3, z = 2, kind = "k", hp = 3, maxHp = 3}})
struck:action("attack"); assert(heardCue(struck, "hit"), "no hit sound")
local hurt = scene(2, 2, "north", {zombie(3, 2)})
hurt:action("wait"); assert(heardCue(hurt, "hurt"), "no hurt sound")
local loot = scene(2, 2, "east")
loot.state.items["2:3"] = "$"
loot:action("forward"); assert(heardCue(loot, "coin"), "no coin sound")
local dead = scene(2, 2, "north", {zombie(3, 2)})
dead.state.player.hp = 1
dead:action("wait"); assert(dead.state.phase == "lost" and heardCue(dead, "lose"), "no defeat sound")
return true
