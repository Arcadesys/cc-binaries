-- Speaker cues for Pine Face. A cue is a list of {delayMs, instrument, volume, pitch}; play()
-- queues it and tick() (run every frame) sounds what is due, so audio never sleeps the event
-- loop. No speaker, or one that errors, is silence rather than a crash.
local Sound = {}
Sound.__index = Sound

local CUES = {
  start = {{0, "pling", 1, 12}, {100, "pling", 1, 16}, {200, "pling", 1, 19}, {300, "pling", 1, 24}},
  fire = {{0, "bit", 0.9, 22}, {40, "bit", 0.7, 16}, {80, "bit", 0.5, 10}},
  fire_far = {{0, "bit", 0.25, 18}},
  hit = {{0, "snare", 1, 8}, {0, "bass", 1, 4}},
  hitmark = {{0, "xylophone", 0.9, 24}},
  block = {{0, "iron_xylophone", 1, 20}, {0, "hat", 0.8, 24}},
  tag = {{0, "bell", 1, 19}, {80, "bell", 1, 24}, {160, "chime", 1, 24}},
  tagged = {{0, "bass", 1, 10}, {150, "bass", 1, 6}, {300, "bass", 1, 2}},
  tag_far = {{0, "pling", 0.3, 12}},
  spawn = {{0, "harp", 0.8, 14}, {90, "harp", 0.8, 19}},
  win = {{0, "bell", 1, 12}, {130, "bell", 1, 16}, {260, "bell", 1, 19}, {390, "bell", 1, 24},
    {650, "bell", 1, 19}, {780, "bell", 1.2, 24}},
  lose = {{0, "bass", 1, 12}, {300, "bass", 1, 8}, {600, "bass", 1, 4}, {900, "bass", 1.2, 0}},
}

local MAX_QUEUE = 64

function Sound.new(options)
  options = options or {}
  local speaker = options.speaker
  if speaker == nil and peripheral and peripheral.find then speaker = peripheral.find("speaker") end
  return setmetatable({speaker = speaker or nil, queue = {}}, Sound)
end

function Sound:play(cue, offsetMs)
  local notes = CUES[cue]
  if not self.speaker or not notes then return end
  local at = os.epoch("utc") + (offsetMs or 0)
  for _, n in ipairs(notes) do
    if #self.queue >= MAX_QUEUE then return end
    self.queue[#self.queue + 1] = {at = at + n[1], n[2], n[3], n[4]}
  end
end

function Sound:tick(now)
  if #self.queue == 0 then return end
  now = now or os.epoch("utc")
  local waiting = {}
  for _, q in ipairs(self.queue) do
    if q.at <= now then pcall(self.speaker.playNote, q[1], q[2], q[3]) else waiting[#waiting + 1] = q end
  end
  self.queue = waiting
end

Sound.cues = CUES
return Sound
