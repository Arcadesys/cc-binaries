-- Pine Arcade screen: a Pine3D carousel of emblems on pedestals above three text rows and
-- the LEFT / CENTER / RIGHT button bar. Camera on -x looking +x; +z is screen right.
local pine=require('derby.vendor.Pine3D')
local mesh=require('casino.mesh')
local emblems=require('pinearcade.emblems')
local M={}
M.minW,M.minH=26,16
M.spacing=3.3
local function line(t,y,text,fg,bg,center)
 local w,h=t.getSize(); if y>h or y<1 then return end
 if center then text=string.rep(' ',math.max(0,math.floor((w-#text)/2)))..text end
 t.setCursorPos(1,y); t.setBackgroundColor(bg or colors.black); t.setTextColor(fg or colors.white)
 t.write((text..string.rep(' ',w)):sub(1,w))
end
function M.slots(w)
 local third=math.floor(w/3)
 return {{x1=1,x2=third},{x1=third+1,x2=2*third},{x1=2*third+1,x2=w}}
end
M.barColors={{colors.black,colors.white},{colors.black,colors.yellow},{colors.white,colors.red}}
-- Ring radius that keeps neighbours M.spacing apart.
function M.radius(n) return n<2 and 0 or M.spacing/(2*math.sin(math.pi/math.max(3,n))) end
-- items: {name, title, ...}. Models are built once and swapped when the boot choice moves.
function M.new(t,items)
 assert(t.isColor(),'Pine Arcade needs an advanced colour computer or monitor')
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(1,2,w,math.max(1,h-5)); f:setBackgroundColor(colors.black)
 local floor={}
 mesh.quad(floor,{-40,-.36,-40},{40,-.36,-40},{40,-.36,40},{-40,-.36,40},colors.black,{0,1,0})
 local floorObj=f:newObject(floor,0,0,0)
 local pedestals={plain=emblems.pedestal(false),lit=emblems.pedestal(true)}
 local slots={}
 for k,item in ipairs(items) do
  slots[k]={item=item,model={},emblem=f:newObject(emblems.model(item.name,item.title,false),0,0,0),stand=f:newObject(pedestals.plain,0,0,0)}
  if item.name=='boot' then slots[k].litModel=emblems.model('boot',nil,true); slots[k].plainModel=emblems.model('boot',nil,false) end
 end
 term.redirect(old)
 local api={frame=f}
 -- v: angle (ring rotation, radians), selected, spin, zoom 0..1, boot (name lit),
 -- title, subtitle, status, highlight, options {{label}...}
 function api:draw(v)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(1,2,w,math.max(1,h-5)) end
  if w<M.minW or h<M.minH then
   t.setBackgroundColor(colors.black); t.clear(); line(t,2,' PINE ARCADE needs '..M.minW..' x '..M.minH); line(t,4,' Use a bigger screen.')
   term.redirect(previous); return
  end
  local n=#slots; local R=M.radius(n)
  -- Pull in closer when a game is chosen; wide, short frames get a wider lens.
  local aspect=w/math.max(1,h-5)
  f:setFoV(aspect>3 and 64 or aspect>2 and 56 or 50)
  local zoom=v.zoom or 0
  local d=7.2-zoom*1.5
  mesh.look(f,-R-d,2.9-zoom*.7,0,-R,1.2,0)
  local objects={floorObj}
  for k,s in ipairs(slots) do
   local a=math.pi+(v.angle or 0)-(k-1)*2*math.pi/n
   local x,z=R*math.cos(a),R*math.sin(a)
   -- Only the chosen emblem and its neighbours are drawn; the rest of the ring would
   -- sit behind them and cost frames.
   local off=math.abs((a-math.pi+math.pi)%(2*math.pi)-math.pi)
   if n<2 or off<math.min(1.5*2*math.pi/n,math.rad(100)) then
    local lit=v.boot==s.item.name
    s.stand:setModel(lit and pedestals.lit or pedestals.plain)
    if s.litModel then s.emblem:setModel(lit and s.litModel or s.plainModel) end
    s.stand:setPos(x,0,z); s.emblem:setPos(x,0,z)
    local chosen=k==v.selected
    s.emblem:setRot(0,chosen and (v.spin or 0) or 0,0)
    s.emblem:setPos(x,chosen and (v.bob or 0) or 0,z)
    objects[#objects+1]=s.stand; objects[#objects+1]=s.emblem
   end
  end
  f:drawObjects(objects); f:drawBuffer()
  line(t,1,' PINE ARCADE',colors.yellow,colors.blue)
  if v.counter then local c=v.counter..' '; t.setCursorPos(math.max(1,w-#c+1),1); t.setTextColor(colors.white); t.setBackgroundColor(colors.blue); t.write(c) end
  line(t,h-3,v.title or '',colors.yellow,colors.black,true)
  line(t,h-2,v.subtitle or '',colors.lightGray,colors.black,true)
  line(t,h-1,v.status or '',v.highlight and colors.black or colors.lime,v.highlight and colors.yellow or colors.black,true)
  for i,s in ipairs(M.slots(w)) do
   local label=v.options and v.options[i] and v.options[i].label or ''
   local width=s.x2-s.x1+1; local lp=math.max(0,math.floor((width-#label)/2))
   local fg,bg=M.barColors[i][1],M.barColors[i][2]
   if label=='' then fg,bg=colors.gray,colors.black end
   t.setCursorPos(s.x1,h); t.setTextColor(fg); t.setBackgroundColor(bg)
   t.write((string.rep(' ',lp)..label..string.rep(' ',width)):sub(1,width))
  end
  term.redirect(previous)
 end
 return api
end
return M
