-- A seat terminal: reports its card, draws the table's view, sends button presses.
-- Holds no money and no game rules, so a seat never needs updating for a new game.
local net=require('tables.net')
local view=require('tables.view')
local M={}
-- o: send(msg) to the table, card() -> inserted card or nil, now() in seconds
function M.new(o)
 local s={seq=0,heard=-math.huge}
 function s:hello()
  local c=o.card()
  o.send({t='hello',card=c and {account=c.account,diskID=c.diskID} or nil})
 end
 function s:receive(msg)
  if msg.t~='view' or type(msg.view)~='table' then return false end
  s.heard=o.now(); s.seq=msg.seq; s.view=msg.view; return true
 end
 function s:connected() return s.view~=nil and o.now()-s.heard<=net.TIMEOUT end
 function s:current()
  if s:connected() then return s.view end
  return {title='TABLE SEAT',status='Connecting to table #'..tostring(o.table)..'...',lines={'Waiting for the table computer.'},buttons={},footer='Q: quit'}
 end
 function s:press(id)
  if not s:connected() then return false end
  for _,b in ipairs(s.view.buttons or {}) do
   if b.id==id then o.send({t='press',seq=s.seq,button=id}); return true end
  end
  return false
 end
 return s
end
-- script (optional) runs alongside the seat with the seat object; used by tests.
function M.run(c,script)
 local link=net.open(c)
 local monitor=peripheral.find('monitor')
 local t=monitor or term.current()
 if monitor then monitor.setTextScale(1) end
 local card=require('derby.ui').card
 local s=M.new({table=c.table,card=card,now=function() return os.epoch('utc')/1000 end,
  send=function(msg) link.send(c.table,msg) end})
 local function loop()
  local timer=os.startTimer(0)
  while true do
   local e,a,b,p=os.pullEvent()
   local from,msg=link.parse(e,a,b,p)
   if from==c.table then s:receive(msg)
   elseif e=='timer' and a==timer then s:hello(); timer=os.startTimer(net.HEARTBEAT)
   elseif e=='disk' or e=='disk_eject' then s:hello()
   elseif e=='mouse_click' or e=='monitor_touch' then
    local hit=view.hit(t,s:current(),p); if hit then s:press(hit.id) end
   elseif e=='key' then
    if a==keys.q and not script then return end
    local n=a-keys.one+1
    local buttons=s:current().buttons or {}
    if buttons[n] then s:press(buttons[n].id) elseif a==keys.enter and buttons[1] then s:press(buttons[1].id) end
   end
   if t.isColor() then view.draw(t,s:current()) end
  end
 end
 if script then parallel.waitForAny(loop,function() script(s) end) else loop() end
 return s
end
return M
