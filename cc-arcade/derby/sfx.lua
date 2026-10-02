-- Race-day sound for the display and the betting station. Notes go through casino.sound,
-- which holds them until the frame loop plays them, so sound never sleeps the event loop.
-- Times are milliseconds on os.epoch('utc'); the caller passes `now` and ticks the queue.
local M={}
local GALLOP=450
local PLACES={24,19,14}
function M.new(sound)
 local self={sound=sound or require('casino.sound')(),phase=nil,second=nil,placed=0,gallopAt=0}
 local function note(at,instrument,volume,pitch) self.sound:play(at,instrument,volume,pitch) end
 -- The display calls this with every snapshot. Joining mid-race stays quiet until a
 -- phase change is actually seen, so only real starts and finishes get fanfares.
 function self:hear(v,now)
  local phase=v.phase
  if phase~=self.phase then
   local was=self.phase
   if phase=='RUNNING' and was=='LOCKED' then
    for i,p in ipairs({12,16,19,24}) do note(now+(i-1)*90,'bell',1.2,p) end
    note(now,'snare',1.2,12); note(now,'basedrum',1.2,8)
    self.gallopAt=now+500
   elseif phase=='RESULT' and was=='RUNNING' then
    for i,p in ipairs({12,16,19,24,19,24}) do note(now+400+(i-1)*130,'bell',1,p) end
    note(now+1100,'chime',1,24)
   elseif phase=='CANCELLED' then
    note(now,'bass',1,8); note(now+150,'bass',1,4); note(now+300,'bass',1,0)
   end
   self.phase=phase; self.second=nil; self.placed=#(v.order or {})
  end
  if phase=='LOCKED' and v.seconds and v.seconds>0 and v.seconds~=self.second then
   self.second=v.seconds
   if v.seconds<=3 then note(now,'pling',1,12+(3-v.seconds)*4) else note(now,'hat',.6,18) end
  end
  if phase=='RUNNING' then
   if now>=self.gallopAt then
    self.gallopAt=now+GALLOP
    note(now,'basedrum',.6,3); note(now+110,'hat',.5,10); note(now+220,'hat',.5,10)
   end
   local order=v.order or {}
   while self.placed<#order do
    self.placed=self.placed+1
    note(now,'bell',1.2,PLACES[self.placed] or 12); note(now,'snare',.8,16)
   end
  end
  self.sound:tick(now)
 end
 -- Betting station feedback.
 function self:move(now) note(now,'hat',.4,20); self.sound:tick(now) end
 function self:ticket(accepted,now)
  if accepted then note(now,'bell',1,12); note(now+100,'bell',1,16); note(now+200,'bell',1,19)
  else note(now,'bass',1,6); note(now+120,'bass',1,3) end
  self.sound:tick(now)
 end
 function self:tick(now) self.sound:tick(now) end
 return self
end
return M
