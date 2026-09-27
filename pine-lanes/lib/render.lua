local ui = require("lib.ui")
local lane = require("lib.lane")
local pine = require("vendor.Pine3D")
local render = {}

local ZS = 3.0 -- spread lane features and object positions, not object geometry
local PIN_VISUAL_SCALE = 1.8 -- modest display-only stylization for terminal resolution; physics stays exact
local BALL_VISUAL_SCALE = 1.6 -- readable round silhouette above the lane surface
local function quad(x1,y1,z1,x2,y2,z2,x3,y3,z3,c)
  return {x1=x1,y1=y1,z1=z1*ZS,x2=x2,y2=y2,z2=z2*ZS,x3=x3,y3=y3,z3=z3*ZS,c=c,forceRender=true}
end
local function rect(x1,x2,z1,z2,y,c)
  return {quad(x1,y,z1,x2,y,z1,x2,y,z2,c),quad(x1,y,z1,x2,y,z2,x1,y,z2,c)}
end
local function boardModel()
  local m={}
  local left,right=-lane.width/2,lane.width/2
  -- dark approach and foul stripe
  for _,p in ipairs(rect(-5,0,-.72,.72,0,colors.gray)) do m[#m+1]=p end
  for _,p in ipairs(rect(-.06,.06,-.55,.55,.015,colors.white)) do m[#m+1]=p end
  -- Individual maple boards with alternating tones, seams and arrows.
  local shades={colors.brown,colors.orange}
  for board=0,14 do
    local z1=left+(right-left)*board/15
    local z2=left+(right-left)*(board+1)/15
    local c=shades[board%2+1]
    for _,p in ipairs(rect(0,lane.endX,z1,z2,.02,c)) do m[#m+1]=p end
  end
  -- Side gutters and rails, with contrasting dark troughs and bright edges.
  for side=-1,1,2 do
    local inner=side*right; local outer=side*(right+lane.gutterWidth)
    local mid=(inner+outer)/2
    for _,p in ipairs(rect(0,lane.endX,math.min(inner,mid),math.max(inner,mid),-.08,colors.gray)) do m[#m+1]=p end
    for _,p in ipairs(rect(0,lane.endX,math.min(mid,outer),math.max(mid,outer),-.16,colors.black)) do m[#m+1]=p end
    for _,p in ipairs(rect(0,lane.endX,outer-.012,outer+.012,-.03,colors.lightGray)) do m[#m+1]=p end
  end
  -- pin deck
  for _,p in ipairs(rect(17.8,21,-.65,.65,.01,colors.brown)) do m[#m+1]=p end
  -- Dark pinsetter backboard frames the white rack and closes the far end.
  m[#m+1]=quad(21.12,0,-1.05,21.12,1.8,-1.05,21.12,1.8,1.05,colors.gray)
  m[#m+1]=quad(21.12,0,-1.05,21.12,1.8,1.05,21.12,0,1.05,colors.black)
  return m
end

local function pinModel(angle,tilt,visualScale)
  angle,tilt=angle or 0,tilt or 0
  visualScale=visualScale or PIN_VISUAL_SCALE
  local m={}; local r=lane.pinRadius; local h=lane.pinHeight
  local rings={{0,r*.50},{h*.09,r*.65},{h*.29,r},{h*.52,r*.70},{h*.71,r*.42},{h*.89,r*.30},{h,r*.44}}
  local sa,ca=math.sin(angle),math.cos(angle)
  local st,ct=math.sin(tilt),math.cos(tilt)
  local ax,ay,az=st*ca,ct,st*sa
  local ux,uy,uz=ct*ca,-st,ct*sa
  local vx,vy,vz=-sa,0,ca
  local function point(x,y,z)
    x,y,z=x*visualScale,y*visualScale,z*visualScale
    return ax*y+ux*x+vx*z, ay*y+uy*x+vy*z, az*y+uz*x+vz*z
  end
  local function tri(x1,y1,z1,x2,y2,z2,x3,y3,z3,c)
    local ax1,ay1,az1=point(x1,y1,z1); local ax2,ay2,az2=point(x2,y2,z2); local ax3,ay3,az3=point(x3,y3,z3)
    m[#m+1]={x1=ax1,y1=ay1,z1=az1,x2=ax2,y2=ay2,z2=az2,x3=ax3,y3=ay3,z3=az3,c=c,forceRender=true}
  end
  local n=8
  for r=1,#rings-1 do
    local y1,a=rings[r][1],rings[r][2]; local y2,b=rings[r+1][1],rings[r+1][2]
    for j=0,n-1 do
      local q1=j*math.pi*2/n; local q2=(j+1)*math.pi*2/n
      local lit=math.sin((q1+q2)/2)>.15
      local c=(r==5 or r==6) and (lit and colors.red or colors.purple)
        or (lit and colors.white or colors.lightGray)
      local x1,z1=math.cos(q1)*a,math.sin(q1)*a
      local x2,z2=math.cos(q2)*a,math.sin(q2)*a
      local x3,z3=math.cos(q2)*b,math.sin(q2)*b
      local x4,z4=math.cos(q1)*b,math.sin(q1)*b
      tri(x1,y1,z1,x2,y1,z2,x3,y2,z3,c)
      tri(x1,y1,z1,x3,y2,z3,x4,y2,z4,c)
    end
  end
  -- Close the crown so the near/deck camera sees a solid pin, not an open tube.
  local topY,topR=rings[#rings][1],rings[#rings][2]
  for j=0,n-1 do
    local q1=j*math.pi*2/n; local q2=(j+1)*math.pi*2/n
    tri(0,topY,0,math.cos(q1)*topR,topY,math.sin(q1)*topR,
      math.cos(q2)*topR,topY,math.sin(q2)*topR,colors.white)
  end
  return m
end
local function scaleModel(model,sx,sy,sz)
  local out={}
  for i,p in ipairs(model) do
    local q={c=p.c,forceRender=true}
    for _,axis in ipairs({"x","y","z"}) do
      local s=axis=="x" and sx or axis=="y" and sy or sz
      for j=1,3 do local k=axis..j; q[k]=p[k]*s end
    end
    out[i]=q
  end
  return out
end
local function ballModel()
  local diameter=lane.ballRadius*2*BALL_VISUAL_SCALE
  local mesh=pine.models:sphere({res=10,color=colors.green})
  for _,face in ipairs(mesh) do
    local x=(face.x1+face.x2+face.x3)/3
    local y=(face.y1+face.y2+face.y3)/3
    local z=(face.z1+face.z2+face.z3)/3
    local length=math.sqrt(x*x+y*y+z*z)
    local light=length>0 and (y+.55*z-.25*x)/length or 0
    face.c=light>.45 and colors.lime or (light>-.2 and colors.cyan or colors.green)
  end
  return scaleModel(mesh,diameter,diameter,diameter)
end
local function paletteSave(t)
  local saved={}
  if t.getPaletteColor then
    for i=0,15 do local ok,r,g,b=pcall(t.getPaletteColor,2^i); if ok then saved[i]={r,g,b} end end
  end
  local fg,bg
  if t.getTextColor then fg=t.getTextColor() end
  if t.getBackgroundColor then bg=t.getBackgroundColor() end
  return saved,fg,bg
end
function render.new(target)
  local t=target or term.current(); local oldTerm=term.current(); local oldW,oldH=t.getSize()
  local saved,oldFg,oldBg=paletteSave(t)
  local colorset={ [colors.black]={.035,.045,.065},[colors.brown]={.36,.20,.10},[colors.orange]={.72,.40,.19},
    [colors.yellow]={.95,.75,.35},[colors.red]={.82,.12,.15},[colors.purple]={.43,.08,.11},
    [colors.lightGray]={.68,.70,.73},[colors.gray]={.24,.27,.33},
    [colors.white]={.96,.96,.91},[colors.lime]={.42,.85,.28},[colors.cyan]={.24,.66,.27},
    [colors.green]={.12,.45,.20},[colors.lightBlue]={.17,.33,.47} }
  for c,rgb in pairs(colorset) do if t.setPaletteColor then pcall(t.setPaletteColor,c,rgb[1],rgb[2],rgb[3]) end end
  t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
  local w,h=t.getSize(); local controls=ui.layout(w,h,"AIM")
  local sceneY=5; local sceneH=math.max(1,h-sceneY+1-controls.rowH*3)
  local frame=pine.newFrame(1,sceneY,w,sceneH); frame:setBackgroundColor(colors.black); frame:setFoV(63)
  local objects={frame:newObject(boardModel(),0,0,0)}
  local rack=lane.newRack(); local pins={}
  local pinPose={}
  for i=1,10 do pins[i]=frame:newObject(pinModel(),rack[i].x,0,rack[i].z*ZS); objects[#objects+1]=pins[i]; pinPose[i]={angle=0,tilt=0,scale=PIN_VISUAL_SCALE} end
  local ball=frame:newObject(ballModel(),0,lane.ballRadius*BALL_VISUAL_SCALE,0)
  objects[#objects+1]=ball
  local axes={}; local axesLabels={}
  local function ensureAxes()
    if #axes>0 then return end
    -- Small flat inspection tile plus three solid world-space rods from one origin.
    local tile=frame:newObject({unpack(rect(1,4,-.75,.75,-.01,colors.lightGray))},0,0,0); objects[#objects+1]=tile
    local rodDefs={{"X",colors.red,2.2,.035,.035},{"Y",colors.lime,.035,1.2,.035},{"Z",colors.blue,.035,.035,.72}}
    for _,d in ipairs(rodDefs) do
      local model=scaleModel(pine.models:cube({color=d[2],top=d[2]}),d[3],d[4],d[5])
      local o=frame:newObject(model,0,0,0); axes[#axes+1]=o; objects[#objects+1]=o
    end
    axesLabels={{"X+",3.25,.08,0},{"Y+",1.75,.35,0},{"Z+",1.75,.08,.2}}
  end
  local closed=false
  local api={buttons={}}
  local function cameraFor(view)
    local cam=view.camera or "lane"; local s=view.settings or {}; local snap=view.snapshot or {}; local b=snap.ball or {}
    local bx=b.x or -1.5; local bz=(b.z or s.position or 0)*ZS
    local yaw=math.deg(s.aim or 0)
    if cam=="deck" then
      frame:setCamera({x=15.5,y=1.4,z=0,rotX=-90,rotY=0,rotZ=-22})
      frame:setFoV(72)
    elseif cam=="score" then
      frame:setCamera({x=16.2,y=5.8,z=bz,rotX=-90,rotY=0,rotZ=-27})
      frame:setFoV(64)
    else
      frame:setCamera({x=math.min(bx,15)-3.5,y=.5,z=bz,rotX=-90,rotY=yaw,rotZ=-4})
      frame:setFoV(42)
    end
  end
  function api:draw(view)
    if closed then return end
    local tw,th=t.getSize()
    if tw~=oldW or th~=oldH then
      oldW,oldH=tw,th; controls=ui.layout(tw,th,view.phase,view.camera)
      sceneH=math.max(1,th-4-controls.rowH*3); frame:setSize(1,sceneY,tw,sceneH)
    else controls=ui.layout(tw,th,view.phase,view.camera) end
    for _,button in ipairs(controls) do
      if button.id=="fine" then button.label=view.fine and "FINE ON" or "FINE OFF" end
    end
    self.buttons=controls
    local snap=view.snapshot or {}; local poses=snap.pins
    if poses==nil then poses=lane.newRack() end
    local byId={}; for _,p in ipairs(poses) do byId[p.id]=p end
    for id=1,10 do
      local p=byId[id]
      if p then
        pins[id]:setPos(p.x or rack[id].x,0,(p.z or rack[id].z)*ZS)
        local angle,tilt=p.angle or 0,p.tilt or 0
        local visualScale=view.camera=="deck" and 1.3 or PIN_VISUAL_SCALE
        if math.abs(angle-pinPose[id].angle)>.01 or math.abs(tilt-pinPose[id].tilt)>.01 or visualScale~=pinPose[id].scale then
          pins[id]:setModel(pinModel(angle,tilt,visualScale)); pinPose[id]={angle=angle,tilt=tilt,scale=visualScale}
        end
        pins[id]:setRot(0,0,0)
      else pins[id]:setPos(0,-100,0) end
    end
    local b=snap.ball or {x=-1.5,y=lane.ballRadius,z=(view.settings and view.settings.position) or 0,gutter=false}
    ball:setPos(b.x or -1.5,(b.y or lane.ballRadius)+(BALL_VISUAL_SCALE-1)*lane.ballRadius,(b.z or 0)*ZS)
    ball:setRot(0,0,0)
    if view.diagnostic then
      ensureAxes()
      for i,o in ipairs(axes) do
        local d=({{2.2,.035,.035},{.035,1.2,.035},{.035,.035,.72}})[i]
        o:setPos(1.7+d[1]/2,.04+d[2]/2,d[3]/2)
        o:setRot(0,0,0)
      end
    end
    cameraFor(view)
    t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
    frame:drawObjects(objects); frame:drawBuffer()
    ui.draw(t,view,controls)
    if view.diagnostic then
      for _,lab in ipairs(axesLabels) do
        local x,y,visible=frame:map3dTo2d(lab[2],lab[3],lab[4]*ZS)
        if visible then
          local px=math.floor(x/2+.5); local py=sceneY+math.floor(y/3+.5)
          if py>=sceneY and py<sceneY+sceneH and px>=1 and px<=tw-2 then
            t.setCursorPos(px,py); t.setTextColor(lab[1]=="X+" and colors.red or lab[1]=="Y+" and colors.lime or colors.blue); t.setBackgroundColor(colors.black); t.write(lab[1])
          end
        end
      end
    end
    t.setCursorPos(1,th)
  end
  function api:close()
    if closed then return end; closed=true
    if frame and frame.buffer and frame.buffer.blitWin then pcall(frame.buffer.blitWin.setVisible,false) end
    for i,rgb in pairs(saved) do if t.setPaletteColor then pcall(t.setPaletteColor,2^i,rgb[1],rgb[2],rgb[3]) end end
    if oldFg then pcall(t.setTextColor,oldFg) end; if oldBg then pcall(t.setBackgroundColor,oldBg) end
    t.clear(); t.setCursorPos(1,1); if term.redirect then term.redirect(oldTerm) end
  end
  return api
end
render._testPinModel=pinModel
render._testBallModel=ballModel
return render
