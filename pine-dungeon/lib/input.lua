local input={}
local function keysFor()
  local k=keys or {}
  local m={}
  local function add(code,action) if code then m[code]=action end end
  add(k.up,"north");add(k.w,"north")
  add(k.down,"south");add(k.s,"south")
  add(k.left,"west");add(k.a,"west")
  add(k.right,"east");add(k.d,"east")
  add(k.space,"attack");add(k.h,"heal")
  add(k.period,"wait");add(k.enter,"wait")
  add(k.tab,"map");add(k.p,"menu")
  add(k.f1,"help");add(k.r,"new");add(k.q,"quit")
  return m
end
local function hit(buttons,x,y)
  for _,b in ipairs(buttons or {}) do
    if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then return b.id end
  end
end
function input.action(event,buttons,monitorName)
  if type(event)~="table" then return nil end
  if event[1]=="key" then
    if event[3] then return nil end
    return keysFor()[event[2]]
  elseif event[1]=="monitor_touch" then
    if not monitorName or event[2]~=monitorName then return nil end
    return hit(buttons,event[3],event[4])
  elseif event[1]=="mouse_click" then
    if monitorName then return nil end
    return hit(buttons,event[3],event[4])
  end
end
return input
