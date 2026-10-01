local config=require('derby.config')
local store=require('derby.store')
local M={protocol='pine-derby-house-v1'}
function M.new(c)
 c=c or config.read(); config.network(c); assert(c.host,'Host ID missing')
 local db=store.open('/house-client/state',{counter=0,bindings={},rounds={}})
 local state=db:get(); local api={config=c}
 function api:localState() return store.copy(state) end
 function api:saveLocal(s) db:save(s); state=s end
 local function transport(q)
  local token=tostring(os.getComputerID())..':'..tostring(os.epoch('utc'))..':'..tostring(math.random(1,999999))
  rednet.send(c.host,{token=token,request=q},M.protocol)
  local timer=os.startTimer(2)
  while true do
   local e,a,b,p=os.pullEvent()
   if e=='timer' and a==timer then return {ok=false,error='House offline; request retained for retry',offline=true} end
   if e=='rednet_message' and a==c.host and p==M.protocol and type(b)=='table' and b.token==token and type(b.result)=='table' then os.cancelTimer(timer); return b.result end
  end
 end
 function api:read(q) return transport(q) end
 local function deliver(q)
  local r=transport(q)
  if not r.offline and not r.pending then state.pending=nil; state.last={request=q,result=r}; db:save(state) end
  if r.pending then return {ok=false,error='Cashier transfer pending reconciliation',pending=true} end
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
