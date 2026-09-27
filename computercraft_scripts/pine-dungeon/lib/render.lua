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
local goblin=box(.65,.7,.65,colors.red,colors.orange,colors.red)
local shade=box(.68,.85,.68,colors.purple,colors.red,colors.purple)
local potion=box(.45,.48,.45,colors.lime,colors.white,colors.lime)
local gold=box(.45,.35,.45,colors.yellow,colors.white,colors.orange)
local stairs=box(.78,.12,.78,colors.yellow,colors.white,colors.orange)
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
              local model,height
              if symbol=="g" then model,height=goblin,.35
              elseif symbol=="s" then model,height=shade,.42
              elseif symbol=="P" then model,height=potion,.24
              elseif symbol=="$" then model,height=gold,.18
              elseif symbol==">" then model,height=stairs,.06 end
              if model then objects[#objects+1]=frame:newObject(model,x,height,z) end
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
