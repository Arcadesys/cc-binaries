-- Deterministic virtual CC computers. Production client, server, service, ledger,
-- config and two-slot store are loaded unchanged in independent environments.
local platform = require('tests.support.platform')
local M = {}
local function copy(v)
 if type(v) ~= 'table' then return v end
 local out = {}; for k,x in pairs(v) do out[copy(k)] = copy(x) end; return out
end
function M.new()
 local hub = {nodes={}, packets={}, trace={}, now=0, serial=0, hook=nil}
 local function inventory(count)
  local inv={count=count,moves=0}
  inv.list=function() return inv.count>0 and {[1]={name='minecraft:diamond',count=inv.count}} or {} end
  inv.getItemDetail=function() return {name='minecraft:diamond',count=inv.count} end
  inv.pushItems=function(destination,_,amount)
   inv.moves=inv.moves+1
   local target=assert(hub.inventories[destination]); local moved=math.min(inv.count,amount,target.capacity or amount)
   inv.count=inv.count-moved; target.count=target.count+moved
   if inv.failAfterMove then error('Simulated unplug after movement') end
   return moved
  end
  return inv
 end
 hub.inventories={bank=inventory(1000),intake=inventory(1000),output=inventory(0)}
 local function resume(node,...)
  assert(node.co and coroutine.status(node.co)~='dead','Computer '..node.id..' is not awaiting an event')
  local ok,result=coroutine.resume(node.co,...)
  assert(ok,'Computer '..node.id..': '..tostring(result))
  if coroutine.status(node.co)=='dead' then node.result=result; node.finished=true end
 end
 function hub:computer(id,files)
  local p=platform.new({files=files or {}})
  local node={id=id,platform=p,files=p.files,timers={},modules={},finished=false}
  self.nodes[id]=node
  local env=setmetatable({fs=p.fs,textutils=p.textutils},{__index=_G}); env._G=env
  node.env=env
  local randomState=id+1
  env.math=setmetatable({random=function(low,high)
   randomState=(randomState*48271)%2147483647
   if low==nil then return randomState/2147483647 end
   if high==nil then high=low; low=1 end
   return low+randomState%(high-low+1)
  end},{__index=math})
  local noop=function() end
  local terminal=setmetatable({getSize=function() return 51,19 end},{__index=function() return noop end})
  env.term={current=function() return terminal end}
  env.colors={yellow=16,white=1,black=32768,blue=2048}
  env.keys={q=16,p=25,c=46,f=33,r=19,u=22}
  env.os={getComputerID=function() return id end,epoch=function() return math.floor(hub.now*1000) end,
   startTimer=function(seconds) hub.serial=hub.serial+1; node.timers[hub.serial]=hub.now+seconds; return hub.serial end,
   cancelTimer=function(timer) node.timers[timer]=nil end,
   pullEvent=function() return coroutine.yield() end}
  env.os.pullEventRaw=env.os.pullEvent
  env.peripheral={wrap=function(name)
   if name=='wired' then return {isWireless=function() return false end} end
   return hub.inventories[name]
  end}
  env.rednet={open=noop,send=function(to,message,protocol)
   -- Serialization round trip prevents sender and recipient sharing table references.
   local packet={from=id,to=to,message=p.textutils.unserializeJSON(p.textutils.serializeJSON(message)),protocol=protocol}
   hub.trace[#hub.trace+1]=copy(packet)
   local deliveries
   if hub.hook then deliveries=hub.hook(copy(packet)) end
   if deliveries==false then return true end
   for _,item in ipairs(deliveries or {packet}) do hub.packets[#hub.packets+1]=item end
   return true
  end}
  function env.require(name)
   if node.modules[name]~=nil then return node.modules[name] end
   -- Presentation only: no renderer/terminal access is needed for wire tests.
   if name=='derby.ui' then node.modules[name]={clear=noop,line=noop}; return node.modules[name] end
   local path=name:gsub('%.','/')..'.lua'
   local fn,err=loadfile(path,'t',env); assert(fn,err)
   local value=fn(); node.modules[name]=value==nil and true or value; return node.modules[name]
  end
  node.require=env.require
  return node
 end
 function hub:startHost(files)
  local node=self:computer(1,files)
  self.roles=self.roles or {['2']='cashier',['3']='station',['4']='station',['5']='display'}
  local config={modem='wired',clients=self.roles,bank='bank',intake='intake',payout='output'}
  if not files then
   local state=node.require('derby.house').new(node.require('derby.odds'))
   state.bank=1000; state.accounts['house-1']={name='Fixture Guest',balance=100}; state.nextAccount=1
   node.require('derby.store').open('/house-bank/state',state):save(state)
  end
  node.co=coroutine.create(function() node.require('derby.server').run(config) end)
  resume(node); self.host=node; return node
 end
 function hub:client(id,files)
  local node=self:computer(id,files)
  node.client=node.require('derby.client').new({modem='wired',host=1})
  return node
 end
 function hub:task(node,fn)
  node.finished=false; node.result=nil; node.co=coroutine.create(fn)
  resume(node); return node
 end
 function hub:start(node,method,q)
  return self:task(node,function() return node.client[method](node.client,q) end)
 end
 function hub:deliver(packet)
  local node=self.nodes[packet.to]
  if node and node.co and coroutine.status(node.co)~='dead' then
   resume(node,'rednet_message',packet.from,copy(packet.message),packet.protocol)
  end
 end
 function hub:pump()
  local count=0
  while #self.packets>0 do
   count=count+1; assert(count<1000,'Router failed to quiesce')
   self:deliver(table.remove(self.packets,1))
  end
 end
 function hub:timeout(node)
  local soonest,id
  for timer,at in pairs(node.timers) do if not soonest or at<soonest then soonest,id=at,timer end end
  assert(id,'No outstanding timer'); self.now=math.max(self.now,soonest); node.timers[id]=nil; resume(node,'timer',id)
 end
 function hub:call(node,method,q)
  self:start(node,method,q); self:pump()
  if not node.finished then self:timeout(node); self:pump() end
  assert(node.finished,'Request did not complete'); return node.result
 end
 function hub:state()
  return self.host.require('derby.store').open('/house-bank/state',{}):get()
 end
 function hub:restartHost() return self:startHost(self.host.files) end
 function hub:restartClient(node) return self:client(node.id,node.files) end
 function hub:operator(key)
  resume(self.host,'key',self.host.env.keys[key])
 end
 hub:startHost()
 return hub
end
return M
