local net=require("lib.net")
local input=require("lib.input")
local TICK=100 -- ms per game tick
local App={};App.__index=App
local function myName()
  local label=os.getComputerLabel and os.getComputerLabel()
  return (label and label~="" and label or ("PC"..(os.getComputerID and os.getComputerID() or 0))):sub(1,8)
end
function App.new(options)
  options=options or {}
  local self=setmetatable({options=options,running=true,overlay=nil,input=input.new(),
    sound=options.sound or require("lib.sound").new()},App)
  local rn=options.rednet or rednet
  if options.join~=nil then
    self.session=net.client({rn=rn,name=myName(),hostId=type(options.join)~="boolean" and tonumber(options.join) or nil,find=options.find,now=options.now})
    self.session:join()
  else
    self.session=net.host({rn=rn,solo=options.solo,name=myName(),find=options.find,now=options.now,
      seed=options.seed or (os.epoch and os.epoch("utc")%100000 or 1)})
  end
  return self
end
function App:view()
  local v=self.session:view();v.overlay=self.overlay;return v
end
-- Sound is read off the world's per-tick events from this seat's point of view: your own
-- shots, hits and tags are loud, everyone else's are faint. A snapshot resent while the
-- game is idle repeats the last tick's events, so each tick sounds once.
function App:hearEvents()
  local s=self.session;local state=s.state
  if not state or state.tick==self.heardTick then return end
  self.heardTick=state.tick
  local me,tagged=s.mySeat,{}
  for _,e in ipairs(state.events or {}) do if e.kind=="tag" then tagged[e.seat]=true end end
  for _,e in ipairs(state.events or {}) do
    local cue
    if e.kind=="fire" then cue=e.seat==me and "fire" or "fire_far"
    elseif e.kind=="hit" then
      if not tagged[e.seat] then cue=e.seat==me and "hit" or e.by==me and "hitmark" or nil end
    elseif e.kind=="block" then cue=(e.seat==me or e.by==me) and "block" or nil
    elseif e.kind=="tag" then cue=e.by==me and "tag" or e.seat==me and "tagged" or "tag_far"
    elseif e.kind=="spawn" then cue=e.seat==me and "spawn" or nil end
    if cue then self.sound:play(cue) end
  end
end
function App:hearPhase()
  local s=self.session
  if s.phase==self.heardPhase then return end
  local was=self.heardPhase;self.heardPhase=s.phase
  if s.phase=="play" then self.heardTick=nil;self.sound:play("start")
  elseif s.phase=="over" and was=="play" then
    self.sound:play(s.state and s.state.winner==s.mySeat and "win" or "lose")
  end
end
function App:emit(kind,data)
  if self.options.record then self.options.record(kind,data,self) end
end
-- One-shot commands from keys and buttons. Returns true when the screen should redraw.
function App:command(cmd)
  local s=self.session
  if cmd=="quit" then self.running=false;return true end
  if cmd=="help" or cmd=="menu" or cmd=="scores" then
    if cmd=="scores" and s.phase~="play" then return false end
    self.overlay=self.overlay~=cmd and cmd or nil;self.input:clear();return true
  end
  if cmd=="resume" then self.overlay=nil;return true end
  if cmd=="start" and s.role=="host" and (s.phase=="lobby" or s.phase=="over") then
    self.overlay=nil;s:start();self:emit("start");self:hearPhase();return true
  end
  if cmd=="retry" and s.role=="client" and s.phase=="lost" then s:join();return true end
  return false
end
function App:mask()
  if self.overlay then return 0 end
  return self.input:mask()
end
-- Advance on the wall clock: the host steps the world, a client sends input and keepalives.
function App:update(now)
  local s=self.session;local changed=false
  self.last=self.last or now
  local steps=0
  while now-self.last>=TICK and steps<3 do
    self.last=self.last+TICK;steps=steps+1
    local before=s.phase
    if s.role=="host" then
      if s:tick(self:mask()) then changed=true;self:emit("tick",s.state);self:hearEvents() end
    elseif s:tick(self:mask()) then changed=true end
    self.input:decay()
    if s.phase~=before then changed=true end
  end
  if now-self.last>=TICK*3 then self.last=now end -- fell behind: drop time rather than spiral
  self:hearPhase()
  return changed
end
function App:handle(event)
  local kind=event[1]
  if kind=="rednet_message" then
    local r=self.session:handle(event[2],event[3],event[4])
    if r=="snap" then self:emit("snap",self.session.snap);self:hearEvents() end
    self:hearPhase()
    return r and true or false
  end
  local result=self.input:event(event,self.buttons,self.monitorName)
  if result=="held" then
    if self.session.role=="client" then self.session:tick(self:mask()) end
    return false
  end
  if result then return self:command(result) end
  return false
end
function App.run(options)
  options=options or {}
  local render=require("lib.render")
  local original=term.current()
  local fg,bg,blink=original.getTextColor(),original.getBackgroundColor(),original.getCursorBlink()
  local target,monitorName=original,nil
  if not options.terminal then
    if options.monitor then
      target=assert(peripheral.wrap(options.monitor),"Monitor not found: "..options.monitor)
      monitorName=options.monitor;assert(target.isColor and target.isColor(),"Use an Advanced Monitor")
    else peripheral.find("monitor",function(name,mon)
      if not monitorName and mon.isColor() then target=mon;monitorName=name end
    end) end
  end
  local app=App.new(options);app.monitorName=monitorName
  local renderer,width,height
  local function rebuild()
    if renderer then pcall(function() renderer:close() end) end
    term.redirect(target);renderer=render.new(target)
    width,height=target.getSize()
  end
  local ok,err=xpcall(function()
    rebuild()
    local function draw()
      local start=os.epoch("utc")
      local objects=renderer:draw(app:view())
      app.buttons=renderer.buttons
      app:emit("frame",{width=width,height=height,renderMs=os.epoch("utc")-start,objects=objects})
    end
    draw()
    local dirty=false
    local timer=os.startTimer(.05)
    while app.running do
      local event={os.pullEventRaw()}
      if event[1]=="terminate" then app.running=false
      elseif event[1]=="peripheral_detach" and event[2]==monitorName then
        target=original;monitorName=nil;app.monitorName=nil;rebuild();dirty=true
      elseif (event[1]=="monitor_resize" and event[2]==monitorName)
        or (event[1]=="term_resize" and not monitorName) then
        rebuild();dirty=true
      elseif event[1]=="timer" and event[2]==timer then
        local w,h=target.getSize()
        if w~=width or h~=height then rebuild();dirty=true end
        if app:update(os.epoch("utc")) then dirty=true end
        app.sound:tick()
        -- Draw at most once per timer so a burst of snapshots never backs up the queue.
        if dirty and app.running then draw();dirty=false end
        timer=os.startTimer(.05)
      elseif app:handle(event) then dirty=true; app.sound:tick() end
    end
  end,debug.traceback)
  pcall(function() app.session:close() end)
  if renderer then pcall(function() renderer:close() end) end
  term.redirect(original);original.setTextColor(fg);original.setBackgroundColor(bg);original.setCursorBlink(blink)
  app:emit("exit",{ok=ok,error=err})
  if not ok then error(err,0) end
  return app
end
return App
