-- Held keys become a movement mask; other keys and taps become one-shot commands.
-- Touch can't hold, so a tapped movement button pulses its bit for a few ticks.
local world=require("lib.world")
local input={}
local Input={};Input.__index=Input
local PULSE={[world.FWD]=4,[world.BACK]=3,[world.LEFT]=2,[world.RIGHT]=2,[world.FIRE]=1}
local function holdKeys()
  local k=keys or {}
  local m={}
  local function add(code,b) if code then m[code]=b end end
  add(k.up,world.FWD);add(k.w,world.FWD)
  add(k.down,world.BACK);add(k.s,world.BACK)
  add(k.left,world.LEFT);add(k.a,world.LEFT)
  add(k.right,world.RIGHT);add(k.d,world.RIGHT)
  add(k.space,world.FIRE);add(k.leftCtrl,world.FIRE)
  return m
end
local function commandKeys()
  local k=keys or {}
  local m={}
  local function add(code,c) if code then m[code]=c end end
  add(k.enter,"start");add(k.numPadEnter,"start");add(k.r,"retry")
  add(k.f1,"help");add(k.h,"help");add(k.tab,"scores");add(k.p,"menu");add(k.q,"quit")
  return m
end
input.buttonBits={fwd=world.FWD,back=world.BACK,left=world.LEFT,right=world.RIGHT,fire=world.FIRE}
function input.new()
  return setmetatable({held={},pulses={},holds=holdKeys(),commands=commandKeys()},Input)
end
local function hit(buttons,x,y)
  for _,b in ipairs(buttons or {}) do
    if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then return b.id end
  end
end
input.hit=hit
-- Returns a command string, "held" when the mask changed, or nil.
function Input:event(event,buttons,monitorName)
  if type(event)~="table" then return nil end
  local kind=event[1]
  if kind=="key" then
    local b=self.holds[event[2]]
    if b then
      if self.held[b]==nil then self.held[b]={} end
      local was=next(self.held[b])~=nil
      self.held[b][event[2]]=true
      return not was and "held" or nil
    end
    if event[3] then return nil end
    return self.commands[event[2]]
  elseif kind=="key_up" then
    local b=self.holds[event[2]]
    if b and self.held[b] then
      self.held[b][event[2]]=nil
      if next(self.held[b])==nil then return "held" end
    end
    return nil
  end
  local id
  if kind=="monitor_touch" then
    if not monitorName or event[2]~=monitorName then return nil end
    id=hit(buttons,event[3],event[4])
  elseif kind=="mouse_click" then
    if monitorName then return nil end
    id=hit(buttons,event[3],event[4])
  end
  if not id then return nil end
  local b=input.buttonBits[id]
  if b then self.pulses[b]=PULSE[b];return "held" end
  return id
end
function Input:mask()
  local m=0
  for b in pairs(PULSE) do
    if (self.held[b] and next(self.held[b])) or (self.pulses[b] or 0)>0 then m=m+b end
  end
  return m
end
-- Call once per game tick after reading the mask.
function Input:decay()
  for b,n in pairs(self.pulses) do self.pulses[b]=n>1 and n-1 or nil end
end
function Input:clear() self.held={};self.pulses={} end
return input
