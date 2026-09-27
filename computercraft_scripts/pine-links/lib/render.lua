local ui = require("lib.ui")
local pine = require("vendor.Pine3D")
local render = {}

local function col(name, fallback)
  return colors[name] or fallback
end
local palette = {
  fairway=col("lime", colors.green), rough=col("green", colors.lime),
  green=col("cyan", colors.lightBlue), bunker=col("yellow", colors.orange),
  sand=col("yellow", colors.orange), water=col("blue", colors.cyan),
  ocean=col("blue", colors.cyan), cliff=col("gray", colors.lightGray),
  rock=col("gray", colors.lightGray), tee=col("white", colors.lightGray),
}
local function materialColor(name)
  return palette[tostring(name or "fairway"):lower()] or colors.lime
end
local function faceColor(tri)
  local a,b,c=tri.a,tri.b,tri.c
  local ux,uy,uz=b.x-a.x,b.y-a.y,b.z-a.z
  local vx,vy,vz=c.x-a.x,c.y-a.y,c.z-a.z
  local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
  local len=math.sqrt(nx*nx+ny*ny+nz*nz)
  if len>0 then nx,ny,nz=nx/len,ny/len,nz/len end
  if ny<0 then nx,ny,nz=-nx,-ny,-nz end
  local lit=math.max(0,nx*0.35+ny*0.86+nz*(-0.37))
  local name=tostring(tri.material or "fairway"):lower()
  -- Preserve distinct materials under every light angle. The former shared
  -- brightest shade turned rough, fairway and green into one lime silhouette.
  if name=='rough' then return lit<0.88 and colors.purple or colors.green end
  if name=='fairway' then return lit<0.88 and colors.brown or colors.lime end
  if name=='green' then return lit<0.88 and colors.orange or colors.cyan end
  return materialColor(name)
end
local function vec(p)
  return p or {x=0,y=0,z=0}
end
local function polygon(a,b,c,color)
  return {x1=a.x,y1=a.y,z1=a.z,x2=b.x,y2=b.y,z2=b.z,x3=c.x,y3=c.y,z3=c.z,c=color}
end
local function doubleSided(a,b,c,color)
  local p=polygon(a,b,c,color); p.forceRender=true; return p
end

local function axisBox(model,origin,x0,x1,y0,y1,z0,z1,color)
  local p={}
  for _,x in ipairs({x0,x1}) do for _,y in ipairs({y0,y1}) do for _,z in ipairs({z0,z1}) do
    p[x..":"..y..":"..z]={x=origin.x+x,y=origin.y+y,z=origin.z+z}
  end end end
  local function quad(a,b,c,d)
    model[#model+1]=doubleSided(p[a],p[b],p[c],color)
    model[#model+1]=doubleSided(p[a],p[c],p[d],color)
  end
  local function key(x,y,z) return x..":"..y..":"..z end
  quad(key(x0,y0,z0),key(x0,y0,z1),key(x0,y1,z1),key(x0,y1,z0))
  quad(key(x1,y0,z0),key(x1,y1,z0),key(x1,y1,z1),key(x1,y0,z1))
  quad(key(x0,y0,z0),key(x1,y0,z0),key(x1,y0,z1),key(x0,y0,z1))
  quad(key(x0,y1,z0),key(x0,y1,z1),key(x1,y1,z1),key(x1,y1,z0))
  quad(key(x0,y0,z0),key(x0,y1,z0),key(x1,y1,z0),key(x1,y0,z0))
  quad(key(x0,y0,z1),key(x1,y0,z1),key(x1,y1,z1),key(x0,y1,z1))
end

local function diagnosticModels(tee)
  local axes={}
  local origin={x=tee.x,y=tee.y+0.25,z=tee.z}
  axisBox(axes,origin,0,12,-0.08,0.08,-0.08,0.08,colors.red)
  axisBox(axes,origin,-0.08,0.08,0,6,-0.08,0.08,colors.white)
  axisBox(axes,origin,-0.08,0.08,-0.08,0.08,0,10,colors.magenta)
  local y=tee.y+0.3
  local tile={
    polygon({x=tee.x+12,y=y,z=tee.z-8},{x=tee.x+12,y=y,z=tee.z+8},{x=tee.x+32,y=y,z=tee.z+8},colors.lime),
    polygon({x=tee.x+12,y=y,z=tee.z-8},{x=tee.x+32,y=y,z=tee.z+8},{x=tee.x+32,y=y,z=tee.z-8},colors.green),
  }
  return axes,tile,{x=tee.x+32,y=y,z=tee.z}
end

local function makeFlag(cup)
  local x,y,z = cup.x,cup.y,cup.z
  return {
    polygon({x=x,y=y,z=z},{x=x,y=y+3,z=z},{x=x+0.8,y=y+2.6,z=z},colors.red),
    polygon({x=x-0.04,y=y,z=z},{x=x-0.04,y=y+3,z=z},{x=x+0.04,y=y+3,z=z},colors.white),
    polygon({x=x-0.04,y=y,z=z},{x=x+0.04,y=y+3,z=z},{x=x+0.04,y=y,z=z},colors.white),
  }
end

local function makeBall()
  return {
    polygon({x=-0.12,y=0,z=-0.12},{x=0.12,y=0,z=-0.12},{x=0,y=0.2,z=0.12},colors.white),
    polygon({x=0.12,y=0,z=-0.12},{x=0.12,y=0,z=0.12},{x=0,y=0.2,z=0.12},colors.lightGray),
    polygon({x=0.12,y=0,z=0.12},{x=-0.12,y=0,z=0.12},{x=0,y=0.2,z=0.12},colors.white),
    polygon({x=-0.12,y=0,z=0.12},{x=-0.12,y=0,z=-0.12},{x=0,y=0.2,z=0.12},colors.lightGray),
  }
end

local function worldPoint(x,y,z)
  -- Course and Pine3D both use X forward, Y up, Z sideways.
  return {x=x or 0,y=y or 0,z=z or 0}
end

function render.new(target, course)
  local t = term.current()
  local originalPalette = {}
  if t.getPaletteColor then
    for i=0,15 do
      local ok,r,g,b = pcall(t.getPaletteColor, 2^i)
      if ok then originalPalette[#originalPalette+1] = {2^i,r,g,b} end
    end
  end
  -- Six turf shades, separate from the cream sand and bright text. Restored on exit.
  if t.setPaletteColor then
    local shades={[colors.purple]=0x174b35,[colors.green]=0x286742,
      [colors.brown]=0x548a3d,[colors.lime]=0x77b64c,
      [colors.orange]=0x92bd63,[colors.cyan]=0xb3d980,
      [colors.yellow]=0xf3da82,[colors.blue]=0x23659e,
      [colors.lightBlue]=0x9bbddd,[colors.gray]=0x424b53}
    for c,rgb in pairs(shades) do t.setPaletteColor(c,rgb) end
  end
  local hole = course.hole or course
  local renderer = {target=target, course=course, buttons={}}
  local frame, sceneBox, objects, ballObject, axisObject, tileObject, diagnosticFlagObject
  local axisLabels
  local function build()
    local w,h = t.getSize()
    local layout=ui.layout(w,h,"AIM")
    local rowH=layout[1] and layout[1].h or 2
    local sceneH = math.max(1, h - 4 - rowH*(layout.rows or 3))
    sceneBox = {x=1,y=5,w=w,h=sceneH}
    frame = pine.newFrame(sceneBox.x,sceneBox.y,sceneBox.w,sceneBox.h)
    frame:setBackgroundColor(colors.lightBlue)
    local model={}
    local edgeCounts, edgeRefs = {}, {}
    local function edgeKey(a,b)
      local ka=string.format("%.4f,%.4f,%.4f",a.x,a.y,a.z)
      local kb=string.format("%.4f,%.4f,%.4f",b.x,b.y,b.z)
      return ka<kb and (ka.."|"..kb) or (kb.."|"..ka)
    end
    for _,tri in ipairs(hole.triangles or {}) do
      model[#model+1]=polygon(vec(tri.a),vec(tri.b),vec(tri.c),faceColor(tri))
      local sides={{tri.a,tri.b},{tri.b,tri.c},{tri.c,tri.a}}
      for _,side in ipairs(sides) do
        local k=edgeKey(side[1],side[2]); edgeCounts[k]=(edgeCounts[k] or 0)+1; edgeRefs[k]=side
      end
    end
    objects={}
    local bounds=hole.bounds or {minX=-20,maxX=127,minZ=-30,maxZ=30}
    local oceanY=(hole.waterLevel or -2)-0.25
    local x0,x1=bounds.minX-500,bounds.maxX+500
    local z0,z1=bounds.minZ-500,bounds.maxZ+500
    local ocean={
      polygon({x=x0,y=oceanY,z=z0},{x=x0,y=oceanY,z=z1},{x=x1,y=oceanY,z=z1},colors.blue),
      polygon({x=x0,y=oceanY,z=z0},{x=x1,y=oceanY,z=z1},{x=x1,y=oceanY,z=z0},colors.blue),
    }
    objects[#objects+1]=frame:newObject(ocean,0,0,0)
    local skirts={}
    for k,count in pairs(edgeCounts) do
      if count==1 then
        local edge=edgeRefs[k]
        local a,b=edge[1],edge[2]
        local dx,dz=b.x-a.x,b.z-a.z
        local length=math.sqrt(dx*dx+dz*dz)
        if course.sample and length>0 then
          local mx,mz=(a.x+b.x)/2,(a.z+b.z)/2
          local ox,oz=-dz/length*0.2,dx/length*0.2
          local plus=course.sample(mx+ox,mz+oz)~=nil
          local minus=course.sample(mx-ox,mz-oz)~=nil
          if plus~=minus then
            local ad={x=a.x,y=oceanY,z=a.z}; local bd={x=b.x,y=oceanY,z=b.z}
            skirts[#skirts+1]=doubleSided(a,b,bd,colors.gray)
            skirts[#skirts+1]=doubleSided(a,bd,ad,colors.gray)
          end
        end
      end
    end
    if #skirts>0 then objects[#objects+1]=frame:newObject(skirts,0,0,0) end
    if #model>0 then objects[#objects+1]=frame:newObject(model,0,0,0) end
    local tee=vec(hole.tee)
    local cup=vec(hole.cup)
    objects[#objects+1]=frame:newObject(makeFlag(cup),0,0,0)
    ballObject=frame:newObject(makeBall(),tee.x,tee.y,tee.z)
    objects[#objects+1]=ballObject
  end
  build()

  function renderer:resize()
    local w,h=t.getSize()
    local layout=ui.layout(w,h,"AIM")
    local rowH=layout[1] and layout[1].h or 2
    sceneBox={x=1,y=5,w=w,h=math.max(1,h-4-rowH*(layout.rows or 3))}
    if frame then frame:setSize(sceneBox.x,sceneBox.y,sceneBox.w,sceneBox.h) else build() end
  end

  local function drawScene(view)
    local ball=vec(view.ball or hole.tee)
    local tee=vec(hole.tee); local cup=vec(hole.cup)
    local w,h=t.getSize()
    if view.phase=="DIAGNOSTIC" then
      -- Face the diagnostic origin from above and from its Z-negative side so
      -- all three positive world axes separate in the projection.
      local yaw=math.deg(math.atan(28/18))
      local pitch=-math.deg(math.atan(14/math.sqrt(18*18+28*28)))
      frame:setCamera(tee.x-18,tee.y+18,tee.z-28,-90,yaw,pitch)
    elseif view.view == 'overview' then
      -- A fixed three-quarter view makes the elevation and cliff edge legible
      -- without camera motion; also useful for watching a complete shot.
      frame:setCamera(38,72,-82,-90,77,-39)
    elseif view.view == "map" then
      local bounds=hole.bounds or {minX=0,maxX=107,minZ=-12,maxZ=12}
      local cx=(bounds.minX+bounds.maxX)/2
      local cz=(bounds.minZ+bounds.maxZ)/2
      local span=math.max(bounds.maxX-bounds.minX,bounds.maxZ-bounds.minZ)
      -- Roll toward the ground and yaw 90 degrees so course X runs across the map.
      frame:setCamera(cx,span*0.9,cz,-90,90,-90)
    else
      local aim=view.aim or 0
      local d=view.phase=="SHOT_PLAYBACK" and 8 or 12
      local lift=view.phase=="SHOT_PLAYBACK" and 3.5 or 5.1
      local side=2
      local cam=worldPoint(ball.x-math.cos(aim)*d-math.sin(aim)*side,ball.y+lift,
        ball.z-math.sin(aim)*d+math.cos(aim)*side)
      local pitch=-17
      frame:setCamera(cam.x,cam.y,cam.z,-90,math.deg(aim),pitch)
    end
    ballObject:setPos(ball.x,ball.y,ball.z)
    local drawObjects=objects
    if view.phase=="DIAGNOSTIC" then
      if not axisObject then
        local tee=vec(hole.tee)
        local axes,tile,flag=diagnosticModels(tee)
        axisObject=frame:newObject(axes,0,0,0)
        tileObject=frame:newObject(tile,0,0,0)
        diagnosticFlagObject=frame:newObject(makeFlag(flag),0,0,0)
        axisLabels={
          {p=worldPoint(tee.x+12.5,tee.y+0.25,tee.z),text="X+",color=colors.red},
          {p=worldPoint(tee.x,tee.y+6.5,tee.z),text="Y+",color=colors.white},
          {p=worldPoint(tee.x,tee.y+0.25,tee.z+10.5),text="Z+",color=colors.magenta},
        }
      end
      drawObjects={}
      for i=1,#objects do drawObjects[i]=objects[i] end
      drawObjects[#drawObjects+1]=tileObject
      drawObjects[#drawObjects+1]=diagnosticFlagObject
      drawObjects[#drawObjects+1]=axisObject
    end
    frame:drawObjects(drawObjects)
    frame:drawBuffer()

    local function marker(p,glyph,fg,bg)
      local px,py,visible=frame:map3dTo2d(p.x,p.y,p.z)
      if not visible or px<0 or py<0 then return end
      -- Pine3D coordinates are sub-character pixels relative to the frame;
      -- add the frame origin before converting 2x3 pixels to terminal cells.
      local x=sceneBox.x+math.floor((px-1)/2+0.5)
      local y=sceneBox.y+math.floor((py-1)/3+0.5)
      if x>=sceneBox.x and x<sceneBox.x+sceneBox.w and y>=sceneBox.y and y<sceneBox.y+sceneBox.h then
        t.setCursorPos(x,y); t.setTextColor(fg); t.setBackgroundColor(bg); t.write(glyph)
      end
    end
    -- Oversized textual marker and shadow are deliberately HUD-only, never collision geometry.
    marker(worldPoint(ball.x,ball.y,ball.z),".",colors.gray,colors.black)
    if view.phase=="AIM" or view.phase=="DIAGNOSTIC" then
      for i=1,5 do
        local along=3+i*2
        marker(worldPoint(ball.x+math.cos(view.aim or 0)*along,ball.y+0.08,
          ball.z+math.sin(view.aim or 0)*along),".",colors.yellow,colors.black)
      end
    end
    if view.phase=="DIAGNOSTIC" and axisLabels then
      for _,label in ipairs(axisLabels) do marker(label.p,label.text,colors.black,label.color) end
    end
    marker(worldPoint(ball.x,ball.y+0.25,ball.z),"@",colors.black,colors.white)
    marker(worldPoint(cup.x,cup.y+3,cup.z),"!",colors.yellow,colors.black)
    if view.view == "map" then
      marker(worldPoint(tee.x,tee.y+0.2,tee.z),"T",colors.cyan,colors.black)
      marker(worldPoint(cup.x,cup.y+0.2,cup.z),"C",colors.yellow,colors.black)
    end
  end

  function renderer:draw(view)
    view=view or {}
    t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
    drawScene(view)
    local club=type(view.club)=="table" and view.club or nil
    local carry=club and club.carry or view.carry
    local clubName=club and club.name or view.club or "wedge"
    local row2
    if select(1,t.getSize()) >= 48 then
      row2=string.format("%s %syd  POWER %d%%  AIM %.1f deg",
        tostring(clubName):upper(), tostring(carry or "?"), math.floor((view.power or 0)*100+0.5),
        math.deg(view.aim or 0))
    else
      row2=string.format("%s %syd PWR%d%% AIM%.1f",
        tostring(clubName):upper(), tostring(carry or "?"), math.floor((view.power or 0)*100+0.5),
        math.deg(view.aim or 0))
    end
    local ball=vec(view.ball or hole.tee)
    local cup=vec(hole.cup)
    local dx,dz=cup.x-ball.x,cup.z-ball.z
    local distance=math.sqrt(dx*dx+dz*dz)
    local sampled=course.sample and course.sample(ball.x,ball.z)
    local lie=(sampled and sampled.material) or (view.result and view.result.surface) or "tee"
    local row3=string.format("TO CUP %.1f yd  LIE %s  WIND %s",
      distance,tostring(lie):upper(),tostring(view.windLabel or "CALM"))
    local title
    if view.phase=="TITLE" then title=select(1,t.getSize())>=48 and "PINE LINKS  |  PEBBLE BEACH 7" or "PINE LINKS  |  HOLE 7"
    else title=string.format("HOLE 7  PAR 3  |  STROKES %s  |  PEN %s",tostring(view.strokes or 0),tostring(view.penalties or 0)) end
    t.setCursorPos(1,1); t.setTextColor(colors.black); t.setBackgroundColor(colors.yellow); t.write(title:sub(1,select(1,t.getSize())))
    if select(2,t.getSize())>=2 then t.setCursorPos(1,2); t.setTextColor(colors.white); t.setBackgroundColor(colors.black); t.write(row2:sub(1,select(1,t.getSize()))) end
    if select(2,t.getSize())>=3 then
      t.setCursorPos(1,3); t.setTextColor(colors.white); t.setBackgroundColor(colors.black); t.write(row3:sub(1,select(1,t.getSize())))
    end
    self.buttons=ui.layout(select(1,t.getSize()),select(2,t.getSize()),view.phase)
    ui.draw(t,view,self.buttons,sceneBox.h)
  end

  function renderer:close()
    if frame and frame.buffer and frame.buffer.blitWin then pcall(frame.buffer.blitWin.setVisible,false) end
    if t.setPaletteColor then
      for _,p in ipairs(originalPalette) do pcall(t.setPaletteColor,p[1],p[2],p[3],p[4]) end
    end
    if t.setBackgroundColor then t.setBackgroundColor(colors.black) end
    if t.setTextColor then t.setTextColor(colors.white) end
    if t.clear then t.clear(); t.setCursorPos(1,1) end
  end
  return renderer
end

return render
