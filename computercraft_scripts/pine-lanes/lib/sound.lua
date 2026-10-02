-- Speaker cues for Pine Lanes. A cue is a list of {delayMs, instrument, volume, pitch}; play()
-- queues it and tick() (run every frame) sounds what is due, so audio never sleeps the event
-- loop. No speaker, or one that errors, is silence rather than a crash.
local Sound = {}
Sound.__index = Sound

local CUES = {
  start = {{0, "bell", 1, 12}, {110, "bell", 1, 16}, {220, "bell", 1, 19}, {330, "pling", 1, 24}},
  tick = {{0, "hat", 0.4, 20}},
  release = {{0, "basedrum", 0.7, 2}, {250, "basedrum", 0.4, 0}, {500, "basedrum", 0.4, 0},
    {750, "basedrum", 0.4, 0}, {1000, "basedrum", 0.4, 0}},
  crash = {{0, "basedrum", 1.2, 6}, {0, "snare", 1.2, 14}, {0, "hat", 1, 24}, {60, "snare", 1, 20},
    {110, "basedrum", 1, 4}},
  clack = {{0, "hat", 0.8, 22}, {0, "xylophone", 0.5, 24}},
  gutter = {{0, "bass", 0.9, 4}, {180, "bass", 0.9, 2}},
  miss = {{0, "hat", 0.5, 8}, {120, "bass", 0.6, 6}},
  strike = {{0, "basedrum", 1.2, 10}, {0, "bell", 1.2, 12}, {110, "bell", 1.2, 16}, {220, "bell", 1.2, 19},
    {330, "bell", 1.2, 24}, {520, "chime", 1, 24}},
  spare = {{0, "bell", 1, 16}, {110, "bell", 1, 19}, {220, "bell", 1.2, 24}},
  final = {{0, "bell", 1, 12}, {130, "bell", 1, 16}, {260, "bell", 1, 19}, {390, "bell", 1, 24},
    {650, "bell", 1, 19}, {780, "bell", 1.2, 24}},
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
