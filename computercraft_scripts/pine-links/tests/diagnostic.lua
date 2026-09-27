-- M0 event/animation proof through the actual Pine3D display path.
local App=require('lib.app')
local ui=require('lib.ui')
for _,mode in ipairs({'keyboard','monitor'}) do
  local name=mode=='monitor' and 'pine_diagnostic' or nil
  if name then assert(periphemu.create(name,'monitor')) end
  local original=term.current()
  local target=name and peripheral.wrap(name) or original
  local savedPalette={}
  for i=0,15 do savedPalette[2^i]={target.getPaletteColor(2^i)} end
  local frames,moved,echo,done=0,false,false,false
  local function action(id)
    if name then
      for _,b in ipairs(ui.layout(target.getSize(),select(2,target.getSize()),'DIAGNOSTIC')) do
        if b.id==id then os.queueEvent('monitor_touch',name,b.x,b.y); return end
      end
    end
    os.queueEvent('key',id=='view' and keys.tab or keys.backspace,false)
  end
  parallel.waitForAny(function()
    App.run({terminal=not name,monitor=name,diagnostic=true,record=function(kind,data,app)
      if kind=='input' and data=='view' then echo=true end
      if kind=='frame' then
        frames=frames+1
        if frames==1 then action('view') end
        if app.displayBall and app.displayBall.x~=app.course.hole.tee.x then moved=true end
        if echo and moved then os.queueEvent('key',keys.backspace,false) end
      end
    end}); done=true
  end,function() sleep(10); os.queueEvent('terminate') end)
  assert(done and echo and moved,'diagnostic input/motion failed: '..mode)
  assert(term.current()==original,'diagnostic did not restore terminal')
  for c,rgb in pairs(savedPalette) do
    local r,g,b=target.getPaletteColor(c)
    assert(math.abs(r-rgb[1])<1e-6 and math.abs(g-rgb[2])<1e-6 and math.abs(b-rgb[3])<1e-6,'diagnostic palette restoration')
  end
  if name then periphemu.remove(name) end
  print('PASS diagnostic '..mode..': Pine3D frames, view input echo, moving ball, clean exit')
end
return true
