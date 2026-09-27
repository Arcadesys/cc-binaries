-- Real dispatcher/renderer integration. Controls are queued CC events; tests
-- never mutate the game's rack, result, score, or selected settings.
local App=require('lib.app')
local ui=require('lib.ui')
local M={}
local keyNames={start='space',continue='space',roll='space',players_up='right',players_down='left',
 select_position='one',select_aim='two',select_power='three',select_hook='four',adjust_down='left',adjust_up='right',
 fine='f',view='tab',skip='s',help='h',pause='p',restart='r',quit='backspace',select_prev='up',select_next='down'}
function M.run(mode,playerCount,shots)
 local started=os.epoch('utc')
 local name=mode=='monitor' and 'lanes_test' or nil
 if name then assert(periphemu.create(name,'monitor')) end
 local original=term.current();local target=name and peripheral.wrap(name) or original
 local palette={};for i=0,15 do palette[2^i]={original.getPaletteColor(2^i)} end
 local done,timedOut=false,false;local pending;local final
 local frames,events={},{};local warm=1;local finalStage=1;local numRolls=0;local lastPhase
 local function queue(action,app)
   local event
   if name then
     local w,h=target.getSize()
     for _,b in ipairs(ui.layout(w,h,app.phase,app.camera)) do
       if b.id==action then event={'monitor_touch',name,b.x+math.floor(b.w/2),b.y+math.floor(b.h/2)};break end
     end
     assert(event,'No tap target '..action..' in '..app.phase)
   else event={'key',assert(keys[keyNames[action]],action),false} end
   if action=='roll' or action=='start' or action=='continue' then
     pending={time=os.clock()+.35,event=event}
   else os.queueEvent(table.unpack(event)) end
 end
 local options={terminal=not name,monitor=name}
 options.record=function(kind,data,app)
   if kind=='resolved' then
     numRolls=numRolls+1
     events[#events+1]={deliveryId=data.deliveryId,player=app.beforeRoll.player,frame=app.beforeRoll.frame,ball=app.beforeRoll.ballNumber,count=#data.knocked,duration=data.duration}
     local h=fs.open('/results/progress.txt','w');h.write(mode..' roll '..numRolls..' player '..app.beforeRoll.player..' frame '..app.beforeRoll.frame);h.close()
   elseif kind=='cancelled' then error('Runtime roll cancelled: '..tostring(data and data.error))
   elseif kind=='frame' then
     frames[#frames+1]=data.renderMs;assert(#frames<6000,'frame budget')
     if app.phase=='SETUP' then
       if app.playerCount<playerCount then queue('players_up',app) else queue('start',app) end;return
     end
     -- Inspect help and all camera modes once before bowling.
     local actions={'help','start','view','view','view','pause','start'}
     if warm<=#actions then local action=actions[warm];warm=warm+1;queue(action,app);return end
     if app.phase=='AIM' then
       local shot=shots[(numRolls%#shots)+1]
       if not app.fine then queue('fine',app);return end
       for _,p in ipairs({'position','aim','power','hook'}) do
         local goal=shot[p]
         if goal and math.abs(app:currentSettings()[p]-goal)>1e-7 then
           if app.selected~=p then queue('select_'..p,app)
           else queue(app:currentSettings()[p]<goal and 'adjust_up' or 'adjust_down',app) end
           return
         end
       end
       queue('roll',app)
     elseif app.phase=='PLAYBACK' then queue('skip',app)
     elseif app.phase=='RESULT' then queue('continue',app)
     elseif app.phase=='FINAL' then
       assert(app.match.complete and numRolls>=playerCount*10 and numRolls<=playerCount*21,'match progression')
       if mode=='monitor' and finalStage==1 then
         target.setTextScale(target.getTextScale()==.5 and 1 or .5);finalStage=2
       elseif mode=='monitor' and finalStage==3 then
         assert(periphemu.remove(name));name=nil;target=original;finalStage=4
       else queue('quit',app) end
     elseif app.phase=='PAUSED' and (finalStage==2 or finalStage==4) then
       finalStage=finalStage+1;queue('start',app)
     end
   end
 end
 parallel.waitForAll(function() final=App.run(options);done=true end,function()
   local start=os.clock()
   while not done do
     sleep(.1)
     if pending and os.clock()>=pending.time then os.queueEvent(table.unpack(pending.event));pending=nil end
     if os.clock()-start>240 then timedOut=true;os.queueEvent('terminate');return end
   end
 end)
 assert(not timedOut,'runtime timeout '..mode)
 assert(final.match.complete,'incomplete match')
 assert(term.current()==original,'redirect not restored')
 for c,rgb in pairs(palette) do
   local r,g,b=original.getPaletteColor(c)
   assert(math.abs(r-rgb[1])<1e-6 and math.abs(g-rgb[2])<1e-6 and math.abs(b-rgb[3])<1e-6,'palette not restored')
 end
 local scores={};local rules=require('lib.rules')
 for i,p in ipairs(final.match.players) do
   local card=rules.score(p);assert(not card.pending and card.total>=0 and card.total<=300)
   scores[i]=card.total
 end
 if name then periphemu.remove(name) end
 print('PASS runtime '..mode..': '..playerCount..' players, '..numRolls..' deliveries, complete match, help/views/pause, clean restoration'..(mode=='monitor' and ', actual resize/detach' or ''))
 return {mode=mode,players=playerCount,scores=scores,frames=frames,events=events,elapsedMs=os.epoch('utc')-started}
end
-- Resize to an unsupported size, recover, then detach during live playback.
-- Only real peripheral changes and keyboard events drive the controller.
function M.playbackRecovery()
 local original=term.current();assert(periphemu.create('lanes_recovery','monitor'))
 local target=peripheral.wrap('lanes_recovery');local stage=0;local done=false
 local frozen,elapsed,simulation;local pending;local start=os.clock()
 local function key(name) pending={at=os.clock()+.35,name=name} end
 local final
 parallel.waitForAll(function()
  final=App.run({monitor='lanes_recovery',record=function(kind,data,app)
   if kind~='frame' then return end
   if stage==0 and app.phase=='SETUP' then stage=1;key('space')
   elseif stage==1 and app.phase=='AIM' then stage=2;key('space')
   elseif stage==2 and app.phase=='PLAYBACK' then
    frozen,elapsed,simulation=app.displaySnapshot,app.playback.elapsed,app.sim
    stage=3;target.setTextScale(3)
   elseif stage==3 and app.phase=='PAUSED' then
    assert(app.smallDisplay and app.displaySnapshot==frozen and app.sim==simulation and app.playback.elapsed==elapsed,'small resize changed playback')
    assert(#ui.layout(data.width,data.height,app.phase)==1,'small screen did not retain quit')
    stage=4;target.setTextScale(.5)
   elseif stage==4 and app.phase=='PAUSED' and not app.smallDisplay then stage=5;key('space')
   elseif stage==5 and app.phase=='PLAYBACK' then
    assert(app.displaySnapshot==frozen and app.playback.elapsed==elapsed,'resize resume changed playback')
    stage=6;assert(periphemu.remove('lanes_recovery'))
   elseif stage==6 and app.phase=='PAUSED' then
    assert(app.displaySnapshot==frozen and app.sim==simulation and app.playback.elapsed==elapsed,'detach changed playback')
    stage=7;key('space')
   elseif stage==7 and app.phase=='PLAYBACK' then stage=8;key('s')
   elseif stage==8 and app.phase=='RESULT' then stage=9;key('p')
   elseif stage==9 and app.phase=='PAUSED' then stage=10;key('backspace') end
  end});done=true
 end,function()
  while not done do
   sleep(.05)
   if pending and os.clock()>=pending.at then os.queueEvent('key',keys[pending.name],false);pending=nil end
   if os.clock()-start>30 then os.queueEvent('terminate');return end
  end
 end)
 assert(stage==10 and final.match.lastDeliveryId==1,'recovery delivery was lost or repeated')
 assert(term.current()==original,'recovery redirect restoration')
 print('PASS live playback: small-screen resize, recovery, monitor detach, same cached delivery, clean exit')
end
function M.errorRestoration()
 local original=term.current();assert(periphemu.create('lanes_error','monitor'))
 local target=peripheral.wrap('lanes_error');local palette={}
 for i=0,15 do palette[2^i]={target.getPaletteColor(2^i)} end
 local ok=pcall(App.run,{monitor='lanes_error',record=function(kind) if kind=='frame' then error('intentional renderer observer failure') end end})
 assert(not ok and term.current()==original,'error did not restore redirect')
 for c,rgb in pairs(palette) do
  local r,g,b=target.getPaletteColor(c)
  assert(math.abs(r-rgb[1])<1e-6 and math.abs(g-rgb[2])<1e-6 and math.abs(b-rgb[3])<1e-6,'error palette restoration')
 end
 periphemu.remove('lanes_error');print('PASS error path: monitor palette and original terminal restored')
end
return M
