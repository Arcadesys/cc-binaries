-- Speaker cues for Pine Ball. A cue is a list of {delayMs, instrument, volume, pitch}; play()
-- queues it and tick() (run every frame) sounds what is due, so audio never sleeps the event
-- loop. No speaker, or one that errors, is silence rather than a crash.
local Sound = {}
Sound.__index = Sound

local CUES = {
  playball = {{0, "bell", 1, 12}, {130, "bell", 1, 16}, {260, "bell", 1, 19}, {420, "bell", 1.2, 24}},
  pitch = {{0, "hat", 0.5, 6}, {70, "hat", 0.4, 12}},
  swing = {{0, "snare", 0.6, 20}, {40, "hat", 0.5, 24}},
  hit_weak = {{0, "basedrum", 0.8, 6}},
  hit_good = {{0, "basedrum", 1, 10}, {0, "snare", 0.9, 18}},
  hit_perfect = {{0, "basedrum", 1.2, 12}, {0, "snare", 1.2, 22}, {40, "bell", 1, 24}},
  foul = {{0, "bit", 0.7, 8}, {90, "bit", 0.7, 4}},
  strike = {{0, "basedrum", 1, 4}, {0, "hat", 1, 20}},
  ball = {{0, "hat", 0.5, 14}, {0, "bass", 0.5, 8}},
  strikeout = {{0, "basedrum", 1, 6}, {0, "bass", 1, 10}, {150, "bass", 1, 6}, {300, "bass", 1, 2}},
  walk = {{0, "pling", 0.8, 12}, {100, "pling", 0.8, 16}},
  single = {{0, "xylophone", 1, 14}, {100, "xylophone", 1, 19}},
  double = {{0, "xylophone", 1, 14}, {90, "xylophone", 1, 17}, {180, "xylophone", 1, 21}},
  triple = {{0, "xylophone", 1, 14}, {90, "xylophone", 1, 17}, {180, "xylophone", 1, 21}, {270, "xylophone", 1, 24}},
  homerun = {{0, "bell", 1.2, 12}, {110, "bell", 1.2, 16}, {220, "bell", 1.2, 19}, {330, "bell", 1.2, 24},
    {330, "basedrum", 1.2, 8}, {520, "chime", 1, 24}, {640, "chime", 1, 24}, {760, "chime", 1, 24}},
  out = {{0, "bass", 1, 8}, {120, "bass", 1, 4}},
  run = {{0, "pling", 1, 19}, {90, "pling", 1, 24}},
  error = {{0, "bit", 0.8, 12}, {120, "bit", 0.8, 9}, {240, "bit", 0.8, 6}},
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
