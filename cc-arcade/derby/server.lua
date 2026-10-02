local config=require('derby.config')
local store=require('derby.store')
local house=require('derby.house')
local service=require('derby.service')
local ledger=require('derby.ledger')
local ui=require('derby.ui')
local M={}
function M.run(c)
 config.network(c)
 local initial=house.new(require('derby.odds')); initial.paused=true
 local db=store.open('/house-bank/state',initial)
 local host=service.new(db,c,peripheral.wrap)
 local t=term.current(); local message='P: start after live acceptance. F: recognise funded bank.'
 local function draw()
  local s=host:state(); ui.clear(t,'HOUSE HOST | ID '..os.getComputerID())
  ui.line(t,3,' Bank: '..s.bank..' credits backing | Available: '..ledger.available(s))
  ui.line(t,5,' '..(s.paused and 'PAUSED' or 'RUNNING')..' | '..(s.race and s.race.id..' '..s.race.phase or 'Awaiting first race'))
  ui.line(t,7,' [P] Pause/start  [C] Cancel unstarted race')
  ui.line(t,9,' [F] Recognise added stock  [M] Apply currency config')
  ui.line(t,11,' [R] Reconcile transfer  [U] Refund interrupted game')
  local y=13
  for id,p in pairs(s.pending) do ui.line(t,y,' PENDING '..id..' '..p.kind..' '..tostring(p.requestedItems or p.amount)); y=y+1 end
  for id,r in pairs(s.rounds) do if r.status=='open' and r.game~='derby' then ui.line(t,y,' OPEN '..id..' '..r.game); y=y+1 end end
  local _,h=t.getSize(); ui.line(t,h-1,message,colors.yellow); ui.line(t,h,' [Q] Stop host (all clients go offline)')
 end
 local timer=os.startTimer(.1); draw()
 while true do
  local e,a,b,p=os.pullEvent()
  if e=='timer' and a==timer then
   host:tick(os.epoch('utc')%2147483646); timer=os.startTimer(.1); draw()
  elseif e=='rednet_message' and p=='pine-derby-house-v1' and type(b)=='table' and type(b.token)=='string' then
   local role=c.clients[tostring(a)]
   local result=role and host:request(b.request,role,a) or {ok=false,error='Computer not registered at house host'}
   rednet.send(a,{token=b.token,result=result},p)
  elseif e=='key' then
   local result
   if a==keys.q then return
   elseif a==keys.p then result=host:operator('pause')
   elseif a==keys.c then result=host:operator('cancel')
   elseif a==keys.m then result=host:operator('currency')
   elseif a==keys.f then result=host:operator('fund')
   elseif a==keys.r or a==keys.u then
    t.setCursorPos(1,15); t.clearLine(); write(a==keys.r and 'Transaction ID: ' or 'Round ID: '); local id=read()
    if a==keys.r then write('Verified items actually moved: '); result=host:operator('reconcile',id,tonumber(read()))
    else result=host:operator('refund',id) end
   end
   if result then message=result.ok and 'Saved and verified' or result.error; draw() end
  end
 end
end
return M
