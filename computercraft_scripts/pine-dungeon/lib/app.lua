local world=require("lib.world")
local App={};App.__index=App
function App.new(options)
  options=options or {}
  return setmetatable({state=world.new(),overlay=nil,map=false,running=true,
    options=options,small=false,sound=options.sound or require("lib.sound").new()},App)
end
function App:view()
  return {state=self.state,overlay=self.overlay,map=self.map}
end
function App:emit(kind,data)
  if self.options.record then self.options.record(kind,data,self) end
end
local function snapshot(state)
  local foes=0
  for _,m in ipairs(state.monsters) do if m.hp>0 then foes=foes+m.hp end end
  local p=state.player
  return {x=p.x,z=p.z,hp=p.hp,potions=p.potions,gold=p.gold,floor=state.floor,
    kills=state.kills,foes=foes}
end
-- The world is pure, so sound is read off what a turn changed. The player's own result
-- sounds at once; the monsters' reply (damage, Warden telegraphs) lands just after.
function App:hear(before,action,consumed)
  local state,sound=self.state,self.sound
  local now=snapshot(state)
  if now.floor~=before.floor then sound:play("descend")
  elseif state.phase=="won" then sound:play("win")
  elseif not consumed then sound:play("blocked")
  elseif now.kills>before.kills then sound:play(state.message:find("Warden falls",1,true) and "champion" or "kill")
  elseif now.foes<before.foes then sound:play("hit")
  elseif action=="attack" then sound:play("whiff")
  elseif action=="turn_left" or action=="turn_right" then sound:play("turn")
  elseif now.hp>before.hp and now.potions<before.potions then sound:play("heal")
  elseif now.x~=before.x or now.z~=before.z then
    sound:play("step")
    if now.gold>before.gold then sound:play("coin",120) elseif now.potions>before.potions then sound:play("steak",120) end
  end
  if now.floor~=before.floor or not consumed then return end
  local message=state.message
  if message:find("SONIC BOOM",1,true) then sound:play("boom",180)
  elseif now.hp<before.hp then sound:play("hurt",180) end
  if message:find("CHARGES",1,true) then sound:play("warn",360) end
  if message:find("roars",1,true) then sound:play("roar",360) end
  if state.phase=="lost" then sound:play("lose",600) end
end
function App:action(action)
  if not action then return false end
  if action=="quit" then self.running=false;self:emit("quit");return true end
  if self.small then return false end
  if action=="new" then
    if self.overlay or self.state.phase~="play" then
      self.state=world.new();self.overlay=nil;self.map=false;self:emit("new")
      self.sound:play("start")
      return true
    end
    return false
  end
  if action=="resume" then
    if self.overlay then self.overlay=nil;return true end
    return false
  end
  if action=="help" then
    if self.overlay=="help" then self.overlay=nil else self.overlay="help" end
    return true
  end
  if action=="menu" then
    if self.overlay=="menu" then self.overlay=nil else self.overlay="menu" end
    return true
  end
  if self.overlay or self.state.phase~="play" then return false end
  if action=="map" then self.map=not self.map;return true end
  local before=snapshot(self.state)
  local consumed=world.act(self.state,action)
  self:hear(before,action,consumed)
  if consumed then self:emit("turn",{action=action,turn=self.state.turn,
    floor=self.state.floor,hp=self.state.player.hp,phase=self.state.phase}) end
  return consumed or true -- show blocked moves and no-potion feedback
end
function App.run(options)
  options=options or {}
  local render=require("lib.render");local input=require("lib.input")
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
  local app=App.new(options);local renderer,width,height
  local function rebuild()
    if renderer then pcall(function() renderer:close() end) end
    term.redirect(target);renderer=render.new(target)
    width,height=target.getSize();app.small=width<39 or height<19
  end
  local ok,err=xpcall(function()
    rebuild()
    local function draw()
      local start=os.epoch("utc")
      renderer:draw(app:view())
      app:emit("frame",{width=width,height=height,renderMs=os.epoch("utc")-start})
    end
    draw()
    local timer=os.startTimer(.25)
    while app.running do
      local event={os.pullEventRaw()};local changed=false
      if event[1]=="terminate" then app.running=false
      elseif event[1]=="peripheral_detach" and event[2]==monitorName then
        target=original;monitorName=nil;app.overlay="menu"
        app.state.message="Monitor detached. RESUME here.";rebuild();changed=true
      elseif (event[1]=="monitor_resize" and event[2]==monitorName)
        or (event[1]=="term_resize" and not monitorName) then
        app.overlay="menu";app.state.message="Display resized. RESUME when ready."
        rebuild();changed=true
      elseif event[1]=="timer" and event[2]==timer then
        local w,h=target.getSize()
        if w~=width or h~=height then
          app.overlay="menu";app.state.message="Display resized. RESUME when ready."
          rebuild();changed=true
        end
        app.sound:tick();timer=os.startTimer(.25)
      else
        local action=input.action(event,renderer.buttons,monitorName)
        if action then changed=app:action(action);app.sound:tick() end
      end
      if app.running and changed then draw() end
    end
  end,debug.traceback)
  if renderer then pcall(function() renderer:close() end) end
  term.redirect(original);original.setTextColor(fg);original.setBackgroundColor(bg);original.setCursorBlink(blink)
  app:emit("exit",{ok=ok,error=err})
  if not ok then error(err,0) end
  return app
end
return App
