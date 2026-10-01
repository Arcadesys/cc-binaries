local realFS,realTerm,nativeSleep=fs,term,sleep
-- Load unchanged source before installing the virtual filesystem. CC shell
-- programs normally get cc.require; this loader keeps that cache contract.
local sources={}
for _,dir in ipairs({'/src','/src/tests'}) do
 for _,name in ipairs(realFS.list(dir)) do
  if name:match('%.lua$') then local f=realFS.open(dir..'/'..name,'r');sources[name:gsub('%.lua$','')]=f.readAll();f.close() end
 end
end
package={loaded={}}
function require(name)
 if package.loaded[name]~=nil then return package.loaded[name] end
 local source=assert(sources[name],'Module missing: '..name)
 local fn=assert(load(source,'@'..name,'t',_ENV));local result=fn();package.loaded[name]=result or true;return package.loaded[name]
end
local sim=require('simulator')
local report={};local passed,failed,testIndex=0,0,0
local function eq(a,b,msg) assert(a==b,(msg or 'Mismatch')..': expected '..tostring(b)..', got '..tostring(a)) end
local function test(name,fn)
 testIndex=testIndex+1
 local part=_G.__SAFE_TEST_PART
 if part and (testIndex-1)%part.total~=part.index-1 then return end
 if _G.__SAFE_TEST_FILTER and not name:find(_G.__SAFE_TEST_FILTER,1,true) then return end
 local marker=realFS.open('/results/running.txt','w');marker.write(name);marker.close()
 nativeSleep(0)
 local ok,err=pcall(fn)
 if ok then passed=passed+1;report[#report+1]='PASS '..name else failed=failed+1;report[#report+1]='FAIL '..name..': '..tostring(err) end
 local f=assert(realFS.open('/results/progress.txt','w'));f.write(table.concat(report,'\n'));f.close()
end
local function fresh(opts)
 opts=opts or {};opts.env=_ENV
 local w=sim.new(opts)
 turtle=w.turtle;fs=w.env.fs;peripheral=w.env.peripheral;sleep=w.env.sleep
 for name in pairs(package.loaded) do if name:match('^lib_') or name:match('^state_') then package.loaded[name]=nil end end
 return w
end
local function config(heading)
 return {mode='mine',job='tiny',home={x=0,y=0,z=0,facing=heading or 'north'},dimension='minecraft:overworld',
  bounds={min={x=-10,y=-1,z=-10},max={x=10,y=2,z=10}},length=6,branchInterval=3,branchLength=2,torchInterval=3,
  outputSide='front',supplySide='up',fuelMargin=8,torchReserve=1,fillReserve=8,fillItem='minecraft:cobblestone'}
end
local function ready(opts,cfg)
 local w=fresh(opts);cfg=cfg or config(w.pose.facing)
 w.slots[1]={name='minecraft:coal',count=32};w.slots[2]={name='minecraft:torch',count=32};w.slots[3]={name='minecraft:cobblestone',count=64}
 -- Receiver below home keeps both the forward entrance and bay ceiling distinct.
 cfg.outputSide='down';cfg.supplySide='up'
 w.set(w.target('down'),{name='minecraft:chest',capacity=100000,items={}})
 w.set(w.target('up'),{name='minecraft:chest',capacity=100000,items={['minecraft:coal']=16,['minecraft:torch']=64,['minecraft:cobblestone']=64}})
 local ctx={config=cfg};local engine=require('lib_safe_miner')
 local ok,err=engine.initialize(ctx);assert(ok~='ERROR',ctx.lastError or err)
 local raw=engine.step;local ticks=0;engine.step=function(c) ticks=ticks+1;if ticks%20==0 then nativeSleep(0) end;return raw(c) end
 return w,ctx,engine
end
local function drive(w,ctx,engine,max)
 for tick=1,max or 1000 do
  if ctx.phase=='DONE' or ctx.phase=='NEEDS_HELP' or ctx.phase=='STOPPED' then return end
  engine.step(ctx)
  if tick%20==0 then nativeSleep(0) end
 end
 error('Exceeded bounded test steps: '..tostring(ctx.phase))
end
local function poseMatches(w,ctx)
 local p=ctx.pose or (ctx.movementState and ctx.movementState.position)
 assert(p,'Missing engine pose');eq(w.pose.x,p.x,'physical x');eq(w.pose.y,p.y,'physical y');eq(w.pose.z,p.z,'physical z')
 if p.facing then eq(w.pose.facing,p.facing,'physical heading') end
end

for _,heading in ipairs({'north','east','south','west'}) do
 test('bilateral route geometry '..heading,function()
  fresh({facing=heading});local s=require('lib_strategy_branchmine');local steps=s.generate(6,3,2,3)
  local min,max=999,-999;local branches={};local origin={x=100,y=64,z=200,facing=heading}
  for _,step in ipairs(steps) do
   if step.type=='move' then min=math.min(min,step.x);max=math.max(max,step.x);if step.z==3 or step.z==6 then branches[step.x..','..step.z]=true end end
   local world=s.localToWorld(origin,step);local dx,dz=world.x-origin.x,world.z-origin.z
   local expected={north={step.x,-step.z},east={step.z,step.x},south={-step.x,step.z},west={-step.z,-step.x}}
   eq(dx,expected[heading][1]);eq(dz,expected[heading][2]);eq(world.y,64+step.y)
  end
  eq(min,-2);eq(max,2);for _,z in ipairs({3,6}) do for _,x in ipairs({-2,-1,1,2}) do assert(branches[x..','..z],'Missing bilateral branch coordinate') end end
  local last=steps[#steps];eq(last.type,'done');eq(last.x,0);eq(last.z,0);eq(last.y,0);eq(last.facing,0)
 end)
end

test('explicit policy rejects containers turtles unknown and fluids',function()
 fresh();local p=require('lib_mine_policy')
 for _,name in ipairs({'minecraft:chest','minecraft:barrel','computercraft:turtle_normal','computercraft:computer_advanced','mod:machine'}) do eq(p.classify(name),'protected') end
 eq(p.classify('mod:mystery_ore'),'unknown');eq(p.classify('minecraft:lava'),'fluid');eq(p.classify('minecraft:water'),'fluid')
 eq(p.classify('minecraft:diamond_ore'),'ore');eq(p.classify('minecraft:stone'),'terrain')
end)

local function primitiveWorld(dir,name)
 local w=fresh();local movement=require('lib_movement');local p=require('lib_mine_policy')
 local c={config={},origin={x=0,y=0,z=0,facing='north'},miningPolicy={allowed={},knownAir={},config={},maxFallingBlocks=8}}
 movement.setPosition(c,w.pose);movement.setFacing(c,'north')
 for _,d in ipairs({'front','up','down'}) do local target=w.target(d);c.miningPolicy.allowed[p.key(target)]=true end
 w.set(w.target(dir),name);w.slots[1]={name='minecraft:cobblestone',count=64}
 return w,c,require('lib_mining'),movement
end
for _,dir in ipairs({'front','up','down'}) do
 for _,name in ipairs({'minecraft:chest','computercraft:turtle_normal','mod:mystery_ore','minecraft:lava','minecraft:water'}) do
  for _,api in ipairs({'prepareMove','mineAndFill'}) do
   test(api..' protects '..dir..' '..name,function()
    local w,c,m=primitiveWorld(dir,name);local ok,err=m[api](c,dir);assert(not ok,err)
    for _,call in ipairs(w.calls) do assert(not call.name:match('^dig'),'Forbidden block was dug') end
    eq(w.block(w.target(dir)),name)
   end)
  end
 end
 test('safe movement cannot bypass block policy '..dir,function()
  local w,c,m,movement=primitiveWorld(dir,'minecraft:chest');local fn=dir=='front' and movement.forward or movement[dir]
  assert(not fn(c,{dig=true,attack=true,maxRetries=3}));eq(#w.calls,0,'Protected movement made a native destructive call')
 end)
 test('unknown cave opening fails '..dir,function()
  local w,c,m=primitiveWorld(dir,false);assert(not m.prepareMove(c,dir));eq(#w.calls,0)
 end)
 test('failed seal is surfaced '..dir,function()
  local w,c,m=primitiveWorld(dir,'minecraft:diamond_ore');w.fail.place=true;w.fail.placeUp=true;w.fail.placeDown=true
  local ok,err=m.mineAndFill(c,dir);assert(not ok);assert(err:find('seal'),'Missing seal reason')
 end)
end
test('falling material has bounded dig attempts',function()
 local w,c,m=primitiveWorld('front','minecraft:gravel');local native=turtle.dig
 turtle.dig=function() local ok,err=native();if ok then w.set(w.target('front'),'minecraft:gravel') end;return ok,err end
 local ok,err=m.prepareMove(c,'front');assert(not ok);assert(err:find('falling'));local digs=0
 for _,call in ipairs(w.calls) do if call.name=='dig' then digs=digs+1 end end;eq(digs,8)
end)
test('neighbor scan stops on horizontal protected block without digging',function()
 local w,c,m=primitiveWorld('front','minecraft:chest');local ok=m.scanAndMineNeighbors(c);assert(not ok)
 for _,call in ipairs(w.calls) do assert(not call.name:match('^dig')) end
end)

for _,heading in ipairs({'north','east','south','west'}) do
 test('complete tiny mine physical cycle '..heading,function()
  local w,c,e=ready({facing=heading});drive(w,c,e);eq(c.phase,'DONE',c.lastError);poseMatches(w,c)
  eq(w.pose.x,0);eq(w.pose.y,0);eq(w.pose.z,0);eq(w.pose.facing,heading);eq(w.drops,0,'No world-item dumping')
  local receiver=w.block({x=0,y=-1,z=0});assert((receiver.received or 0)>0,'Mined output was not transferred')
 end)
end

test('unlimited fuel runs complete operating cycle',function() local w,c,e=ready({fuel='unlimited'});drive(w,c,e);eq(c.phase,'DONE',c.lastError);eq(w.fuel,'unlimited') end)
test('low fuel without consumables stops before reserve loss',function()
 local w,c,e=ready({fuel=0});w.slots[1]=nil;drive(w,c,e);eq(c.phase,'NEEDS_HELP');eq(w.pose.x,0);eq(w.pose.z,0);eq(w.fuel,0)
end)
test('missing output receiver fails without drops',function()
 local w,c,e=ready();w.set({x=0,y=-1,z=0},false);drive(w,c,e);eq(c.phase,'NEEDS_HELP');eq(w.drops,0)
end)
test('full output receiver fails without drops',function()
 local w,c,e=ready();w.block({x=0,y=-1,z=0}).capacity=0;drive(w,c,e);eq(c.phase,'NEEDS_HELP');eq(w.drops,0)
end)
test('failed turn preserves instruction and heading',function()
 local w,c,e=ready();w.fail.turnRight=true;w.fail.turnLeft=true;drive(w,c,e);eq(c.phase,'NEEDS_HELP');poseMatches(w,c)
end)
test('failed torch placement stops instead of advancing',function()
 local w,c,e=ready();w.fail.place=true;w.fail.placeUp=true;w.fail.placeDown=true;drive(w,c,e);eq(c.phase,'NEEDS_HELP');assert(c.lastError)
end)
test('blocked home route stops without destructive shortcuts',function()
 local w,c,e=ready();for _=1,20 do e.step(c);if w.pose.z < -1 then break end end
 e.requestReturn(c);local before=#w.calls;w.fail.forward=true;w.fail.back=true;drive(w,c,e);eq(c.phase,'NEEDS_HELP')
 for i=before+1,#w.calls do assert(not w.calls[i].name:match('^dig'),'Return attempted excavation') end
end)
test('inventory service restores exact work pose before next instruction',function()
 local w,c,e=ready();for _=1,20 do e.step(c);if w.pose.z < -1 then break end end
 for i=4,16 do w.slots[i]={name='minecraft:iron_ore',count=64} end
 local work=sim.copy(w.pose);local pointer=c.pointer;local sawResume=false
 for _=1,1000 do
  e.step(c)
  if c.phase=='NEEDS_HELP' then error(c.lastError) end
  if c.phase=='RESUMING' then sawResume=true end
  if sawResume and c.phase=='MINING' then break end
 end
 assert(sawResume,'Capacity never triggered service');eq(c.pointer,pointer,'Resume instruction');eq(w.pose.x,work.x);eq(w.pose.y,work.y);eq(w.pose.z,work.z);eq(w.pose.facing,work.facing)
 drive(w,c,e);eq(c.phase,'DONE',c.lastError)
end)
test('checkpoint readback and clean reload preserve pointer and pose',function()
 local w,c,e=ready();for _=1,5 do e.step(c) end
 local cp=require('lib_mining_checkpoint');local saved,err=cp.save(c);assert(saved,err);local record,loadErr=cp.load(c);assert(record,loadErr);eq(record.pointer,c.pointer);eq(record.pose.z,c.pose.z)
 local loaded={config=sim.copy(c.config)};loaded.config.resume=true;local ok,e2=e.initialize(loaded);assert(ok~='ERROR',loaded.lastError or e2);eq(loaded.pointer,c.pointer);eq(loaded.pose.z,c.pose.z);poseMatches(w,loaded)
end)
test('interrupted action refuses recovery without turtle actions',function()
 local w,c,e=ready();local cp=require('lib_mining_checkpoint');c.intent={action='forward'};assert(cp.save(c));local before=#w.calls
 local resumed={config=sim.copy(c.config)};resumed.config.resume=true;local ok,err=e.initialize(resumed);eq(ok,'ERROR','Ambiguous pose accepted');assert(resumed.lastError);eq(#w.calls,before)
end)
test('interrupted journal replacement refuses automatic recovery',function()
 local w,c,e=ready();local cp=require('lib_mining_checkpoint');w.files[cp.path(c)..'.next']='unfinished';local before=#w.calls
 local resumed={config=sim.copy(c.config)};resumed.config.resume=true;eq(e.initialize(resumed),'ERROR');eq(#w.calls,before)
end)
test('corrupt checkpoint refuses recovery',function()
 local w,c,e=ready();local cp=require('lib_mining_checkpoint');w.files[cp.path(c)]='this is not serialized Lua';local before=#w.calls
 local resumed={config=sim.copy(c.config)};resumed.config.resume=true;eq(e.initialize(resumed),'ERROR');eq(#w.calls,before)
end)

for _,failure in ipairs({'open','write','move','readback'}) do
 test('checkpoint '..failure..' failure prevents unjournaled action',function()
  local w,c,e=ready();local before=#w.calls;w.fsFail=failure
  local ok,err=e.step(c)
  eq(#w.calls,before,'No action after persistence failure');assert(c.phase=='NEEDS_HELP' or ok==false,'Persistence failure did not stop')
 end)
end
test('real termination after successful physical move fails closed on fresh load',function()
 local w,c,e=ready();local interrupted=false
 w.afterAction=function(name) if name=='forward' or name=='up' or name=='down' then interrupted=true;error('Injected process termination after physical action') end end
 local ok=pcall(function() drive(w,c,e) end);assert(interrupted,'No physical action reached')
 w.afterAction=nil;local before=#w.calls
 package.loaded.lib_safe_miner=nil;package.loaded.lib_mining_checkpoint=nil
 local engine=require('lib_safe_miner');local resumed={config=sim.copy(c.config)};resumed.config.resume=true
 eq(engine.initialize(resumed),'ERROR','Physical interrupted action resumed');eq(#w.calls,before)
end)
test('partial receiver transfer is counted without world drops',function()
 local w,c,e=ready();w.block({x=0,y=-1,z=0}).maxTransfer=7;drive(w,c,e)
 assert(c.phase=='DONE' or c.phase=='NEEDS_HELP','Unbounded transfer');eq(w.drops,0)
 local output=w.block({x=0,y=-1,z=0});assert((output.received or 0)>0,'Partial transfer not attempted')
end)

for _,dims in ipairs({{39,13},{39,19},{51,19}}) do
 test('rendered labelled keyboard UI '..dims[1]..'x'..dims[2],function()
  local w,c,e=ready();c.phase='NEEDS_HELP';c.lastError='Protected block minecraft:chest at 2, 64, -5. No digging permitted.'
  local screen=window.create(realTerm.current(),1,1,dims[1],dims[2],false)
  local previous=term.redirect(screen);require('lib_mining_status').render(c);term.redirect(previous)
  local hex='0123456789abcdef';local palette,lines={},{};local all=''
  for i=0,15 do palette[hex:sub(i+1,i+1)]=colors.packRGB(screen.getPaletteColor(2^i)) end
  for y=1,dims[2] do local text,fg,bg=screen.getLine(y);lines[y]={text={text:byte(1,-1)},fg=fg,bg=bg};all=all..text end
  local file=assert(realFS.open('/results/miner-'..dims[1]..'x'..dims[2]..'.screen.json','w'))
  file.write(textutils.serializeJSON({w=dims[1],h=dims[2],palette=palette,lines=lines}));file.close()
  assert(all:find('NEEDS HELP',1,true));assert(all:find('Q: EXIT',1,true));assert(not all:find('R: RETURN',1,true))
  if not all:find('Protected block',1,true) then
   for page=2,c.statusPages do c.statusPage=page;local prev=term.redirect(screen);require('lib_mining_status').render(c);term.redirect(prev)
    for y=1,dims[2] do local text=screen.getLine(y);all=all..text end
   end
  end
  assert(all:find('Protected block',1,true),'Reason invisible across keyboard detail pages')
  for _,line in ipairs(lines) do assert(not line.fg:find('[^0]'),'Text must be high contrast white');assert(not line.bg:find('[^f]'),'Background must be black') end
 end)
end

test('surplus cobblestone unload creates mining capacity and resumes',function()
 local w,c,e=ready();for _=1,5 do e.step(c) end
 for i=1,16 do w.slots[i]={name='minecraft:cobblestone',count=64} end
 local pointer=c.pointer;local resumed=false
 for _=1,1000 do e.step(c);if c.phase=='NEEDS_HELP' then error(c.lastError) end;if c.phase=='RESUMING' then resumed=true end;if resumed and c.phase=='MINING' then break end end
 assert(resumed,'No surplus unload');local free=0;for i=1,16 do if not w.slots[i] then free=free+1 end end;assert(free>=2,'Capacity still full');eq(c.pointer,pointer)
 drive(w,c,e);eq(c.phase,'DONE',c.lastError)
end)
test('move orientation substep never skips target cell',function()
 local w,c,e=ready();while c.strategy[c.pointer].type~='move' do e.step(c) end
 w.pose.facing='south';c.pose.facing='south';c.movement.facing='south'
 local pointer=c.pointer;local start=sim.copy(w.pose);e.step(c)
 eq(c.pointer,pointer,'Turn-only move advanced instruction');eq(w.pose.x,start.x);eq(w.pose.z,start.z)
 for _=1,5 do if c.pointer~=pointer then break end;e.step(c) end
 assert(c.pointer>pointer,'Move did not finish');assert(w.pose.x~=start.x or w.pose.z~=start.z,'No physical movement')
end)
test('clean restart after placed torches finishes complete cycle',function()
 local w,c,e=ready();local sawTorch=false
 for _=1,300 do e.step(c);for _,call in ipairs(w.calls) do if call.name=='place' then sawTorch=true end end;if sawTorch then break end end
 assert(sawTorch,'No torch placed');local cp=require('lib_mining_checkpoint');assert(cp.save(c))
 package.loaded.lib_safe_miner=nil;local engine=require('lib_safe_miner');local resumed={config=sim.copy(c.config)};resumed.config.resume=true
 eq(engine.initialize(resumed),'MINE',resumed.lastError)
 drive(w,resumed,engine);eq(resumed.phase,'DONE',resumed.lastError);eq(w.drops,0)
end)

local function factoryEvents(events)
 local w,c,e=ready();w.files={};local i=0
 local fakeOS=setmetatable({startTimer=function() return 42 end},{__index=os})
 fakeOS.pullEvent=function() i=i+1;local event=assert(events[i],'Factory requested unexpected extra event');if event.check then event.check(w) end;return event[1],event[2] end
 local env=setmetatable({os=fakeOS,sleep=function() end,_G={__FACTORY_EMBED__=true}},{__index=_ENV})
 local factory=assert(load(sources.factory,'@factory','t',env))()
 local result=factory.run({'mine','--job','tiny','--dimension','minecraft:overworld','--home','0','0','0','--heading','north','--bounds-min','-10','-1','-10','--bounds-max','10','2','10','--length','6','--branch-interval','3','--branch-length','2','--torch-interval','3','--output-side','down','--supply-side','up'})
 return w,result
end

test('factory READY Q stops with zero native turtle actions',function()
 local w,c=factoryEvents({{'key',keys.q,check=function(w) eq(#w.calls,0) end}});eq(c.phase,'STOPPED');eq(#w.calls,0)
end)
test('factory keys and stale timers never mine before Enter',function()
 local noActions=function(w) eq(#w.calls,0,'Unexpected action before confirmation') end
 local w,c=factoryEvents({{'key',keys.right,check=noActions},{'timer',999,check=noActions},{'key',keys.pageDown,check=noActions},{'key',keys.q,check=noActions}})
 eq(c.phase,'STOPPED');eq(#w.calls,0)
end)
test('factory detail key and stale timer after Enter do not advance',function()
 local noActions=function(w) eq(#w.calls,0,'Detail event advanced mining') end
 local w,c=factoryEvents({{'key',keys.enter,check=noActions},{'key',keys.right,check=noActions},{'timer',999,check=noActions},{'key',keys.q,check=noActions}})
 eq(c.phase,'STOPPED');eq(c.pointer,1);eq(#w.calls,0)
end)
test('manual return stops partial job and clean resume completes it',function()
 local w,c,e=ready();for _=1,10 do e.step(c) end;e.requestReturn(c);drive(w,c,e);eq(c.phase,'STOPPED');assert(c.pointer<#c.strategy)
 local resumed={config=sim.copy(c.config)};resumed.config.resume=true;eq(e.initialize(resumed),'MINE',resumed.lastError)
 drive(w,resumed,e);eq(resumed.phase,'DONE',resumed.lastError)
end)

test('completion at home does not traverse the job a second time',function()
 local w,c,e=ready();for _=1,1000 do if c.strategy[c.pointer].type=='done' then break end;e.step(c) end
 eq(c.strategy[c.pointer].type,'done');eq(w.pose.x,0);eq(w.pose.y,0);eq(w.pose.z,0)
 local before=#w.calls;drive(w,c,e);eq(c.phase,'DONE',c.lastError)
 for i=before+1,#w.calls do assert(not ({forward=true,back=true,up=true,down=true})[w.calls[i].name],'Completed job traversed again') end
end)
test('every physical dig preserves capacity with distinct neighbour drops',function()
 local w,c,m=primitiveWorld('front','minecraft:diamond_ore')
 for i=3,13 do w.slots[i]={name='mod:stored_'..i,count=64} end
 for _,dir in ipairs({'up','down'}) do w.set(w.target(dir),dir=='up' and 'minecraft:iron_ore' or 'minecraft:gold_ore') end
 local p=require('lib_mine_policy');for _,pos in ipairs({{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=0,z=1}}) do c.miningPolicy.allowed[p.key(pos)]=true;w.set(pos,'minecraft:emerald_ore') end
 local record=w.record;w.record=function(name,target)
  if name:match('^dig') then local free=0;for i=1,16 do if not w.slots[i] then free=free+1 end end;assert(free>=2,'Physical dig without reserve capacity') end
  return record(name,target)
 end
 local ok,err=m.scanAndMineNeighbors(c);assert(not ok);eq(err,'inventory_capacity');eq(w.drops,0)
end)

local function setupAnswers(answers)
 local w=fresh();local old=read;local i=0
 read=function() i=i+1;return assert(answers[i],'Unexpected setup input request') end
 local ok,args=pcall(function() return require('lib_mining_setup').collect() end);read=old
 assert(ok,args);eq(#w.calls,0,'Setup performed turtle action');return args,i
end
test('setup valid tiny defaults generate complete explicit CLI arguments',function()
 local args,count=setupAnswers({'setup-one','','0 64 0','north','minecraft:overworld','','','','','','','',''})
 assert(args);local all=table.concat(args,' ');assert(all:find('--job setup-one',1,true));assert(all:find('--home 0 64 0',1,true));assert(all:find('--heading north',1,true));assert(all:find('--bounds-min',1,true));assert(all:find('--length 6',1,true));eq(count,13)
end)
test('setup malformed home reprompts rather than inferring pose',function()
 local args,count=setupAnswers({'setup-one','','bad position','0 64 0','north','minecraft:overworld','','','','','','','',''})
 assert(args);eq(count,14);assert(table.concat(args,' '):find('--home 0 64 0',1,true))
end)
test('setup Q cancels without turtle actions',function() local args=setupAnswers({'q'});eq(args,nil) end)

test('factory R retraces and unloads partial job without new excavation',function()
 local digCount
 local events={{'key',keys.enter},{'timer',42},{'timer',42},{'key',keys.r,check=function(w)
  digCount=0;for _,call in ipairs(w.calls) do if call.name:match('^dig') then digCount=digCount+1 end end;assert(digCount>0,'No work before return request')
 end}}
 for _=1,30 do events[#events+1]={'timer',42,check=function(w)
  local n=0;for _,call in ipairs(w.calls) do if call.name:match('^dig') then n=n+1 end end;eq(n,digCount,'Return excavated new cells')
 end} end
 local w,c=factoryEvents(events);eq(c.phase,'STOPPED');eq(w.pose.x,0);eq(w.pose.y,0);eq(w.pose.z,0);eq(w.pose.facing,'north');eq(w.drops,0)
end)

report[#report+1]=(failed==0 and 'PASS all ' or 'FAIL summary ')..passed..' passed, '..failed..' failed'
local out=assert(realFS.open('/results/tests.txt','w'));out.write(table.concat(report,'\n')..'\n');out.close()
if failed>0 then error(failed..' test failures') end
