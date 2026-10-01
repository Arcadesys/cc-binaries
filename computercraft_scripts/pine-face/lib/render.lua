local pine=require("vendor.Pine3D")
local world=require("lib.world")
local ui=require("lib.ui")
local render={}
local C=colors
local function tri(a,b,c,color)
  return {x1=a[1],y1=a[2],z1=a[3],x2=b[1],y2=b[2],z2=b[3],x3=c[1],y3=c[2],z3=c[3],c=color,forceRender=true}
end
local function quad(m,a,b,c,d,color)
  m[#m+1]=tri(a,b,c,color);m[#m+1]=tri(a,c,d,color)
end
local function cube(m,x0,y0,z0,x1,y1,z1,color)
  local p={{x0,y0,z0},{x1,y0,z0},{x1,y1,z0},{x0,y1,z0},{x0,y0,z1},{x1,y0,z1},{x1,y1,z1},{x0,y1,z1}}
  for _,f in ipairs({{1,2,3,4},{5,6,7,8},{1,2,6,5},{4,3,7,8},{1,4,8,5},{2,3,7,6}}) do
    quad(m,p[f[1]],p[f[2]],p[f[3]],p[f[4]],color)
  end
  return m
end
render.EYE=.45
-- A faceted Smiley ball facing +x, centred at eye height so faces meet you eye to eye.
local function smiley(color)
  local m={};local R=.34;local cy=render.EYE;local slices,stacks=8,4
  local function at(i,j)
    local lat=math.pi*(j/stacks-.5);local lon=2*math.pi*i/slices
    return {math.cos(lat)*math.cos(lon)*R,cy+math.sin(lat)*R,math.cos(lat)*math.sin(lon)*R}
  end
  for j=0,stacks-1 do for i=0,slices-1 do
    local a,b,c,d=at(i,j),at(i+1,j),at(i+1,j+1),at(i,j+1)
    if j==0 then m[#m+1]=tri(a,c,d,color) elseif j==stacks-1 then m[#m+1]=tri(a,b,c,color)
    else quad(m,a,b,c,d,color) end
  end end
  local f=R*.97
  cube(m,f-.02,cy+.05,-.14,f+.04,cy+.17,-.06,C.black)
  cube(m,f-.02,cy+.05,.06,f+.04,cy+.17,.14,C.black)
  cube(m,f-.03,cy-.16,-.13,f+.03,cy-.1,.13,C.black)
  cube(m,f-.06,cy-.12,-.19,f+.02,cy-.04,-.12,C.black)
  cube(m,f-.06,cy-.12,.12,f+.02,cy-.04,.19,C.black)
  return m
end
local seatColor={C.yellow,C.cyan,C.lime,C.red}
render.seatColor=seatColor
local smileys,shielded={},{}
for i,c in ipairs(seatColor) do smileys[i]=smiley(c);shielded[i]=smiley(C.white) end
local bulletModel=cube({},-.07,render.EYE-.07,-.07,.07,render.EYE+.07,.07,C.white)
-- Wall face on the shared edge between a wall tile and the open tile (ox,oz) beside it.
local function wallFace(dx,dz)
  local m={}
  local function pt(s,y)
    if dx~=0 then return {dx*.5,y,s} else return {s,y,dz*.5} end
  end
  for _,band in ipairs({{0,.08,C.purple},{.08,.82,C.blue},{.82,1,C.lightBlue}}) do
    quad(m,pt(-.5,band[1]),pt(.5,band[1]),pt(.5,band[2]),pt(-.5,band[2]),band[3])
  end
  return m
end
local faceModels={}
for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do faceModels[d[1]..","..d[2]]=wallFace(d[1],d[2]) end
local function floorTile(color)
  local m={};quad(m,{-.5,0,-.5},{.5,0,-.5},{.5,0,.5},{-.5,0,.5},color);return m
end
local floorA,floorB=floorTile(C.gray),floorTile(C.brown)
local function savePalette(t)
  local saved={}
  if t.getPaletteColor then for i=0,15 do
    local ok,r,g,b=pcall(t.getPaletteColor,2^i)
    if ok then saved[i]={r,g,b} end
  end end
  return saved
end
render.palette={
  [C.black]={.03,.03,.08},[C.white]={.97,.97,.97},[C.yellow]={1,.86,.1},
  [C.cyan]={.15,.85,.9},[C.lime]={.35,.9,.3},[C.red]={.95,.25,.3},
  [C.gray]={.24,.25,.3},[C.brown]={.32,.33,.4},[C.lightGray]={.6,.62,.68},
  [C.blue]={.16,.28,.78},[C.lightBlue]={.45,.65,1},[C.purple]={.3,.16,.55},
  [C.orange]={1,.55,.15},[C.pink]={.55,.08,.12},
}
local VIEW=8
function render.new(target)
  local t=target or term.current();local oldTerm=term.current()
  local saved=savePalette(t);local oldFg,oldBg=t.getTextColor(),t.getBackgroundColor()
  if t.setPaletteColor then for c,rgb in pairs(render.palette) do pcall(t.setPaletteColor,c,rgb[1],rgb[2],rgb[3]) end end
  local layout=ui.layout(t.getSize())
  local scene=layout.scene
  local frame=pine.newFrame(scene.x,scene.y,scene.w,scene.h)
  frame:setBackgroundColor(C.black);frame:setFoV(70)
  local closed=false;local api={buttons={}}
  -- Static geometry is built once; each frame only picks what is near and in front.
  local walls,floors,players,bullets=nil,nil,{},{}
  local function build(state)
    walls,floors={},{}
    for z=1,state.height do for x=1,state.width do
      if world.tile(state,x,z)=="#" then
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
          if world.tile(state,x+d[1],z+d[2])~="#" then
            walls[#walls+1]={x=x+d[1]*.5,z=z+d[2]*.5,nx=d[1],nz=d[2],
              obj=frame:newObject(faceModels[d[1]..","..d[2]],x,0,z)}
          end
        end
      else
        floors[#floors+1]={x=x,z=z,obj=frame:newObject((x+z)%2==0 and floorA or floorB,x,0,z)}
      end
    end end
    for i=1,world.SEATS do
      players[i]={normal=frame:newObject(smileys[i],0,0,0),shield=frame:newObject(shielded[i],0,0,0)}
      bullets[i]=frame:newObject(bulletModel,0,0,0)
    end
  end
  local function drawScene(view)
    local s=view.state;local me=s.players[view.mySeat or 1]
    if not walls then build(s) end
    local yaw=math.rad(me.yaw);local fx,fz=math.cos(yaw),math.sin(yaw)
    local cx,cz=me.x-fx*.05,me.z-fz*.05
    local objects={}
    local function ahead(x,z,slack)
      local dx,dz=x-cx,z-cz
      return dx*dx+dz*dz<VIEW*VIEW and dx*fx+dz*fz>-slack
    end
    for _,f in ipairs(floors) do if ahead(f.x,f.z,.8) then objects[#objects+1]=f.obj end end
    for _,w in ipairs(walls) do
      if ahead(w.x,w.z,.8) and (cx-w.x)*w.nx+(cz-w.z)*w.nz>0 then objects[#objects+1]=w.obj end
    end
    for i,p in ipairs(s.players) do
      if i~=view.mySeat and p.alive and ahead(p.x,p.z,.4) then
        local o=(p.shield or 0)>0 and s.tick%2==0 and players[i].shield or players[i].normal
        o:setPos(p.x,0,p.z);o:setRot(0,-math.rad(p.yaw),0)
        objects[#objects+1]=o
      end
    end
    for seat,b in pairs(s.bullets) do
      if ahead(b.x,b.z,.2) then bullets[seat]:setPos(b.x,0,b.z);objects[#objects+1]=bullets[seat] end
    end
    local flash=false
    for _,e in ipairs(s.events or {}) do if e.seat==view.mySeat and (e.kind=="hit" or e.kind=="tag") then flash=true end end
    frame:setBackgroundColor(flash and C.pink or C.black)
    frame:setCamera({x=cx,y=render.EYE+.05,z=cz,rotX=-90,rotY=me.yaw,rotZ=0})
    frame:drawObjects(objects);frame:drawBuffer()
    return #objects
  end
  function api:draw(view)
    if closed then return end
    local tw,th=t.getSize()
    local layout=ui.layout(tw,th,view)
    self.buttons=layout.buttons
    local sc=layout.scene
    if sc and (sc.x~=scene.x or sc.y~=scene.y or sc.w~=scene.w or sc.h~=scene.h) then
      scene=sc;frame:setSize(sc.x,sc.y,sc.w,sc.h)
    end
    t.setBackgroundColor(C.black);t.setTextColor(C.white);t.clear()
    local count
    if layout.showScene and view.state then count=drawScene(view) end
    ui.draw(t,view,layout)
    return count
  end
  function api:close()
    if closed then return end;closed=true
    if frame and frame.buffer and frame.buffer.blitWin then pcall(frame.buffer.blitWin.setVisible,false) end
    if t.setPaletteColor then for i,rgb in pairs(saved) do pcall(t.setPaletteColor,2^i,rgb[1],rgb[2],rgb[3]) end end
    pcall(t.setTextColor,oldFg);pcall(t.setBackgroundColor,oldBg)
    t.clear();t.setCursorPos(1,1);if term.redirect then term.redirect(oldTerm) end
  end
  return api
end
return render
