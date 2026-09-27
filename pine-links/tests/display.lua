-- Real Pine3D drawing and responsive control layout at supported widths.
local render=require('lib.render')
local course=require('lib.course')
local App=require('lib.app')
local original=term.current()
for _,size in ipairs({{39,19},{51,19}}) do
  local target=window.create(original,1,1,size[1],size[2],true)
  term.redirect(target)
  local r=render.new(target,course)
  local app=App.new(course,{})
  app:action('start')
  for _,camera in ipairs({'tee','overview','map'}) do
    app.camera=camera; r:draw(app:view())
    local actions={}
    for _,b in ipairs(r.buttons) do
      assert(b.x>=1 and b.y>=1 and b.x+b.w-1<=size[1] and b.y+b.h-1<=size[2],'target out of bounds')
      assert(b.w>=8 and b.h>=2,'target too small')
      actions[b.id]=true
    end
    for _,id in ipairs({'swing','aim_left','aim_right','power_up','power_down','club_prev','club_next','fine','view','help','pause'}) do assert(actions[id],'missing control '..id) end
  end
  r:close(); term.redirect(original)
  print('PASS display '..size[1]..'x'..size[2]..': three Pine3D cameras, all targets within bounds')
end
return true
