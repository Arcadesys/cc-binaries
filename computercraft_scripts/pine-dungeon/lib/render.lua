local pine=require("vendor.Pine3D")
local world=require("lib.world")
local ui=require("lib.ui")
local render={}
local function scaled(model,sx,sy,sz)
  local out={}
  for i,p in ipairs(model) do
    local q={c=p.c,forceRender=true}
    for _,axis in ipairs({"x","y","z"}) do
      local s=axis=="x" and sx or axis=="y" and sy or sz
      for n=1,3 do q[axis..n]=p[axis..n]*s end
    end
    out[i]=q
  end
  return out
end
local function box(sx,sy,sz,color,top,side)
  return scaled(pine.models:cube({color=color,top=top or color,side=side or color,side2=side or color}),sx,sy,sz)
end
local function triangle(a,b,c,color)
  return {x1=a[1],y1=a[2],z1=a[3],x2=b[1],y2=b[2],z2=b[3],
    x3=c[1],y3=c[2],z3=c[3],c=color,forceRender=true}
end
local function flatTile(color)
  local a={-.49,-.08,-.49};local b={.49,-.08,-.49}
  local c={.49,-.08,.49};local d={-.49,-.08,.49}
  return {triangle(a,b,c,color),triangle(a,c,d,color)}
end
local floorA=flatTile(colors.brown)
local floorB=flatTile(colors.orange)
local function wallFace(facing)
  local model={}
  local function point(side,y)
    if facing=="east" then return {-.49,y,side}
    elseif facing=="west" then return {.49,y,-side}
    elseif facing=="north" then return {side,y,.49}
    else return {-side,y,-.49} end
  end
  for _,band in ipairs({{0,.16,colors.gray},{.16,1.02,colors.lightGray},
    {1.02,1.25,colors.gray}}) do
    local a=point(-.49,band[1]);local b=point(.49,band[1])
    local c=point(.49,band[2]);local d=point(-.49,band[2])
    model[#model+1]=triangle(a,b,c,band[3])
    model[#model+1]=triangle(a,c,d,band[3])
  end
  return model
end
local wallFaces={north=wallFace("north"),south=wallFace("south"),
  west=wallFace("west"),east=wallFace("east")}
local wallPost=box(.14,1.18,.14,colors.gray,colors.lightGray,colors.gray)
-- Composite Minecraft-style models: each part is a box placed on the ground (y=0).
local function translate(model,dx,dy,dz)
  for _,p in ipairs(model) do
    p.x1=p.x1+dx;p.x2=p.x2+dx;p.x3=p.x3+dx
    p.y1=p.y1+dy;p.y2=p.y2+dy;p.y3=p.y3+dy
    p.z1=p.z1+dz;p.z2=p.z2+dz;p.z3=p.z3+dz
  end
  return model
end
local function part(w,h,d,x,y,z,color,top,side)
  return translate(box(w,h,d,color,top,side),x,y+h/2,z)
end
local function merge(...)
  local out={}
  for _,model in ipairs({...}) do for _,p in ipairs(model) do out[#out+1]=p end end
  return out
end
local function mirrored(w,h,d,x,y,z,color,top,side)
  return merge(part(w,h,d,-x,y,z,color,top,side),part(w,h,d,x,y,z,color,top,side))
end
local C=colors
local zombie=merge(
  mirrored(.2,.34,.2,.12,0,0,C.blue),
  part(.46,.4,.24,0,.34,0,C.cyan,C.cyan,C.cyan),
  part(.32,.3,.3,0,.74,0,C.green,C.green,C.green),
  mirrored(.12,.12,.46,.3,.56,0,C.green))
local skeleton=merge(
  mirrored(.1,.4,.1,.1,0,0,C.lightGray),
  part(.34,.38,.14,0,.4,0,C.lightGray,C.white,C.gray),
  part(.28,.28,.28,0,.78,0,C.white,C.white,C.lightGray),
  mirrored(.08,.08,.36,.24,.62,0,C.lightGray),
  part(.06,.55,.06,.4,.3,.12,C.brown))
local function wardenModel(chest)
  return merge(
    mirrored(.3,.4,.3,.22,0,0,C.blue),
    part(.8,.7,.5,0,.4,0,C.blue,C.gray,C.blue),
    part(.84,.26,.56,0,.55,0,chest,chest,chest),
    part(.5,.36,.5,0,1.1,0,C.blue,C.gray,C.blue),
    mirrored(.1,.3,.1,.3,1.4,0,C.lightBlue),
    mirrored(.2,.7,.3,.55,.3,0,C.blue))
end
local warden=wardenModel(C.cyan)
local wardenCharging=wardenModel(C.red)
local steak=merge(
  part(.46,.12,.36,0,0,0,C.brown,C.orange,C.brown),
  part(.1,.1,.18,.3,.01,0,C.white))
local emerald=merge(
  part(.3,.1,.3,0,0,0,C.green,C.lime,C.green),
  part(.22,.1,.22,0,.1,0,C.lime,C.white,C.lime),
  part(.12,.1,.12,0,.2,0,C.white))
local ladder=merge(
  part(.8,.05,.8,0,0,0,C.black),
  mirrored(.06,.9,.06,.2,0,0,C.brown),
  part(.46,.05,.05,0,.2,0,C.orange),
  part(.46,.05,.05,0,.45,0,C.orange),
  part(.46,.05,.05,0,.7,0,C.orange))
local function portalModel(center,top)
  return merge(
    part(.92,.2,.2,0,0,.36,C.orange,C.yellow,C.orange),
    part(.92,.2,.2,0,0,-.36,C.orange,C.yellow,C.orange),
    part(.2,.2,.52,.36,0,0,C.orange,C.yellow,C.orange),
    part(.2,.2,.52,-.36,0,0,C.orange,C.yellow,C.orange),
    part(.52,.1,.52,0,.02,0,center,top,center))
end
local portalSealed=portalModel(C.black,C.black)
local portalOpen=portalModel(C.purple,C.lightBlue)
local sprites={z=zombie,k=skeleton,["%"]=steak,["$"]=emerald,[">"]=ladder}
local function savePalette(t)
  local saved={}
  if t.getPaletteColor then for i=0,15 do
    local ok,r,g,b=pcall(t.getPaletteColor,2^i)
    if ok then saved[i]={r,g,b} end
  end end
  return saved
end
function render.new(target)
  local t=target or term.current();local oldTerm=term.current()
  local saved=savePalette(t);local oldFg=t.getTextColor();local oldBg=t.getBackgroundColor()
  local palette={
    [colors.black]={.025,.035,.055},[colors.white]={.96,.95,.86},
    [colors.yellow]={.98,.79,.29},[colors.orange]={.52,.35,.23},
    [colors.brown]={.30,.21,.17},[colors.gray]={.22,.26,.34},
    [colors.lightGray]={.52,.58,.66},[colors.red]={.85,.18,.18},
    [colors.purple]={.40,.20,.52},[colors.lime]={.38,.85,.35},
    [colors.green]={.28,.52,.24},[colors.blue]={.10,.20,.36},
    [colors.cyan]={.18,.67,.70},[colors.lightBlue]={.42,.80,.98},
  }
  if t.setPaletteColor then for c,rgb in pairs(palette) do
    pcall(t.setPaletteColor,c,rgb[1],rgb[2],rgb[3])
  end end
  local w,h=t.getSize();local sceneH=math.max(1,h-3-6)
  local sceneW=math.max(1,w-14)
  local frame=pine.newFrame(1,4,sceneW,sceneH)
  frame:setBackgroundColor(colors.black);frame:setFoV(64)
  local closed=false
  local api={buttons={}}
  local function cameraFor(p)
    local yaw=({north=-90,south=90,west=180,east=0})[p.facing] or 0
    frame:setCamera({x=p.x,y=1.0,z=p.z,rotX=-90,rotY=yaw,rotZ=-8})
  end
  function api:draw(view)
    if closed then return end
    local tw,th=t.getSize()
    local buttons=ui.layout(tw,th,view.overlay or view.state.phase)
    self.buttons=buttons
    local desiredW=math.max(1,tw-14)
    local desiredH=math.max(1,th-3-(buttons.rowH or 2)*3)
    if desiredW~=sceneW or desiredH~=sceneH then
      sceneW,sceneH=desiredW,desiredH;frame:setSize(1,4,sceneW,sceneH)
    end
    t.setBackgroundColor(colors.black);t.setTextColor(colors.white);t.clear()
    if not buttons.small and not view.map and not view.overlay and view.state.phase=="play" then
      local s=view.state;local p=s.player;local objects={}
      local forward=({north={0,-1},south={0,1},west={-1,0},east={1,0}})[p.facing] or {1,0}
      for z=math.max(1,p.z-4),math.min(s.height,p.z+4) do
        for x=math.max(1,p.x-4),math.min(s.width,p.x+4) do
          local ahead=(x-p.x)*forward[1]+(z-p.z)*forward[2]
          local lateral=math.abs((x-p.x)*forward[2]-(z-p.z)*forward[1])
          if ahead>0 and lateral<=2 then
            local m=(x+z)%2==0 and floorA or floorB
            objects[#objects+1]=frame:newObject(m,x,0,z)
            if world.tile(s,x,z)=="#" then
              if lateral==0 then
                objects[#objects+1]=frame:newObject(wallFaces[p.facing],x,0,z)
              elseif ahead>=2 then
                local wx,wz=x,z
                if p.facing=="east" or p.facing=="west" then
                  wz=z+(p.z>z and .42 or -.42)
                else wx=x+(p.x>x and .42 or -.42) end
                objects[#objects+1]=frame:newObject(wallPost,wx,.59,wz)
              end
            else
              local symbol=world.symbol(s,x,z)
              local model=sprites[symbol]
              if symbol=="W" then
                local boss=world.monsterAt(s,x,z)
                model=boss and boss.charging and wardenCharging or warden
              elseif symbol=="O" then model=world.sealed(s) and portalSealed or portalOpen end
              if model then objects[#objects+1]=frame:newObject(model,x,0,z) end
            end
          end
        end
      end
      cameraFor(p);frame:drawObjects(objects);frame:drawBuffer()
    end
    ui.draw(t,view,buttons)
  end
  function api:close()
    if closed then return end;closed=true
    if frame and frame.buffer and frame.buffer.blitWin then pcall(frame.buffer.blitWin.setVisible,false) end
    if t.setPaletteColor then for i,rgb in pairs(saved) do
      pcall(t.setPaletteColor,2^i,rgb[1],rgb[2],rgb[3])
    end end
    pcall(t.setTextColor,oldFg);pcall(t.setBackgroundColor,oldBg)
    t.clear();t.setCursorPos(1,1);if term.redirect then term.redirect(oldTerm) end
  end
  return api
end
return render
