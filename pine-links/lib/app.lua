-- Simulation owns shot outcomes; this controller owns commands and playback only.
local physics = require('lib.physics')
local rules = require('lib.rules')
local App = {}
App.__index = App

local function copy(p) return {x=p.x,y=p.y,z=p.z} end
local function atan2(y,x)
  if math.atan2 then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
  return y>=0 and math.pi/2 or -math.pi/2
end

function App.new(course, options)
  local self=setmetatable({course=course,options=options or {},phase='TITLE',
    fine=false,camera='tee',clubIndex=1,power=0.85,shotId=0,running=true,
    message='Hole 7 | Blue tees | Arcade practice',lastInput='Ready',fps=0},App)
  self.state=rules.new(course.hole.tee)
  self:aimAtCup()
  return self
end
function App:emit(kind, data)
  if self.options.record then self.options.record(kind,data,self) end
end
function App:aimAtCup()
  self.aim=atan2(self.course.hole.cup.z-self.state.ball.z,self.course.hole.cup.x-self.state.ball.x)
end
function App:restart()
  self.state=rules.new(self.course.hole.tee)
  self.phase='AIM'; self.clubIndex=1; self.power=0.85
  self.sim=nil; self.playback=nil; self.displayBall=nil; self.resumePhase=nil
  self:aimAtCup(); self.message='Hole 7: downhill, 107 yards. Choose power; swing.'
  self:emit('restart')
end
function App:view()
  return {ball=self.displayBall or self.state.ball, aim=self.aim,power=self.power,
    club=physics.clubs[self.clubIndex],strokes=self.state.strokes,
    penalties=self.state.penalties,phase=self.phase,message=self.message,
    view=self.camera,fine=self.fine,lastInput=self.lastInput,fps=self.fps,
    scoreName=rules.scoreName(self.state.strokes,self.course.hole.par)}
end
function App:pause(message)
  if self.phase~='PAUSED' and self.phase~='HELP' then self.resumePhase=self.phase end
  self.phase='PAUSED'; self.message=message or 'Paused. P or MENU to resume.'
end
function App:resolve()
  local result=self.sim.result
  rules.apply(self.state,self.shotId,result,self.preShot)
  self:emit('resolved',result)
  self.displayBall=nil; self.playback=nil; self.sim=nil
  if result.outcome=='error' then
    self.phase='AIM'; self.message='Shot cancelled: '..(result.message or 'simulation limit')
  elseif self.state.complete then
    self.phase='SCORECARD'
    self.message=rules.scoreName(self.state.strokes,self.course.hole.par)..' | '..self.state.strokes..' strokes'
  else
    self.phase='AIM'; self:aimAtCup()
    local sample=self.course.sample(self.state.ball.x,self.state.ball.z)
    self.message=(result.outcome=='water' or result.outcome=='ob')
      and 'Hazard: +1 penalty; returned to previous lie.'
      or ('Ball at rest: '..string.upper(sample and sample.material or 'unknown'))
    if sample and sample.material=='green' then
      for i,club in ipairs(physics.clubs) do if club.id=='putter' then self.clubIndex=i end end
      self.power=0.20
    end
  end
end
function App:action(action)
  if not action then return end
  self.lastInput=action; self:emit('input',action)
  if action=='start' and (self.phase=='HELP' or self.phase=='PAUSED') then
    self.phase=self.resumePhase or 'AIM'; self.resumePhase=nil; return
  end
  if action=='quit' then self.running=false; return end
  if action=='view' then self.camera=({tee='overview',overview='map',map='tee'})[self.camera]; return end
  if action=='help' or action=='pause' then
    if self.phase=='HELP' or self.phase=='PAUSED' then
      self.phase=self.resumePhase or 'AIM'; self.resumePhase=nil
      self.message='Arrows aim/power | Q/E club | Space swing'
    else
      self.resumePhase=self.phase; self.phase=action=='help' and 'HELP' or 'PAUSED'
    end
    return
  end
  if action=='restart' then self:restart(); return end
  if self.phase=='TITLE' then if action=='start' or action=='swing' then self:restart() end; return end
  if self.phase=='SCORECARD' then if action=='start' then self:restart() end; return end
  if action=='skip' and (self.phase=='SIMULATE' or self.phase=='SHOT_PLAYBACK') then
    self.skipPlayback=true
    if self.phase=='SHOT_PLAYBACK' then self:resolve() end
    return
  end
  if self.phase~='AIM' then return end
  local aimStep=math.rad(self.fine and 0.5 or 3)
  local powerStep=self.fine and 0.01 or 0.05
  if action=='aim_left' then self.aim=self.aim-aimStep
  elseif action=='aim_right' then self.aim=self.aim+aimStep
  elseif action=='power_up' then self.power=math.min(1,self.power+powerStep)
  elseif action=='power_down' then self.power=math.max(0.01,self.power-powerStep)
  elseif action=='fine' then self.fine=not self.fine
  elseif action=='club_next' then self.clubIndex=self.clubIndex%#physics.clubs+1
  elseif action=='club_prev' then self.clubIndex=(self.clubIndex-2)%#physics.clubs+1
  elseif action=='swing' then
    self.shotId=self.shotId+1; self.preShot=copy(self.state.ball)
    self.sim=physics.begin(self.course,{start=copy(self.state.ball),
      club=physics.clubs[self.clubIndex].id,aim=self.aim,power=self.power,wind={x=0,z=0}})
    self.phase='SIMULATE'; self.skipPlayback=false; self.message='Calculating shot...'
    self:emit('shot',{id=self.shotId,club=physics.clubs[self.clubIndex].id,power=self.power,aim=self.aim})
  end
end
function App:tick(dt)
  if self.phase=='SIMULATE' then
    if physics.advance(self.sim,120) then
      if self.skipPlayback or self.sim.result.outcome=='error' then self:resolve()
      else self.phase='SHOT_PLAYBACK'; self.playback={elapsed=0,index=1}; self.message='Ball in motion | S / SKIP to finish' end
    end
  elseif self.phase=='SHOT_PLAYBACK' then
    local playback=self.playback
    playback.elapsed=playback.elapsed+dt
    local trajectory=self.sim.trajectory
    while playback.index<#trajectory and (trajectory[playback.index+1].t or 0)<=playback.elapsed do
      playback.index=playback.index+1
    end
    self.displayBall=trajectory[playback.index]
    if playback.index>=#trajectory then self:resolve() end
  end
end

-- The only event dispatcher. Simulation runs in bounded batches between events.
function App.run(options)
  options=options or {}
  local course=require('lib.course')
  local render=require('lib.render')
  local input=require('lib.input')
  local original=term.current()
  local originalFg,originalBg=original.getTextColor(),original.getBackgroundColor()
  local originalBlink=original.getCursorBlink()
  local target,monitorName=original,nil
  if not options.terminal then
    if options.monitor then
      target=assert(peripheral.wrap(options.monitor),'Monitor not found: '..options.monitor)
      monitorName=options.monitor
      assert(target.isColor and target.isColor(),'Use an Advanced Monitor')
    else
      peripheral.find('monitor',function(name,mon)
        if not monitorName and mon.isColor() then target=mon; monitorName=name end
      end)
    end
  end
  local app=App.new(course,options)
  local renderer,displayWidth,displayHeight
  local function rebuild()
    if renderer then pcall(function() renderer:close() end) end
    term.redirect(target); renderer=render.new(target,course)
    displayWidth,displayHeight=target.getSize()
  end
  local ok,err=xpcall(function()
    rebuild()
    if options.diagnostic then app:restart(); app.phase='DIAGNOSTIC' end
    local timer=os.startTimer(0.1)
    local function draw()
      local start=os.epoch('utc')
      renderer:draw(app:view())
      local elapsed=os.epoch('utc')-start
      app.fps=elapsed>0 and math.min(10,1000/elapsed) or 10
      app:emit('frame',{renderMs=elapsed,width=select(1,target.getSize()),height=select(2,target.getSize())})
    end
    draw()
    while app.running do
      local event={os.pullEventRaw()}
      local changed=false
      if event[1]=='terminate' then app.running=false
      elseif event[1]=='peripheral_detach' and event[2]==monitorName then
        target=original; monitorName=nil
        app:pause('Monitor detached. P resumes on this computer.'); rebuild(); changed=true
      elseif (event[1]=='term_resize' and not monitorName) or (event[1]=='monitor_resize' and event[2]==monitorName) then
        app:pause('Display resized. P / MENU resumes.'); rebuild(); changed=true
      elseif event[1]=='timer' and event[2]==timer then
        local phase=app.phase
        local width,height=target.getSize()
        if width~=displayWidth or height~=displayHeight then
          -- CraftOS-PC scale changes do not emit monitor_resize.
          app:pause('Display resized. P / MENU resumes.'); rebuild(); changed=true
        elseif phase=='DIAGNOSTIC' then
          local t=os.clock(); app.displayBall={x=15+10*math.sin(t),y=course.hole.tee.y+2,z=0}
          app.message='Axes: +X toward cup | +Y up | +Z right'; changed=true
        else app:tick(0.1); changed=(phase=='SIMULATE' or phase=='SHOT_PLAYBACK') end
        timer=os.startTimer(0.1)
      else
        local action=input.action(event,renderer.buttons or {},monitorName)
        if action then
          if app.phase=='DIAGNOSTIC' then
            app.lastInput=action; app:emit('input',action)
            if action=='quit' then app.running=false elseif action=='view' then app.camera=app.camera=='tee' and 'map' or 'tee' end
          else app:action(action) end
          changed=true
        end
      end
      if app.running and changed then draw() end
    end
  end,debug.traceback)
  if renderer then pcall(function() renderer:close() end) end
  term.redirect(original)
  original.setTextColor(originalFg); original.setBackgroundColor(originalBg)
  original.setCursorBlink(originalBlink)
  app:emit('exit',{ok=ok,error=err})
  if not ok then error(err,0) end
  return app
end
return App
