local M={}
function M.display(client,t,demo,verify)
 local sim=require('derby.sim'); local render=require('derby.render').new(t)
 local camera=settings.get('derby.camera','follow')
 local snapshot={phase='CONNECTING',positions={0,0,0},order={}}
 local race=demo and sim.new(1977); local tick=0
 local nextStep=os.epoch('utc'); local started=nextStep; local frames=0
 local sfx=require('derby.sfx').new()
 local timer=os.startTimer(.05)
 while true do
  local e,a,b,c=os.pullEvent()
  if e=='timer' and a==timer then
   if demo then
    local now=os.epoch('utc')
    while now>=nextStep do
     tick=tick+1; nextStep=nextStep+100
     if tick>30 and #race.order<3 then sim.step(race) end
    end
    snapshot={phase=tick<=30 and 'LOCKED' or (#race.order==3 and 'RESULT' or 'RUNNING'),positions=sim.positions(race),order=race.order,tick=race.tick,seconds=tick<=30 and math.ceil((30-tick)/10) or 0}
    if verify and #race.order==3 then
     local f=assert(fs.open('/derby-exhibition.json','w'))
     f.write(textutils.serializeJSON({seed=race.seed,order=race.order,frames=frames,elapsed=(now-started)/1000,fps=frames/math.max(.001,(now-started)/1000)})); f.close(); verify=false
    end
    if tick>race.tick+180 then race=sim.new(race.seed+1); tick=0 end
   else
    local r=client:read({op='snapshot'})
    snapshot=r.ok and r or {phase='HOUSE OFFLINE',offline=true,positions=snapshot.positions,order={}}
   end
   sfx:hear(snapshot,os.epoch('utc'))
   render:draw(snapshot,camera,demo); frames=frames+1; timer=os.startTimer(.05)
  elseif e=='key' or e=='monitor_touch' or e=='mouse_click' then
   local before=camera
   if e~='key' or a==keys.c then camera=M.nextCamera(camera)
   elseif a==keys.q or a==keys.backspace then return
   elseif a==keys.one then camera='follow' elseif a==keys.two then camera='overview' elseif a==keys.three then camera='finish' end
   if camera~=before then
    settings.set('derby.camera',camera); settings.save('/derby-settings')
    render:draw(snapshot,camera,demo)
   end
  elseif e=='term_resize' or e=='monitor_resize' then render:draw(snapshot,camera,demo) end
 end
end
function M.nextCamera(camera)
 return camera=='follow' and 'overview' or camera=='overview' and 'finish' or 'follow'
end
-- Splits `--monitor NAME` and `--terminal` (as Pine Arcade and get --startup pass them)
-- from the command words. Returns the words and the chosen screen, if any.
function M.options(args)
 local words,screen={},nil
 local i=1
 while i<=#args do
  if args[i]=='--terminal' then screen={terminal=true}
  elseif args[i]=='--monitor' then i=i+1; screen={monitor=args[i]}
  else words[#words+1]=args[i] end
  i=i+1
 end
 return words,screen
end
function M.target(screen)
 local ui=require('derby.ui')
 if screen and screen.terminal then return term.current() end
 if screen and screen.monitor then return assert(peripheral.wrap(screen.monitor or ''),'No monitor named '..tostring(screen.monitor)) end
 return ui.target()
end
local function run(args,t)
 local config=require('derby.config'); local ui=require('derby.ui')
 settings.load('/derby-settings')
 local c=config.read()
 local command=args[1] or 'station'
 -- A bare `race` on a computer that is not part of a house (Pine Arcade, a boot entry)
 -- shows the exhibition rather than a setup hint that vanishes at once.
 if command=='--demo' or command=='demo' or (command=='station' and not c and (not args[1] or (arcadeos and arcadeos.freeplay()))) then return M.display(nil,t,true,args[2]=='--verify') end
 if command=='setup' then return config.setup(args[2],args[3],args[4]) end
 if not c then print('House is not configured. Exhibition: race --demo'); print('Configure: house setup station <wired-modem> <host-id>'); return end
 if command=='host' then assert(c.role=='host','Configure this computer as the host'); return require('derby.server').run(c) end
 -- Screens keep keys, touches and their own timers that arrive during a host request.
 local client=require('derby.client').new(c,{keepEvents=true})
 if command=='display' then return M.display(client,t,false)
 elseif command=='cashier' then assert(c.role=='cashier','Configure this computer as cashier'); return require('derby.cashier').run(client,t)
 elseif command=='station' then return require('derby.station').run(client,t) end
 error('Use: house host|display|station|cashier|setup or race --demo',0)
end
function M.run(args)
 local words,screen=M.options(args)
 local t=M.target(screen)
 local scale=t.getTextScale and t.getTextScale()
 require('derby.ui').fit(t,39,19)
 local restore=require('derby.palette').save(t)
 local old=term.current()
 local ok,err=xpcall(function() run(words,t) end,debug.traceback)
 term.redirect(old); restore()
 if scale then t.setTextScale(scale) end
 if not ok then error(err,0) end
end
return M
