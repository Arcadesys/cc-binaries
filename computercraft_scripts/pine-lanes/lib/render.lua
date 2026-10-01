local ui = require("lib.ui")
local lane = require("lib.lane")
local mascots = require("lib.mascots")
local pine = require("vendor.Pine3D")
local render = {}

local ZS = 1.0 -- furball's arcade lane is already wide enough to read; no lateral stretch
local PIN_VISUAL_SCALE = 1.0 -- furball pin proportions (1.25 tall, 0.2 belly radius)
local BALL_VISUAL_SCALE = 1.15 -- slightly fuller silhouette at terminal resolution
local function quad(x1,y1,z1,x2,y2,z2,x3,y3,z3,c)
  return {x1=x1,y1=y1,z1=z1*ZS,x2=x2,y2=y2,z2=z2*ZS,x3=x3,y3=y3,z3=z3*ZS,c=c,forceRender=true}
end
local function rect(x1,x2,z1,z2,y,c)
  return {quad(x1,y,z1,x2,y,z1,x2,y,z2,c),quad(x1,y,z1,x2,y,z2,x1,y,z2,c)}
end
local alley = require("lib.alley")
local function boardModel() return alley.sceneryModel() end
local function pinModel(angle,tilt) return alley.pinModel(angle,tilt) end
local function ballModel() return alley.ballModel(lane.ballRadius*BALL_VISUAL_SCALE) end
-- Flat chevrons along the predicted path; red once the path has dropped into a gutter.
local function previewModel(points)
  local m={}
  for i=2,#points do
    local a,b=points[i-1],points[i]
    local dx,dz=b.x-a.x,b.z-a.z; local len=math.sqrt(dx*dx+dz*dz)
    if len>0 then
      local nx,nz=-dz/len*.16,dx/len*.16
      local c=b.gutter and colors.red or colors.yellow
      local mx,mz=a.x+dx*.55,a.z+dz*.55
      m[#m+1]=quad(a.x+nx,.045,a.z+nz,mx,.045,mz,a.x-nx,.045,a.z-nz,c)
    end
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
  for c,hex in pairs(alley.palette) do if t.setPaletteColor then pcall(t.setPaletteColor,c,hex) end end
  t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
  local w,h=t.getSize(); local controls=ui.layout(w,h,"AIM")
  local sceneY=5; local sceneH=math.max(1,h-sceneY+1-controls.rowH*3)
  local frame=pine.newFrame(1,sceneY,w,sceneH); frame:setBackgroundColor(colors.gray); frame:setFoV(63)
  local objects={frame:newObject(boardModel(),0,0,0)}
  local rack=lane.newRack(); local pins={}
  local pinPose={}
  for i=1,10 do pins[i]=frame:newObject(pinModel(),rack[i].x,-.05,rack[i].z*ZS); objects[#objects+1]=pins[i]; pinPose[i]={angle=0,tilt=0,scale=PIN_VISUAL_SCALE} end
  local ball=frame:newObject(ballModel(),0,0,0)
  objects[#objects+1]=ball
  local previewObject=frame:newObject({quad(0,-1,0,0,-1,.01,.01,-1,0,colors.black)},0,-100,0)
  objects[#objects+1]=previewObject
  local previewKey
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
  -- Furball's follow camera trails the ball and stops short of the rack so the settle stays in view.
  local function cameraFor(view)
    local cam=view.camera or "lane"; local snap=view.snapshot or {}; local b=snap.ball or {}
    local bx=b.x or 0; local bz=(b.z or 0)*ZS
    if cam=="deck" then
      frame:setCamera({x=lane.headX-3.4,y=2.6,z=0,rotX=-90,rotY=0,rotZ=-26})
      frame:setFoV(62)
    elseif cam=="score" then
      frame:setCamera({x=lane.headX-2.5,y=6.5,z=bz*.3,rotX=-90,rotY=0,rotZ=-52})
      frame:setFoV(64)
    elseif view.phase~="AIM" and view.phase~="SETUP" then
      frame:setCamera({x=math.min(bx,lane.headX-4.2)-3.6,y=2.1,z=bz*.45,rotX=-90,rotY=0,rotZ=-13})
      frame:setFoV(52)
    else
      -- Setup view from behind the approach: release point, path and rack together.
      frame:setCamera({x=-8.2,y=4.6,z=0,rotX=-90,rotY=0,rotZ=-15})
      frame:setFoV(80)
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
        pins[id]:setPos(p.x or rack[id].x,-.05,(p.z or rack[id].z)*ZS)
        local angle,tilt=p.angle or 0,p.tilt or 0
        local visualScale=PIN_VISUAL_SCALE
        if math.abs(angle-pinPose[id].angle)>.01 or math.abs(tilt-pinPose[id].tilt)>.01 or visualScale~=pinPose[id].scale then
          pins[id]:setModel(pinModel(angle,tilt)); pinPose[id]={angle=angle,tilt=tilt,scale=visualScale}
        end
        pins[id]:setRot(0,0,0)
      else pins[id]:setPos(0,-100,0) end
    end
    local b=snap.ball or {x=0,y=lane.ballRadius,z=0,gutter=false}
    ball:setPos(b.x or 0,(b.y or lane.ballRadius)-lane.ballRadius-.05,(b.z or 0)*ZS)
    ball:setRot(0,0,0)
    if view.diagnostic then
      ensureAxes()
      for i,o in ipairs(axes) do
        local d=({{2.2,.035,.035},{.035,1.2,.035},{.035,.035,.72}})[i]
        o:setPos(1.7+d[1]/2,.04+d[2]/2,d[3]/2)
        o:setRot(0,0,0)
      end
    end
    -- Furball's aim arrow: the preview path, sampled from the same trajectory the kernel resolves.
    local key
    if view.preview and #view.preview>1 then
      local parts={}; for i,p in ipairs(view.preview) do parts[i]=string.format("%.3f,%.3f",p.x,p.z) end
      key=table.concat(parts,";")
    end
    if key~=previewKey then
      previewKey=key
      if key then previewObject:setModel(previewModel(view.preview)); previewObject:setPos(0,0,0)
      else previewObject:setPos(0,-100,0) end
    end
    cameraFor(view)
    t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
    frame:drawObjects(objects); frame:drawBuffer()
    local mascotPlayer=view.phase=="MASCOTS" and (view.mascotPlayer or 1) or (view.currentPlayer or 1)
    local mascotIndex=view.mascots and view.mascots[mascotPlayer]
    if mascotIndex and view.phase~="SETUP" and view.phase~="HELP" and view.phase~="PAUSED" then
      mascots.draw(t,mascotIndex,2,5,view.phase=="MASCOTS" and "P"..mascotPlayer or "READY")
    end
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
