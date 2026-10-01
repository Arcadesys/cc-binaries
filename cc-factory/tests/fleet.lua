-- Fleet integration: unchanged production coordinator, worker and mining engine.
-- Each actor has a private Lua global environment, module cache, CC APIs,
-- inventory and disk. Physical blocks and a test-owned mutation log are shared.
local nativeFS,nativeSleep=fs,sleep
local sources={}
for _,dir in ipairs({'/src','/src/tests'}) do
 for _,name in ipairs(nativeFS.list(dir)) do
  if name:match('%.lua$') then local f=nativeFS.open(dir..'/'..name,'r');sources[name:gsub('%.lua$','')]=f.readAll();f.close() end
 end
end
local sim=assert(load(sources.simulator,'@simulator','t',_ENV))()
local function copy(v) return sim.copy(v) end
local function environment(id,clock)
 local env=setmetatable({},{__index=_ENV});env._G=env;env.package={loaded={}}
 env.os=setmetatable({clock=function() return clock.now end,epoch=function() return math.floor(clock.now*1000) end,
  getComputerID=function() return id end,getComputerLabel=function() return 'test-turtle-'..id end},{__index=os})
 env.require=function(name)
  if env.package.loaded[name]~=nil then return env.package.loaded[name] end
  local fn=assert(load(assert(sources[name],'Missing production module '..name),'@'..name,'t',env))
  local module=fn();env.package.loaded[name]=module or true;return env.package.loaded[name]
 end
 return env
end
local function samePosition(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
local function samePose(a,b) return a.x==b.x and a.y==b.y and a.z==b.z and a.facing==b.facing end
local function contains(bounds,p)
 for _,axis in ipairs({'x','y','z'}) do if p[axis]<bounds.min[axis] or p[axis]>bounds.max[axis] then return false end end
 return true
end
local function intersects(a,b)
 for _,axis in ipairs({'x','y','z'}) do if a.max[axis]<b.min[axis] or b.max[axis]<a.min[axis] then return false end end
 return true
end
local function job(name,x,heading)
 local home={x=x,y=64,z=0,facing=heading or 'north'}
 local zMin,zMax=heading=='south' and 0 or -8,heading=='south' and 8 or 0
 local cfg={mode='mine',job=name,dimension='minecraft:overworld',home=home,
  bounds={min={x=x-4,y=63,z=zMin},max={x=x+4,y=66,z=zMax}},length=6,branchInterval=3,branchLength=2,torchInterval=3,
  outputSide='down',supplySide='up',fuelMargin=8,torchReserve=1,fillReserve=8}
 return {config=cfg,footprint={min={x=x-5,y=63,z=zMin-1},max={x=x+5,y=66,z=zMax+1}}}
end
local function fixture(extraJobs)
 local f={clock={now=100},blocks={},actors={},permits={},actions={},messages={},faults={},serverFiles={},completed={},grants={}}
 f.jobs={left=job('left',0),right=job('right',30)}
 for name,entry in pairs(extraJobs or {}) do f.jobs[name]=copy(entry) end
 f.config={fleet='test-fleet',leaseSeconds=30,workers={
  [11]={home=copy(f.jobs.left.config.home),dimension='minecraft:overworld',bayBounds={min={x=-1,y=63,z=0},max={x=1,y=65,z=1}}},
  [12]={home=copy(f.jobs.right.config.home),dimension='minecraft:overworld',bayBounds={min={x=29,y=63,z=0},max={x=31,y=65,z=1}}}},jobs=copy(f.jobs)}
 local serverEnv=environment(1,f.clock);sim.new({env=serverEnv,files=f.serverFiles})
 f.store={record=false,fail=false,load=function() return copy(f.store.record) end,
  save=function(record) if f.store.fail then return false,'Injected durable save failure' end;f.store.record=copy(record);return true end}
 local module=serverEnv.require('lib_fleet_coordinator');f.serverModule=module;f.serverEnv=serverEnv
 local server,err=module.new(f.config,{store=f.store,clock=function() return f.clock.now end});assert(server,err);f.server=server
 function f.oracleReply(id,reply)
  if not reply then return end
  if reply.type=='ASSIGNED' or reply.type=='RENEWED' then
   local key=id..':'..reply.requestId;if f.grants[key] then return end;f.grants[key]=true
   local old=f.permits[id];local area=reply.footprint or (old and old.area) or f.jobs[reply.job].footprint
   local stored=f.server:snapshot().jobs[reply.job];assert(reply.leaseSeconds<=stored.deadline-f.clock.now+0.000001,'Grant TTL outlives durable owner deadline')
   local grant={job=reply.job,token=reply.token,generation=reply.generation,area=copy(area),expires=f.clock.now+reply.leaseSeconds}
   for other,permit in pairs(f.permits) do
    if other~=id and permit.expires>f.clock.now then assert(not intersects(grant.area,permit.area),'Coordinator issued overlapping active physical regions') end
   end
   f.permits[id]=grant
  elseif reply.type=='COMPLETED' then
   assert(not f.completed[reply.job],'Duplicate unique completion');f.completed[reply.job]=id;f.permits[id]=nil
  elseif reply.type=='QUARANTINED' or reply.type=='STOPPED' then f.permits[id]=nil end
 end
 function f.exchange(id,coordinator,message)
  assert(coordinator==1,'Worker sent to wrong coordinator')
  local sent=copy(message);f.messages[#f.messages+1]={sender=id,message=sent}
  local reply=f.server:handle(id,sent)
  f.oracleReply(id,reply)
  local fault=f.faults[id];f.faults[id]=nil
  if fault then return fault(1,copy(reply),sent) end
  return 1,copy(reply)
 end
 function f.actor(id)
  local home=f.config.workers[id].home;local env=environment(id,f.clock)
  local world=sim.new({env=env,pose=home,blocks=f.blocks})
  world.slots[1]={name='minecraft:coal',count=32};world.slots[2]={name='minecraft:torch',count=32};world.slots[3]={name='minecraft:cobblestone',count=64}
  world.set(world.target('down'),{name='minecraft:chest',capacity=100000,items={}})
  world.set(world.target('up'),{name='minecraft:chest',capacity=100000,items={['minecraft:coal']=16,['minecraft:torch']=64,['minecraft:cobblestone']=64}})
  local localJobs={};for name,entry in pairs(f.jobs) do localJobs[name]=copy(entry.config) end
  local config={fleet=f.config.fleet,coordinatorId=1,workerId=id,dimension='minecraft:overworld',home=copy(home),jobs=localJobs,workerCheckpointPrefix='fleet-worker-'}
  local transport={exchange=function(coordinator,message,timeout) return f.exchange(id,coordinator,message) end}
  local worker,err=env.require('lib_fleet_worker').new(config,{clock=function() return f.clock.now end,transport=transport});assert(worker,err)
  local actor={id=id,env=env,world=world,config=config,worker=worker,transport=transport}
  world.beforeMutation=function(name,target)
   local permit=assert(f.permits[id],'Native mutation without a coordinator owner permit: '..name)
   assert(permit.expires>f.clock.now,'Native mutation after lease expiry: '..name)
   assert(contains(permit.area,world.pose) and contains(permit.area,target),'Mutation outside independently granted footprint: '..name)
   if name:match('^dig') then assert(contains(f.jobs[permit.job].config.bounds,target),'Dig outside authorized job excavation bounds') end
   for other,peer in pairs(f.actors) do if other~=id then assert(not samePosition(target,peer.world.pose),'Native action collided with another turtle') end end
   f.actions[#f.actions+1]={worker=id,name=name,target=copy(target),pose=copy(world.pose),job=permit.job,time=f.clock.now}
   if f.afterMutation then f.afterMutation(actor,name,target) end
  end
  f.actors[id]=actor;return actor
 end
 function f.tick(actor) actor.worker:tick();f.clock.now=f.clock.now+0.01 end
 function f.run(actors,max)
  for tick=1,max or 1500 do
   for _,actor in ipairs(actors) do f.tick(actor) end
   f.server:tick()
   if tick%5==0 then nativeSleep(0) end
   if f.untilDone and f.untilDone() then return end
  end
 end
 return f
end
local passed,failed,report=0,0,{}
local function eq(a,b,msg) assert(a==b,(msg or 'Mismatch')..': expected '..tostring(b)..', got '..tostring(a)) end
local function test(name,fn)
 if _G.__SAFE_TEST_FILTER and not name:find(_G.__SAFE_TEST_FILTER,1,true) then return end
 nativeSleep(0);local ok,err=pcall(fn)
 if ok then passed=passed+1;report[#report+1]='PASS '..name else failed=failed+1;report[#report+1]='FAIL '..name..': '..tostring(err) end
 local f=assert(nativeFS.open('/results/progress.txt','w'));f.write(table.concat(report,'\n'));f.close()
end

-- Cases follow the final production protocol. No fake miner reports DONE.
test('isolated turtle environments share only physical world cells',function()
 local clock={now=1};local blocks={};local e1,e2=environment(11,clock),environment(12,clock)
 local a=sim.new({env=e1,blocks=blocks,pose={x=0,y=64,z=0,facing='north'}})
 local b=sim.new({env=e2,blocks=blocks,pose={x=30,y=64,z=0,facing='north'}})
 a.slots[1]={name='minecraft:coal',count=2};a.files['private']='left'
 eq(e1.turtle.getItemCount(1),2);eq(e2.turtle.getItemCount(1),0);eq(e2.fs.exists('private'),false)
 a.set({x=2,y=64,z=3},'minecraft:diamond_ore');eq(b.block({x=2,y=64,z=3}),'minecraft:diamond_ore')
 assert(e1.require('lib_safe_miner')~=e2.require('lib_safe_miner'),'Worker module caches shared')
end)

test('workers require local preflight before protocol or physical actions',function()
 local f=fixture();local a=f.actor(11);for _=1,5 do a.worker:tick() end
 eq(#a.world.calls,0);eq(#f.messages,0);eq(a.worker:state().status,'AWAITING_PREFLIGHT')
 assert(a.worker:confirmHome(true));eq(#a.world.calls,0)
end)
test('two actual mining engines complete disjoint assignments and safely idle',function()
 local f=fixture();local a,b=f.actor(11),f.actor(12);assert(a.worker:confirmHome(true));assert(b.worker:confirmHome(true))
 f.untilDone=function() return f.completed.left and f.completed.right end;f.run({a,b})
 eq(f.completed.left,11);eq(f.completed.right,12);assert(#f.actions>20,'No integrated physical mining')
 eq(a.world.drops,0);eq(b.world.drops,0);assert(samePose(a.world.pose,f.config.workers[11].home));assert(samePose(b.world.pose,f.config.workers[12].home))
 f.tick(a);f.tick(b);eq(a.worker:state().status,'WAIT');eq(b.worker:state().status,'WAIT')
end)
test('expired lease inside multi-action instruction blocks further native mutation',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a);f.tick(a)
 local expired=false
 a.world.afterAction=function(name) if not expired and name:match('^turn') then expired=true;f.clock.now=f.clock.now+31 end end
 for _=1,20 do f.tick(a);if expired then break end end;assert(expired,'No native multi-action scan reached: '..textutils.serialize(a.worker:state()));local actions=#a.world.calls
 for _=1,10 do f.tick(a) end
 eq(#a.world.calls,actions,'Native mutations continued after expiry');assert(a.worker:state().status=='NEEDS_HELP' or a.worker:state().status=='STOPPED')
end)
test('spoofed assignment sender never authorizes mining',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a)
 f.faults[11]=function(sender,reply) return 999,reply end;f.tick(a)
 eq(#a.world.calls,0);eq(a.worker:state().status,'NEEDS_HELP')
end)
test('uncorrelated or reordered assignment response never authorizes mining',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a)
 f.faults[11]=function(sender,reply) reply.requestId=reply.requestId-1;return sender,reply end;f.tick(a)
 eq(#a.world.calls,0);eq(a.worker:state().status,'NEEDS_HELP')
end)
test('lost assignment leaves occupied area reserved with no worker action',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a)
 f.faults[11]=function() return nil,nil end;f.tick(a);eq(#a.world.calls,0)
 f.clock.now=f.clock.now+31;f.server:tick()
 local message={type='request',fleet='test-fleet',workerId=11,requestId=a.worker.sequence+1,session=a.worker.session,eligibleJobs={'left'},home=a.config.home,dimension=a.config.dimension}
 local reply=f.server:handle(11,message);assert(reply.type~='ASSIGNED','Expired occupied area reassigned')
end)
for _,failure in ipairs({'full-output','low-fuel','unknown-block'}) do
 test('worker reports '..failure..' and never reports false completion',function()
  local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true))
  if failure=='full-output' then a.world.block(a.world.target('down')).capacity=0
  elseif failure=='low-fuel' then a.world.fuel=0;a.world.slots[1]=nil
  else a.world.set({x=0,y=64,z=-1},'mod:unknown_machine') end
  f.untilDone=function() local s=a.worker:state().status;return s=='NEEDS_HELP' or s=='STOPPED' end;f.run({a},400)
  assert(not f.completed.left,'Unsafe job falsely completed');local reported=false
  for _,msg in ipairs(f.messages) do if msg.message.type=='stop' then reported=true;assert(msg.message.result.phase~='DONE') end end
  assert(reported,'No coordinator stop report');eq(a.world.drops,0)
 end)
end

test('duplicate completion is idempotent and never produces second assignment',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.untilDone=function() return f.completed.left end;f.run({a})
 local completion;for _,message in ipairs(f.messages) do if message.message.type=='complete' then completion=message.message end end;assert(completion)
 local before=f.server:snapshot().jobs.left.generation
 for _=1,3 do local reply=f.server:handle(11,copy(completion));eq(reply.type,'COMPLETED') end
 eq(f.server:snapshot().jobs.left.generation,before);eq(f.completed.left,11)
end)
test('duplicate assignment replay has only remaining original lease time',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a);f.tick(a)
 local request=f.messages[#f.messages].message;local original=f.server:snapshot().jobs.left.deadline
 f.clock.now=f.clock.now+25;local reply=f.server:handle(11,copy(request));eq(reply.type,'ASSIGNED')
 assert(reply.leaseSeconds<=original-f.clock.now,'Duplicate replay extends ownership beyond original deadline')
 f.clock.now=original+0.01;local expired=f.server:handle(11,copy(request));assert(expired.type~='ASSIGNED','Expired grant replay accepted')
end)
test('reordered request and spoofed sender cannot alter durable owner',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a);f.tick(a)
 local request=copy(f.messages[#f.messages].message);local owner=f.server:snapshot().jobs.left.worker
 request.requestId=request.requestId-1;eq(f.server:handle(11,request).type,'REJECTED')
 request.requestId=request.requestId+20;eq(f.server:handle(12,request).type,'REJECTED')
 eq(f.server:snapshot().jobs.left.worker,owner)
end)
test('failed durable assignment save grants no physical permission',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a);f.store.fail=true;f.tick(a)
 eq(#a.world.calls,0);eq(a.worker:state().status,'NEEDS_HELP');assert(not f.permits[11])
end)
test('coordinator restart persists quarantine and changed epoch stops next action',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));for _=1,6 do f.tick(a) end
 local old=f.server:snapshot().epoch;local replacement,err=f.serverModule.new(f.config,{store=f.store,clock=function() return f.clock.now end});assert(replacement,err);f.server=replacement
 eq(f.server:snapshot().jobs.left.status,'QUARANTINED');assert(f.server:snapshot().epoch>old)
 local before=#a.world.calls;f.clock.now=a.worker.renewAt+0.1;f.tick(a)
 eq(#a.world.calls,before,'Changed coordinator epoch allowed another physical mutation');assert(a.worker:state().status=='NEEDS_HELP' or a.worker:state().status=='STOPPED')
 local durable=f.store.load();eq(durable.jobs.left.status,'QUARANTINED')
end)
test('worker restart after interrupted physical action requires reconciliation',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));f.tick(a);f.tick(a)
 local interrupted=false;a.world.afterAction=function(name) if name=='forward' then interrupted=true;error('Injected power loss after physical move') end end
 for _=1,20 do f.tick(a);if interrupted then break end end;assert(interrupted)
 a.world.afterAction=nil;local before=#a.world.calls
 local restarted,err=a.env.require('lib_fleet_worker').new(a.config,{clock=function() return f.clock.now end,transport=a.transport});assert(restarted,err)
 restarted:confirmHome(true);for _=1,5 do restarted:tick() end
 eq(#a.world.calls,before,'Restart automatically moved ambiguous turtle');assert(restarted:state().status=='NEEDS_HELP' or restarted:state().status=='STOPPED')
 local cp=a.env.require('lib_mining_checkpoint');local record,reason=cp.load(a.worker.ctx);assert(record==nil and reason,'Interrupted mining intent accepted')
end)
test('native fleet store readback survives clean reload and refuses staged corruption',function()
 local clock={now=1};local env=environment(1,clock);local disk=sim.new({env=env});local module=env.require('lib_fleet_store');local store=module.new('fleet.store')
 assert(store.save({version=1,epoch=7,jobs={left={status='QUARANTINED'}}}))
 local saved=assert(store.load());eq(saved.epoch,7);eq(saved.jobs.left.status,'QUARANTINED')
 disk.files['fleet.store.next']='interrupted';local record,err=store.load();assert(record==nil and err,'Staged write silently ignored')
end)

test('same-bay north then south jobs self-schedule beside another real worker',function()
 local f=fixture({south=job('south',0,'south')});local a,b=f.actor(11),f.actor(12);assert(a.worker:confirmHome(true));assert(b.worker:confirmHome(true))
 f.untilDone=function() return f.completed.left and f.completed.right and f.completed.south end;f.run({a,b})
 eq(f.completed.left,11);eq(f.completed.south,11,textutils.serialize(a.worker:state()));eq(f.completed.right,12)
 assert(samePose(a.world.pose,f.jobs.south.config.home),'Successor did not complete at exact south-facing home')
 local northDig,southDig={},{}
 for _,action in ipairs(f.actions) do if action.name:match('^dig') then local key=action.target.x..','..action.target.y..','..action.target.z
  if action.job=='left' then northDig[key]=true elseif action.job=='south' then assert(not northDig[key],'Successor dug retired north work cell');southDig[key]=true end
 end end
 assert(next(northDig) and next(southDig),'No real two-sided successor mining')
 local turns=0;for _,action in ipairs(f.actions) do if action.worker==11 and action.job=='south' and action.name:match('^turn') and samePosition(action.pose,f.jobs.south.config.home) then turns=turns+1 end end
 assert(turns>=2,'No checked known-home orientation change')
end)
for _,failure in ipairs({'expiry','power-loss'}) do
 test('known-home successor turn '..failure..' stops without further mutation',function()
  local f=fixture({south=job('south',0,'south')});local a=f.actor(11);assert(a.worker:confirmHome(true));f.untilDone=function() return f.completed.left end;f.run({a});assert(f.completed.left,'Initial job did not complete: '..textutils.serialize(a.worker:state()))
  local tripped=false
  a.world.afterAction=function(name)
   if not tripped and name:match('^turn') and a.worker.job=='south' then
    tripped=true
    if failure=='expiry' then f.clock.now=f.clock.now+31 else error('Injected power loss during home orientation') end
   end
  end
  for _=1,100 do f.tick(a);if tripped then break end end;assert(tripped,'No successor home turn reached: '..textutils.serialize(a.worker:state()))
  a.world.afterAction=nil;local before=#a.world.calls
  for _=1,10 do f.tick(a) end;eq(#a.world.calls,before,'Home orientation continued after losing safe authority')
  assert(a.worker:state().status=='NEEDS_HELP' or a.worker:state().status=='STOPPED')
  if failure=='power-loss' then
   local nextWorker,reason=a.env.require('lib_fleet_worker').new(a.config,{clock=function() return f.clock.now end,transport=a.transport})
   if nextWorker then assert(not nextWorker:confirmHome(true),'Uncertain home-turn checkpoint accepted') else assert(reason,'Missing reconciliation reason') end
   eq(#a.world.calls,before)
  end
 end)
end
test('lost heartbeat reply stops before any next physical action',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));for _=1,5 do f.tick(a) end
 f.clock.now=a.worker.renewAt+0.1;f.faults[11]=function() return nil,nil end;local before=#a.world.calls;f.tick(a)
 eq(#a.world.calls,before);assert(a.worker:state().status=='NEEDS_HELP' or a.worker:state().status=='STOPPED')
end)
test('unsolicited forged grant cannot replace a live permit or start idle worker',function()
 local f=fixture();local a=f.actor(11);local accepted=a.worker:receive(1,{type='ASSIGNED',fleet='test-fleet',job='left',token='spoof'})
 assert(not accepted);eq(#a.world.calls,0);eq(a.worker:state().status,'AWAITING_PREFLIGHT')
end)

test('documented serialized coordinator and worker examples are compatible',function()
 local env=environment(1,{now=100});sim.new({env=env});local configs={}
 for _,name in ipairs({'fleet-coordinator.config','fleet-worker-11.config','fleet-worker-12.config'}) do
  local file=assert(nativeFS.open('/src/examples/'..name,'r'));configs[name]=assert(textutils.unserialize(file.readAll()));file.close()
 end
 local store={record=false,load=function() return false end,save=function() return true end}
 local server,err=env.require('lib_fleet_coordinator').new(configs['fleet-coordinator.config'],{store=store,clock=function() return 100 end});assert(server,err)
 for _,id in ipairs({11,12}) do
  local config=configs['fleet-worker-'..id..'.config'];local workerEnv=environment(id,{now=100});sim.new({env=workerEnv,pose=config.home})
  local worker,why=workerEnv.require('lib_fleet_worker').new(config,{clock=function() return 100 end,transport={exchange=function() return nil,nil end}});assert(worker,why)
  for name,c in pairs(config.jobs) do
   local other=configs['fleet-coordinator.config'].jobs[name].config
   local function equal(a,b) if type(a)~=type(b) then return false end;if type(a)~='table' then return a==b end;for k,v in pairs(a) do if not equal(v,b[k]) then return false end end;for k in pairs(b) do if a[k]==nil then return false end end;return true end
   assert(equal(c,other),'Example catalogs disagree')
  end
  assert(worker:state().status=='AWAITING_PREFLIGHT')
 end
end)
test('native worker and coordinator adapters agree on default Rednet protocol',function()
 local f=fixture();local a=f.actor(11);local env=a.env;env.__FLEET_WORKER_EMBED__=true
 local cfg=copy(a.config);cfg.modemSide='left';cfg.protocol=nil;a.world.files['worker.config']=textutils.serialize(cfg)
 local coordinatorEnv=environment(1,f.clock);coordinatorEnv.__FLEET_EMBED__=true;sim.new({env=coordinatorEnv})
 local expected=coordinatorEnv.require('fleet_coordinator').protocol
 local pending,protocols={},{}
 env.peripheral.hasType=(function(original) return function(side,kind) if side=='left' and kind=='modem' then return true end;return original(side,kind) end end)(env.peripheral.hasType)
 env.rednet={open=function() end,close=function() end,
  send=function(target,msg,protocol) eq(protocol,expected);protocols[#protocols+1]=protocol;local sender,reply=f.exchange(11,target,msg);pending={sender,reply} end,
  receive=function(protocol) eq(protocol,expected);local p=pending;pending={};return p[1],p[2] end}
 local events={{'key',keys.enter},{'timer',42},{'key',keys.pageDown},{'timer',42},{'timer',42},{'key',keys.q},{'key',keys.q}}
 local index=0;env.os.startTimer=function() return 42 end;env.os.pullEvent=function() index=index+1;local event=assert(events[index],'Unexpected adapter event');return event[1],event[2] end
 local worker=env.require('fleet_worker').run({'worker.config'});assert(worker);eq(worker:state().status,'STOPPED');assert(#protocols>=3)
 local register,request,stop=false,false,false;for _,m in ipairs(f.messages) do register=register or m.message.type=='register';request=request or m.message.type=='request';stop=stop or m.message.type=='stop' end
 assert(register and request and stop,'Native adapter did not execute real protocol lifecycle')
end)
test('native coordinator adapter ignores wrong protocol and answers matching worker',function()
 local f=fixture();local env=f.serverEnv;env.__FLEET_EMBED__=true;f.serverFiles['coordinator.config']=textutils.serialize(f.config)
 env.peripheral.getNames=function() return {'left'} end;env.peripheral.hasType=function(side,kind) return side=='left' and kind=='modem' end
 local sent={};env.rednet={open=function() end,send=function(target,msg,protocol) sent[#sent+1]={target=target,msg=msg,protocol=protocol} end}
 local module=env.require('fleet_coordinator');local request={fleet='test-fleet',type='register',workerId=11,requestId=10001,home=f.config.workers[11].home,dimension='minecraft:overworld'}
 local events={{'rednet_message',11,request,'wrong-protocol'},{'rednet_message',11,request,module.protocol},{'key',keys.q}}
 local index=0;env.os.startTimer=function() return 42 end;env.os.pullEvent=function() index=index+1;local event=assert(events[index],'Unexpected coordinator adapter event');return unpack(event) end
 assert(module.run({'coordinator.config'}));eq(#sent,1);eq(sent[1].msg.type,'REGISTERED');eq(sent[1].protocol,'cc-safe-mining-fleet-v1')
end)
test('regressed monotonic worker clock blocks next mutation',function()
 local f=fixture();local a=f.actor(11);assert(a.worker:confirmHome(true));for _=1,5 do f.tick(a) end
 local before=#a.world.calls;f.clock.now=f.clock.now-5;a.worker:tick();eq(#a.world.calls,before);eq(a.worker:state().status,'NEEDS_HELP')
end)

test('catalog rejects overlapping excavation even at same authorized bay',function()
 local f=fixture();local cfg=copy(f.config);cfg.jobs.overlap=copy(cfg.jobs.left);cfg.jobs.overlap.config.job='overlap'
 local store={load=function() return false end,save=function() return true end}
 local server,err=f.serverModule.new(cfg,{store=store,clock=function() return f.clock.now end});assert(not server and err,'Overlapping planned work authorized')
end)
test('catalog rejects planned work crossing another registered bay',function()
 local f=fixture();local cfg=copy(f.config);cfg.jobs.right=nil
 cfg.workers[12].home={x=2,y=64,z=-3,facing='north'}
 cfg.workers[12].bayBounds={min={x=2,y=63,z=-3},max={x=2,y=65,z=-3}}
 local store={load=function() return false end,save=function() return true end}
 local server,err=f.serverModule.new(cfg,{store=store,clock=function() return f.clock.now end});assert(not server and err,'Planned excavation crosses foreign home/storage')
end)

local summary=(failed==0 and passed>0 and 'PASS all ' or 'FAIL summary ')..passed..' passed, '..failed..' failed'
report[#report+1]=summary
local out=assert(nativeFS.open('/results/tests.txt','w'));out.write(table.concat(report,'\n')..'\n');out.close()
if failed>0 or passed==0 then error(failed..' fleet test failures') end
