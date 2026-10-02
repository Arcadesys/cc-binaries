-- Speaker cues for Pine Links. A cue is a list of {delayMs, instrument, volume, pitch}; play()
-- queues it and tick() (run every frame) sounds what is due, so audio never sleeps the event
-- loop. No speaker, or one that errors, is silence rather than a crash.
local Sound = {}
Sound.__index = Sound

local CUES = {
  start = {{0, "harp", 1, 12}, {120, "harp", 1, 16}, {240, "harp", 1, 19}, {360, "harp", 1.2, 24}},
  tick = {{0, "hat", 0.4, 20}},
  swing = {{0, "snare", 0.8, 22}, {0, "iron_xylophone", 0.8, 24}, {30, "hat", 0.6, 24}},
  putt = {{0, "hat", 0.7, 16}, {0, "xylophone", 0.5, 12}},
  land = {{0, "basedrum", 0.6, 4}},
  green = {{0, "hat", 0.6, 14}, {70, "hat", 0.4, 18}},
  sand = {{0, "snare", 0.5, 4}, {40, "hat", 0.4, 8}},
  ob = {{0, "bass", 1, 10}, {150, "bass", 1, 6}, {300, "bass", 1, 2}},
  cup = {{0, "basedrum", 0.8, 14}, {80, "bell", 1, 19}, {200, "bell", 1, 24}},
  finish = {{0, "bell", 1, 16}, {140, "bell", 1, 19}},
  cheer = {{0, "bell", 1, 12}, {110, "bell", 1, 16}, {220, "bell", 1, 19}, {330, "bell", 1.2, 24},
    {520, "chime", 1, 24}, {640, "chime", 1, 24}},
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
