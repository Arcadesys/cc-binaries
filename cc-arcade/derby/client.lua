local config=require('derby.config')
local store=require('derby.store')
local M={protocol='pine-derby-house-v1'}
local function pack(...) return {n=select('#',...),...} end
local unpack=table.unpack or unpack
function M.new(c,options)
 c=c or config.read(); config.network(c); assert(c.host,'Host ID missing')
 local db=store.open('/house-client/state',{counter=0,bindings={},rounds={}})
 local state=db:get(); local api={config=c}
 function api:localState() return store.copy(state) end
 function api:saveLocal(s) db:save(s); state=s end
 -- options.keepEvents: put back the keys, touches and timers that arrive while waiting
 -- for the host, so a screen's own loop still sees them. Off by default for the wallet.
 local keep=options and options.keepEvents
 local function transport(q)
  local token=tostring(os.getComputerID())..':'..tostring(os.epoch('utc'))..':'..tostring(math.random(1,999999))
  rednet.send(c.host,{token=token,request=q},M.protocol)
  local timer=os.startTimer(2)
  local held={}
  local function finish(result)
   for _,e in ipairs(held) do os.queueEvent(unpack(e,1,e.n)) end
   return result
  end
  while true do
   local e=pack(os.pullEvent())
   local name,a,b,p=e[1],e[2],e[3],e[4]
   if name=='timer' and a==timer then return finish({ok=false,error='House offline',offline=true}) end
   if name=='rednet_message' and a==c.host and p==M.protocol and type(b)=='table' and b.token==token and type(b.result)=='table' then os.cancelTimer(timer); return finish(b.result) end
   -- Stale house replies and raw modem packets are never wanted again.
   if keep and name~='modem_message' and not (name=='rednet_message' and p==M.protocol) then held[#held+1]=e end
  end
 end
 function api:read(q) return transport(q) end
 local function deliver(q)
  local r=transport(q)
  if not r.offline and not r.pending then state.pending=nil; state.last={request=q,result=r}; db:save(state) end
  if r.pending then return {ok=false,error='Cashier transfer pending reconciliation',pending=true} end
  if r.offline then return {ok=false,error='House offline; request kept for retry',offline=true} end
  return r
 end
 function api:retry()
  if not state.pending then return state.last and state.last.result or {ok=false,error='No pending request'} end
  return deliver(state.pending)
 end
 function api:mutate(q)
  if state.pending then return {ok=false,error='Unacknowledged request: press R to retry before another action',pending=true} end
  state.counter=state.counter+1; q.id=tostring(os.getComputerID())..':'..state.counter
  state.pending=store.copy(q); db:save(state)
  return deliver(q)
 end
 return api
end
return M
