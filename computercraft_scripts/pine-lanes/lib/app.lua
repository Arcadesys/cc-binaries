local physics=require('lib.physics')
local rules=require('lib.rules')
local lane=require('lib.lane')
local mascots=require('lib.mascots')
local App={}; App.__index=App
local parameters={'position','aim','power','hook'}
-- Furball control units: position, aim (launch angle) and hook (spin) span -100..100; power 0..100.
local limits={position={-100,100,10,2},aim={-100,100,5,1},power={0,100,5,1},hook={-100,100,10,2}}
local function settings() return {position=0,aim=0,power=60,hook=0} end
local function copy(value)
  if type(value)~='table' then return value end
  local out={}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end
function App.new(options)
  options=options or {}
  local self=setmetatable({options=options,phase='SETUP',playerCount=1,selected='position',fine=false,camera='lane',scorePlayer=1,
    running=true,deliveryId=0,lastInput='Ready',message='Choose 1-4 players, then START.',
    seed=math.floor(tonumber(options.seed) or (os.epoch and os.epoch('utc') or os.time()) % 1000000)},App)
  self.sound=options.sound or require('lib.sound').new()
  self:resetMatch(1)
  if options.diagnostic then self.phase='AIM'; self.message='X+ down lane | Y+ up | Z+ right' end
  return self
end
function App:cue(name,offsetMs) self.sound:play(name,offsetMs) end
function App:emit(kind,data)
  if self.options.record then self.options.record(kind,data,self) end
end
function App:resetMatch(count)
  self.playerCount=count; self.match=assert(rules.new(count))
  self.playerSettings={}; self.playerMascots={}; for i=1,count do self.playerSettings[i]=settings(); self.playerMascots[i]=(i-1)%#mascots.list+1 end
  self.mascotPlayer=1
  self.sim=nil; self.playback=nil; self.displaySnapshot=nil; self.rollSummary=nil; self.resumePhase=nil
  self.selected='position'; self.fine=false; self.camera='lane'; self.scorePlayer=1
end
function App:currentSettings() return self.playerSettings[self.match.currentPlayer] end
function App:view()
  local scores={}; for i,p in ipairs(self.match.players) do scores[i]=rules.score(p) end
  local set=self:currentSettings()
  return {phase=self.phase,playerCount=self.playerCount,currentPlayer=self.match.currentPlayer,frame=self.match.frame,
    ballNumber=self.match.ballNumber,settings=set,selected=self.selected,fine=self.fine,camera=self.camera,scorePlayer=self.scorePlayer,
    snapshot=self.displaySnapshot or {ball={x=0,y=lane.ballRadius,z=physics.releaseZ(set.position),gutter=false},pins=self.match.rack},
    preview=(self.phase=='AIM' and not self.displaySnapshot) and physics.preview(set) or nil,
    scorecards=scores,rankings=self.match.complete and rules.rankings(self.match) or {},message=self.message,lastInput=self.lastInput,
    rollSummary=self.rollSummary,diagnostic=self.options.diagnostic,mascots=self.playerMascots,mascotPlayer=self.mascotPlayer}
end
function App:pause(message)
  if self.phase~='PAUSED' and self.phase~='HELP' then self.resumePhase=self.phase end
  self.phase='PAUSED'; self.message=message or 'Paused. RESUME continues this turn.'
end
function App:resume()
  self.phase=self.resumePhase or 'AIM'; self.resumePhase=nil; self.message='Ready.'
end
function App:roll()
  if self.phase~='AIM' then return end
  self.deliveryId=self.deliveryId+1
  -- Furball seeds each delivery as matchSeed + rollIndex; equal seeds replay a match exactly.
  local shot=copy(self:currentSettings()); shot.deliveryId=self.deliveryId; shot.seed=self.seed+self.deliveryId
  local sim,err=physics.begin(self.match.rack,shot)
  if not sim then self.message='Roll cancelled: '..tostring(err); return end
  self.beforeRoll={player=self.match.currentPlayer,frame=self.match.frame,ballNumber=self.match.ballNumber}
  self.skipRequested=false; self.sim=sim; self.phase='SIMULATE'; self.message='Preparing roll...'
  self:emit('release',shot)
end
-- Pins and gutters are heard as they happen in playback; the result adds the verdict.
function App:cueResult(result)
  local rolls=self.match.players[self.beforeRoll.player].rolls[self.beforeRoll.frame]
  local n=#rolls
  if rolls[n]==10 then self:cue('strike')
  elseif n>=2 and rolls[n-1]<10 and rolls[n-1]+rolls[n]==10 then self:cue('spare')
  elseif result.kind=='gutter' then self:cue('gutter')
  elseif #result.knocked==0 then self:cue('miss') end
end
function App:resolve()
  if not self.sim then return end
  local result=self.sim.result
  local accepted,err=rules.apply(self.match,self.deliveryId,result)
  if not accepted then
    self.message='Roll cancelled: '..tostring(err or (result and result.error) or 'invalid simulation')
    self.phase='AIM'; self.displaySnapshot=nil; self:emit('cancelled',result)
  else
    self.rollSummary=copy(self.beforeRoll)
    self.rollSummary.count=#result.knocked; self.rollSummary.knocked=copy(result.knocked)
    self.phase='RESULT'
    self:cueResult(result)
    local label=#result.knocked>0 and (#result.knocked..' pins') or ({gutter='gutter ball',short='short of the pins',miss='clean miss'})[result.kind] or '0 pins'
    self.message=string.format('Player %d: %s. CONTINUE when ready.',self.beforeRoll.player,label)
    self:emit('resolved',result)
  end
  self.sim=nil; self.playback=nil
end
function App:action(action)
  if not action then return end
  self.lastInput=action; self:emit('input',action)
  if action=='primary' then
    action=({SETUP='start',MASCOTS='mascot_confirm',AIM='roll',SIMULATE='noop',PLAYBACK='noop',RESULT='continue',FINAL='noop',HELP='start',PAUSED='start'})[self.phase]
  end
  if action=='quit' then
    if self.phase=='PAUSED' or self.phase=='HELP' or self.phase=='FINAL' or self.smallDisplay then self.running=false end
    return
  end
  if self.smallDisplay then return end
  if action=='pause' then
    if self.phase=='PAUSED' then self:resume() else self:pause() end
    return
  end
  if action=='help' then
    if self.phase=='HELP' then self:resume()
    else if self.phase~='PAUSED' then self.resumePhase=self.phase end; self.phase='HELP'; self.message='Controls' end
    return
  end
  if action=='start' and (self.phase=='HELP' or self.phase=='PAUSED') then self:resume(); return end
  if action=='restart' and (self.phase=='PAUSED' or self.phase=='HELP' or self.phase=='FINAL') then
    self:resetMatch(self.playerCount); self.phase='AIM'; self.message='New match. Player 1 bowls.'; self:cue('start'); self:emit('restart'); return
  end
  if self.phase=='HELP' or self.phase=='PAUSED' then return end
  if action=='view' then self.camera=({lane='deck',deck='score',score='lane'})[self.camera]; self.scorePlayer=self.match.currentPlayer; return end
  if (self.camera=='score' or self.phase=='RESULT' or self.phase=='FINAL') and (action=='select_prev' or action=='select_next') then
    self.camera='score'
    self.scorePlayer=((self.scorePlayer-1+(action=='select_next' and 1 or -1))%self.playerCount)+1; return
  end
  if self.phase=='SETUP' then
    if action=='players_up' or action=='adjust_up' then self:resetMatch(math.min(4,self.playerCount+1)); self:cue('tick')
    elseif action=='players_down' or action=='adjust_down' then self:resetMatch(math.max(1,self.playerCount-1)); self:cue('tick')
    elseif action=='start' then self.phase='MASCOTS'; self.mascotPlayer=1; self.message='Player 1: choose a mascot.' end
    return
  end
  if self.phase=='MASCOTS' then
    if action=='mascot_prev' or action=='adjust_down' then self.playerMascots[self.mascotPlayer]=(self.playerMascots[self.mascotPlayer]-2)%#mascots.list+1; self:cue('tick')
    elseif action=='mascot_next' or action=='adjust_up' then self.playerMascots[self.mascotPlayer]=self.playerMascots[self.mascotPlayer]%#mascots.list+1; self:cue('tick')
    elseif action=='mascot_confirm' or action=='start' then
      if self.mascotPlayer<self.playerCount then self.mascotPlayer=self.mascotPlayer+1; self.message='Player '..self.mascotPlayer..': choose a mascot.'
      else self.phase='AIM'; self.message='Player 1: position, aim, power, hook; ROLL.'; self:cue('start') end
    end
    return
  end
  if self.phase=='RESULT' and action=='continue' then
    self.displaySnapshot=nil; self.rollSummary=nil; self.scorePlayer=self.match.currentPlayer
    self.phase=self.match.complete and 'FINAL' or 'AIM'
    if self.match.complete then self:cue('final') end
    self.message=self.match.complete and 'Match complete.' or ('Player '..self.match.currentPlayer..' bowls next.')
    return
  end
  if self.phase=='SIMULATE' and action=='skip' then self.skipRequested=true;return end
  if self.phase=='PLAYBACK' and action=='skip' then
    self.displaySnapshot=self.sim.trajectory[#self.sim.trajectory]; self:resolve(); return
  end
  if self.phase~='AIM' then return end
  if action=='roll' then self:roll(); return end
  if action=='fine' then self.fine=not self.fine; return end
  for _,p in ipairs(parameters) do if action=='select_'..p then self.selected=p; self:cue('tick'); return end end
  if action=='select_prev' or action=='select_next' then
    for i,p in ipairs(parameters) do if self.selected==p then self.selected=parameters[((i-1+(action=='select_next' and 1 or -1))%4)+1]; self:cue('tick'); return end end
  elseif action=='adjust_up' or action=='adjust_down' then
    local p=self.selected; local bounds=limits[p]; local s=self:currentSettings()
    s[p]=math.max(bounds[1],math.min(bounds[2],s[p]+bounds[self.fine and 4 or 3]*(action=='adjust_up' and 1 or -1)))
    self:cue('tick')
  end
end
-- First pin contact crashes, later toppling clacks; the ball dropping into a gutter rumbles once.
function App:cuePlayback(p,snap)
  local down=0
  for _,pin in ipairs(snap.pins or {}) do if pin.down or (pin.tilt or 0)>0.2 then down=down+1 end end
  if down>p.down then self:cue(p.down==0 and 'crash' or 'clack'); p.down=down end
  if snap.ball and snap.ball.gutter and not p.gutter then p.gutter=true; self:cue('gutter') end
end
function App:tick(dt)
  if self.phase=='SIMULATE' then
    local done=physics.advance(self.sim,120)
    if done then
      if not self.sim.result or self.sim.result.status~='ok' then self:resolve()
      elseif self.skipRequested then self.displaySnapshot=self.sim.trajectory[#self.sim.trajectory];self:resolve()
      else self.phase='PLAYBACK'; self.playback={elapsed=0,index=1,down=0,gutter=false}; self.displaySnapshot=self.sim.trajectory[1]; self.message='Rolling... S / SKIP jumps to result.'; self:cue('release') end
    end
  elseif self.phase=='PLAYBACK' then
    local p=self.playback; p.elapsed=p.elapsed+dt
    local samples=self.sim.trajectory
    while p.index<#samples and samples[p.index+1].t<=p.elapsed do p.index=p.index+1 end
    self.displaySnapshot=samples[p.index]
    self:cuePlayback(p,self.displaySnapshot)
    if p.index>=#samples then self:resolve() end
  end
end
function App.run(options)
  options=options or {}
  local render=require('lib.render'); local input=require('lib.input')
  local original=term.current(); local fg,bg,blink=original.getTextColor(),original.getBackgroundColor(),original.getCursorBlink()
  local target,monitorName=original,nil
  if not options.terminal then
    if options.monitor then
      target=assert(peripheral.wrap(options.monitor),'Monitor not found: '..options.monitor); monitorName=options.monitor
      assert(target.isColor and target.isColor(),'Use an Advanced Monitor')
    else peripheral.find('monitor',function(name,mon) if not monitorName and mon.isColor() then target=mon;monitorName=name end end) end
  end
  local app=App.new(options); local renderer,width,height
  local function rebuild()
    if renderer then pcall(function() renderer:close() end) end
    term.redirect(target); renderer=render.new(target); width,height=target.getSize(); app.smallDisplay=width<39 or height<19
  end
  local ok,err=xpcall(function()
    rebuild()
    local timer=os.startTimer(.1)
    local function draw()
      local start=os.epoch('utc'); renderer:draw(app:view())
      app:emit('frame',{renderMs=os.epoch('utc')-start,width=width,height=height})
    end
    draw()
    while app.running do
      local event={os.pullEventRaw()}; local changed=false
      if event[1]=='terminate' then app.running=false
      elseif event[1]=='peripheral_detach' and event[2]==monitorName then
        target=original;monitorName=nil;app:pause('Monitor detached. Resume here.');rebuild();changed=true
      elseif (event[1]=='monitor_resize' and event[2]==monitorName) or (event[1]=='term_resize' and not monitorName) then
        app:pause('Display resized. Resume when ready.');rebuild();changed=true
      elseif event[1]=='timer' and event[2]==timer then
        local w,h=target.getSize()
        if monitorName and not w then
          -- The monitor vanished before its detach event arrived; fall back the same way.
          target=original;monitorName=nil;app:pause('Monitor detached. Resume here.');rebuild();changed=true
        elseif w~=width or h~=height then app:pause('Display resized. Resume when ready.');rebuild();changed=true
        else local phase=app.phase;app:tick(.1);app.sound:tick();changed=phase=='SIMULATE' or phase=='PLAYBACK' end
        timer=os.startTimer(.1)
      else
        local action=input.action(event,renderer.buttons or {},monitorName)
        if action then app:action(action);app.sound:tick();changed=true end
      end
      if app.running and changed then draw() end
    end
  end,debug.traceback)
  if renderer then pcall(function() renderer:close() end) end
  term.redirect(original);original.setTextColor(fg);original.setBackgroundColor(bg);original.setCursorBlink(blink)
  app:emit('exit',{ok=ok,error=err}); if not ok then error(err,0) end
  return app
end
return App
