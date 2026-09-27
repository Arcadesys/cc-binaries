local input={}
local lastPrimary=-1
local DEBOUNCE=.30
local function keyMap()
  local k=keys or {}
  local map={}
  local function bind(code,action) if code~=nil then map[code]=action end end
  bind(k.one,"select_position"); bind(k.two,"select_aim")
  bind(k.three,"select_power"); bind(k.four,"select_hook")
  bind(k.up,"select_prev"); bind(k.down,"select_next")
  bind(k.left,"adjust_down"); bind(k.right,"adjust_up")
  bind(k.space,"primary"); bind(k.tab,"view"); bind(k.f,"fine")
  bind(k.h,"help"); bind(k.p,"pause"); bind(k.s,"skip")
  bind(k.r,"restart"); bind(k.backspace,"quit")
  return map
end
local function hit(buttons,x,y)
  for i=1,#(buttons or {}) do
    local b=buttons[i]
    if x>=b.x and y>=b.y and x<b.x+b.w and y<b.y+b.h then return b.id end
  end
end
local function clock()
  if os and os.clock then return os.clock() end
  return 0
end
local function debounce(action,now)
  if action=="primary" or action=="roll" or action=="start" or action=="continue" then
    now=now or clock()
    if now-lastPrimary<DEBOUNCE then return nil end
    lastPrimary=now
  end
  return action
end
function input.action(event,buttons,monitorName)
  if type(event)~="table" then return nil end
  local name=event[1]
  if name=="key" then
    if event[3] then return nil end -- held/repeat events never retrigger a shot
    return debounce(keyMap()[event[2]],event.time)
  elseif name=="monitor_touch" then
    if not monitorName or event[2]~=monitorName then return nil end
    local action=hit(buttons,event[3],event[4])
    return debounce(action,event.time)
  elseif name=="mouse_click" then
    if monitorName then return nil end
    local action=hit(buttons,event[3],event[4])
    return debounce(action,event.time)
  end
  return nil
end
function input._resetDebounce() lastPrimary=-1 end
return input
