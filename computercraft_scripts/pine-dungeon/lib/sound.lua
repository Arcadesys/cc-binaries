-- Speaker cues for Pine Dungeon. A cue is a list of {delayMs, instrument, volume, pitch}; play()
-- queues it and tick() (run every frame) sounds what is due, so audio never sleeps the event
-- loop. No speaker, or one that errors, is silence rather than a crash.
local Sound = {}
Sound.__index = Sound

local CUES = {
  start = {{0, "pling", 0.9, 12}, {120, "pling", 0.9, 16}, {240, "pling", 0.9, 19}},
  step = {{0, "basedrum", 0.35, 0}},
  turn = {{0, "hat", 0.3, 16}},
  blocked = {{0, "bass", 0.6, 4}},
  hit = {{0, "snare", 0.9, 10}, {0, "basedrum", 0.8, 6}},
  whiff = {{0, "hat", 0.5, 22}, {40, "hat", 0.3, 24}},
  kill = {{0, "snare", 1, 10}, {0, "basedrum", 1, 6}, {90, "bell", 0.8, 19}},
  hurt = {{0, "bass", 1, 2}, {0, "snare", 0.8, 4}},
  boom = {{0, "didgeridoo", 1.5, 0}, {0, "basedrum", 1.5, 0}, {0, "bass", 1.5, 0}, {100, "didgeridoo", 1.2, 2}},
  warn = {{0, "cow_bell", 1, 18}, {200, "cow_bell", 1, 18}},
  roar = {{0, "didgeridoo", 1.5, 4}, {200, "didgeridoo", 1.5, 1}, {400, "didgeridoo", 1.2, 0}},
  coin = {{0, "pling", 0.8, 19}, {80, "pling", 0.8, 24}},
  steak = {{0, "bit", 0.7, 14}, {80, "bit", 0.7, 18}},
  heal = {{0, "harp", 0.9, 14}, {100, "harp", 0.9, 19}, {200, "harp", 0.9, 23}},
  descend = {{0, "bass", 0.9, 12}, {150, "bass", 0.9, 8}, {300, "bass", 0.9, 4}},
  champion = {{0, "bell", 1.2, 12}, {110, "bell", 1.2, 16}, {220, "bell", 1.2, 19}, {330, "bell", 1.2, 24},
    {520, "chime", 1, 24}},
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
