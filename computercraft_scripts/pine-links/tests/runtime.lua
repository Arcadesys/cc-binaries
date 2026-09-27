-- Emulator integration driver. It exercises the real dispatcher and renderer
-- using queued CC key/monitor_touch events. It never changes the ball or score.
local App=require('lib.app')
local ui=require('lib.ui')
local M={}
local keyNames={start='space',swing='space',aim_left='left',aim_right='right',
  power_up='up',power_down='down',club_next='e',club_prev='q',fine='f',view='tab',
  help='h',pause='p',restart='r',skip='s',quit='backspace'}

function M.run(mode,steps)
  local monitorName=mode=='monitor' and 'pine_test' or nil
  if monitorName then assert(periphemu.create(monitorName,'monitor'),'attach emulator monitor') end
  local target=monitorName and peripheral.wrap(monitorName) or term.current()
  local before=term.current()
  local savedPalette={}
  for i=0,15 do savedPalette[2^i]={before.getPaletteColor(2^i)} end
  local index,frameCount=1,0
  local events,frames={},{}
  local completed,timeout=false,false
  local pending
  local final
  local options={terminal=not monitorName,monitor=monitorName}
  local function queue(action,app)
    if monitorName then
      local w,h=target.getSize()
      for _,b in ipairs(ui.layout(w,h,app.phase)) do
        if b.id==action then
          -- Separate deliberate test swings from the input adapter's 300 ms
          -- double-tap guard. Ordinary controls need no artificial delay.
          local event={'monitor_touch',monitorName,b.x+math.floor(b.w/2),b.y+math.floor(b.h/2)}
          if action=='swing' then pending={at=os.clock()+0.35,event=event}
          else os.queueEvent(table.unpack(event)) end
          return
        end
      end
      error('No visible monitor control for '..action..' in '..app.phase)
    else
      os.queueEvent('key',assert(keys[keyNames[action]],action),false)
    end
  end
  options.record=function(kind,data,app)
    if kind=='resolved' then
      events[#events+1]={outcome=data.outcome,position=data.position,strokes=app.state.strokes,penalties=app.state.penalties}
    elseif kind=='frame' then
      frameCount=frameCount+1; frames[#frames+1]=data.renderMs
      assert(frameCount<2000,'runtime frame limit')
      while steps[index] do
        local step=steps[index]
        if step.wait then
          if app.phase~=step.wait then return end
          if step.strokes then assert(app.state.strokes==step.strokes,'wrong stroke total at step '..index) end
          if step.penalties then assert(app.state.penalties==step.penalties,'wrong penalty total') end
          index=index+1
        elseif step.check then
          step.check(app); index=index+1
        elseif step.resize then
          assert(monitorName,'resize test requires monitor')
          local scale=target.getTextScale()==step.resize and 1 or step.resize
          target.setTextScale(scale); index=index+1; return
        elseif step.detach then
          assert(periphemu.remove(monitorName),'detach actual emulator monitor')
          monitorName=nil; target=before; index=index+1; return
        elseif step.control then
          local goal=step.control
          local action
          if not app.fine then action='fine'
          elseif goal.club and app:view().club.id~=goal.club then action='club_next'
          elseif goal.power and math.abs(app.power-goal.power)>0.005 then action=app.power<goal.power and 'power_up' or 'power_down'
          elseif goal.aim and math.abs(app.aim-goal.aim)>math.rad(0.1) then action=app.aim<goal.aim and 'aim_right' or 'aim_left' end
          if action then queue(action,app); return end
          index=index+1
        else
          index=index+1; queue(step.action,app); return
        end
      end
      queue('quit',app)
    end
  end
  parallel.waitForAll(function()
    final=App.run(options); completed=true
  end,function()
    local start=os.clock()
    while not completed do
      sleep(0.1)
      if pending and os.clock()>=pending.at then
        os.queueEvent(table.unpack(pending.event)); pending=nil
      end
      if os.clock()-start>50 then timeout=true; os.queueEvent('terminate'); return end
    end
  end)
  assert(not timeout,'runtime scenario timed out at step '..index)
  assert(index>#steps,'scenario did not finish')
  assert(term.current()==before,'terminal redirect not restored')
  for c,rgb in pairs(savedPalette) do
    local r,g,b=before.getPaletteColor(c)
    assert(math.abs(r-rgb[1])<1e-6 and math.abs(g-rgb[2])<1e-6 and math.abs(b-rgb[3])<1e-6,'terminal palette not restored')
  end
  if monitorName then periphemu.remove(monitorName) end
  return {mode=mode,frames=frames,events=events,strokes=final.state.strokes,complete=final.state.complete}
end
return M
