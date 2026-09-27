-- Deterministic bowling-ball and ten-pin simulation; independent of CC/render.
local lane = require("lib.lane")
local physics = {
  step = 1/120,
  snapshotInterval = 1/30,
  maxDuration = 12,
  maxBatch = 120,
  rollingDrag = 0.15,
  hookAcceleration = 0.6,
}

local function finite(n)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local atan2=math.atan2 or function(y,x) return math.atan(y,x) end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function copyPose(p)
  return {id=p.id,x=p.x,z=p.z,angle=p.angle or 0,tilt=p.tilt or 0,down=p.down==true}
end
local function copyPins(pins)
  local out={}
  for i,p in ipairs(pins) do out[i]=copyPose(p) end
  return out
end
local function copyBall(b)
  return {x=b.x,y=b.y,z=b.z,gutter=b.gutter}
end

local function validateRack(rack)
  if type(rack)~="table" or #rack>10 then return nil,"rack must be an array of at most ten pins" end
  local seen, out = {}, {}
  for i,p in ipairs(rack) do
    if type(p)~="table" or not finite(p.id) or p.id%1~=0 or p.id<1 or p.id>10 then return nil,"invalid pin id" end
    if seen[p.id] then return nil,"duplicate pin id" end
    if not finite(p.x) or not finite(p.z) then return nil,"pin coordinates must be finite" end
    if not finite(p.angle or 0) or not finite(p.tilt or 0) then return nil,"pin orientation must be finite" end
    seen[p.id]=true
    out[i]=copyPose(p)
    out[i].tilt=clamp(out[i].tilt,0,math.pi/2)
  end
  return out
end

local function pinAxis(p)
  local length=lane.pinHeight*math.sin(p.tilt)
  return p.x,p.z,p.x+length*math.cos(p.angle),p.z+length*math.sin(p.angle)
end
local function pinAxis3(p)
  local length=lane.pinHeight*math.sin(p.tilt)
  return p.x,lane.pinRadius,p.z,
    p.x+length*math.cos(p.angle),lane.pinRadius+lane.pinHeight*math.cos(p.tilt),p.z+length*math.sin(p.angle)
end

local function pointSegment(px,pz,ax,az,bx,bz)
  local dx,dz=bx-ax,bz-az
  local d=dx*dx+dz*dz
  local t=0
  if d>1e-12 then t=clamp(((px-ax)*dx+(pz-az)*dz)/d,0,1) end
  local x,z=ax+t*dx,az+t*dz
  return x,z,(px-x)^2+(pz-z)^2
end

local function pointSegment3(px,py,pz, ax,ay,az,bx,by,bz)
  local dx,dy,dz=bx-ax,by-ay,bz-az
  local d=dx*dx+dy*dy+dz*dz
  local t=0
  if d>1e-12 then t=clamp(((px-ax)*dx+(py-ay)*dy+(pz-az)*dz)/d,0,1) end
  local x,y,z=ax+t*dx,ay+t*dy,az+t*dz
  return x,y,z,(px-x)^2+(py-y)^2+(pz-z)^2,t
end

local function closestSegments3(a0x,a0y,a0z,a1x,a1y,a1z,b0x,b0y,b0z,b1x,b1y,b1z)
  local ux,uy,uz=a1x-a0x,a1y-a0y,a1z-a0z
  local vx,vy,vz=b1x-b0x,b1y-b0y,b1z-b0z
  local uu=ux*ux+uy*uy+uz*uz
  local vv=vx*vx+vy*vy+vz*vz
  local s,t=0,0
  for _=1,12 do
    local px,py,pz=a0x+s*ux,a0y+s*uy,a0z+s*uz
    if vv>1e-12 then t=clamp(((px-b0x)*vx+(py-b0y)*vy+(pz-b0z)*vz)/vv,0,1) else t=0 end
    local qx,qy,qz=b0x+t*vx,b0y+t*vy,b0z+t*vz
    if uu>1e-12 then s=clamp(((qx-a0x)*ux+(qy-a0y)*uy+(qz-a0z)*uz)/uu,0,1) else s=0 end
  end
  local ax,ay,az=a0x+s*ux,a0y+s*uy,a0z+s*uz
  local bx,by,bz=b0x+t*vx,b0y+t*vy,b0z+t*vz
  local dx,dy,dz=bx-ax,by-ay,bz-az
  return ax,ay,az,bx,by,bz,s,t,dx*dx+dy*dy+dz*dz
end

local function snapshot(sim)
  local pins={}
  for i,p in ipairs(sim.pins) do
    pins[i]={id=p.id,x=p.x,z=p.z,angle=p.angle,tilt=p.tilt,down=p.down}
  end
  return {t=sim.time,ball=copyBall(sim.ball),pins=pins}
end

local function appendSnapshot(sim,force)
  local last=sim.trajectory[#sim.trajectory]
  if not last or (force and sim.time-last.t>1e-9)
    or (not force and sim.time-last.t>=physics.snapshotInterval-1e-8) then
    sim.trajectory[#sim.trajectory+1]=snapshot(sim)
  end
end

local function resultFor(sim,status,message)
  sim.done=true
  local knocked,standing={},{}
  if status=="ok" then
    for _,p in ipairs(sim.pins) do
      local pose=copyPose(p)
      if p.down then knocked[#knocked+1]=p.id else standing[#standing+1]=pose end
    end
  end
  sim.result={deliveryId=sim.shot.deliveryId,status=status,knocked=knocked,standing=standing,duration=sim.time}
  if message then sim.result.error=message end
  appendSnapshot(sim,true)
  return true
end

local function validState(sim)
  local b=sim.ball
  if not finite(b.x) or not finite(b.y) or not finite(b.z) or not finite(sim.vx) or not finite(sim.vz) then return false end
  for _,p in ipairs(sim.pins) do
    if not finite(p.x) or not finite(p.z) or not finite(p.angle) or not finite(p.tilt)
      or not finite(p.vx) or not finite(p.vz) or not finite(p.tiltV) then return false end
  end
  return true
end

local function collidesBallPin(sim,p)
  local ax,ay,az,bx,by,bz=pinAxis3(p)
  local _,_,_,dist2=pointSegment3(sim.ball.x,sim.ball.y,sim.ball.z,ax,ay,az,bx,by,bz)
  return dist2<=(lane.ballRadius+lane.pinRadius)^2,dist2
end

local function pinPointVelocity(p,t)
  local h=lane.pinHeight
  local dirx,dirz=math.cos(p.angle),math.sin(p.angle)
  return p.vx+t*h*math.cos(p.tilt)*p.tiltV*dirx,
    -t*h*math.sin(p.tilt)*p.tiltV,
    p.vz+t*h*math.cos(p.tilt)*p.tiltV*dirz
end

local function ballPinContact(sim,p)
  local overlap=collidesBallPin(sim,p)
  if not overlap then sim.contacts[p.id]=nil; return false end
  if sim.contacts[p.id] then return false end
  sim.contacts[p.id]=true
  local ax,ay,az,bx,by,bz=pinAxis3(p)
  local qx,qy,qz,dist2,t=pointSegment3(sim.ball.x,sim.ball.y,sim.ball.z,ax,ay,az,bx,by,bz)
  local nx,ny,nz=sim.ball.x-qx,sim.ball.y-qy,sim.ball.z-qz
  local length=math.sqrt(dist2)
  if length<1e-8 then
    local speed=math.sqrt(sim.vx*sim.vx+sim.vz*sim.vz)
    if speed<1e-8 then nx,ny,nz,length=-1,0,0,1 else nx,ny,nz,length=-sim.vx/speed,0,-sim.vz/speed,1 end
  else nx,ny,nz=nx/length,ny/length,nz/length end
  local pvx,pvy,pvz=pinPointVelocity(p,t)
  local closing=-((sim.vx-pvx)*nx+(0-pvy)*ny+(sim.vz-pvz)*nz)
  if closing<=0 then return true end
  p.angle=atan2(-nz,-nx)
  local dirx,dirz=math.cos(p.angle),math.sin(p.angle)
  local lever=t*lane.pinHeight*(math.cos(p.tilt)*(nx*dirx+nz*dirz)-math.sin(p.tilt)*ny)
  local inertia=0.073
  local impulse=1.08*closing/(1/6.8+1/1.6+(lever*lever)/inertia)
  sim.vx=sim.vx+impulse/6.8*nx
  sim.vz=sim.vz+impulse/6.8*nz
  p.vx=clamp(p.vx-impulse/1.6*nx,-1.2,1.2)
  p.vz=clamp(p.vz-impulse/1.6*nz,-1.2,1.2)
  if not p.down then p.tiltV=clamp(p.tiltV-impulse*lever/inertia,0,6.5) end
  p.settled=false
  sim.hookActive=false
  sim.hitAny=true
  return true
end

local function resolvePinContacts(sim)
  local radius=lane.pinRadius*2
  local inertia=0.073
  for i=1,#sim.pins do
    local a=sim.pins[i]
    local a0x,a0y,a0z,a1x,a1y,a1z=pinAxis3(a)
    for j=i+1,#sim.pins do
      local b=sim.pins[j]
      local key=a.id..":"..b.id
      local b0x,b0y,b0z,b1x,b1y,b1z=pinAxis3(b)
      local ax,ay,az,bx,by,bz,ta,tb,d2=closestSegments3(
        a0x,a0y,a0z,a1x,a1y,a1z,b0x,b0y,b0z,b1x,b1y,b1z)
      if d2>=(radius+0.008)^2 then sim.pinContacts[key]=nil end
      if d2<=radius*radius then
        local d=math.sqrt(d2)
        local nx,ny,nz
        if d>1e-8 then nx,ny,nz=(bx-ax)/d,(by-ay)/d,(bz-az)/d
        else nx,ny,nz=1,0,0 end
        local avx,avy,avz=pinPointVelocity(a,ta)
        local bvx,bvy,bvz=pinPointVelocity(b,tb)
        local closing=-((bvx-avx)*nx+(bvy-avy)*ny+(bvz-avz)*nz)
        if closing>0.01 and not sim.pinContacts[key] then
          local impulse=1.05*closing/(2/1.6)
          a.vx=a.vx-impulse/1.6*nx
          a.vz=a.vz-impulse/1.6*nz
          b.vx=b.vx+impulse/1.6*nx
          b.vz=b.vz+impulse/1.6*nz
          if not a.down then
            a.angle=atan2(-nz,-nx)
            local signed=ta*lane.pinHeight*(math.cos(a.tilt)*(nx*math.cos(a.angle)+nz*math.sin(a.angle))-math.sin(a.tilt)*ny)
            a.tiltV=clamp(a.tiltV-impulse*signed/inertia,0,6.5)
          end
          if not b.down then
            b.angle=atan2(nz,nx)
            local signed=tb*lane.pinHeight*(math.cos(b.tilt)*(nx*math.cos(b.angle)+nz*math.sin(b.angle))-math.sin(b.tilt)*ny)
            b.tiltV=clamp(b.tiltV+impulse*signed/inertia,0,6.5)
          end
          a.settled=false; b.settled=false
          sim.pinContacts[key]=true
        end
      end
    end
  end
end

local function integratePins(sim,dt)
  for _,p in ipairs(sim.pins) do
    if not p.settled then
      p.x=p.x+p.vx*dt; p.z=p.z+p.vz*dt
      p.vx=p.vx*math.max(0,1-2.8*dt); p.vz=p.vz*math.max(0,1-2.8*dt)
      if p.tilt<math.pi/2 then
        p.tiltV=p.tiltV+7.0*math.sin(p.tilt)*dt
        p.tilt=math.min(math.pi/2,p.tilt+p.tiltV*dt)
      end
      p.tiltV=p.tiltV*math.max(0,1-1.4*dt)
      if p.tilt>=1.08 then p.down=true end
      if math.abs(p.tiltV)<0.05 and math.abs(p.vx)+math.abs(p.vz)<0.04 then p.settled=true end
      if p.x>lane.endX or p.x<lane.foulLine-0.5 or math.abs(p.z)>lane.width/2+lane.gutterWidth then
        p.down=true; p.settled=true; p.vx,p.vz,p.tiltV=0,0,0
      end
    end
  end
end

local function substep(sim,dt)
  integratePins(sim,dt)
  local b=sim.ball
  if not sim.ballStopped then
    if not b.gutter and sim.hookActive then
      local fraction=clamp(b.x/lane.headX,0,1)
      sim.vz=sim.vz+physics.hookAcceleration*sim.shot.hook*fraction*fraction*dt
    end
    local speed=math.sqrt(sim.vx*sim.vx+sim.vz*sim.vz)
    if speed>0 then
      local reduction=math.min(speed,physics.rollingDrag*dt)
      sim.vx=sim.vx*(speed-reduction)/speed
      sim.vz=sim.vz*(speed-reduction)/speed
    end
    b.x=b.x+sim.vx*dt
    if not b.gutter then b.z=b.z+sim.vz*dt end
    b.y=lane.ballRadius
    if not b.gutter and math.abs(b.z)+lane.ballRadius>=lane.width/2 then
      b.gutter=b.z<0 and "left" or "right"
      b.z=(b.gutter=="left" and -1 or 1)*(lane.width/2+lane.gutterWidth*0.55)
      sim.vz=0
      sim.hookActive=false
    end
    if not b.gutter then
      for _,p in ipairs(sim.pins) do ballPinContact(sim,p) end
    end
    if b.x>=lane.endX then b.x=lane.endX end
    if b.x>=lane.endX or math.sqrt(sim.vx*sim.vx+sim.vz*sim.vz)<0.35 then
      sim.ballStopped=true
      sim.vx,sim.vz=0,0
    end
  end
  resolvePinContacts(sim)
  sim.time=sim.time+dt
  if not validState(sim) then return resultFor(sim,"error","non-finite simulation state") end
  if sim.time>=physics.maxDuration then return resultFor(sim,"error","simulation timed out") end
  return false
end

local function settleComplete(sim)
  if not sim.ballStopped then return false end
  for _,p in ipairs(sim.pins) do if not p.settled then return false end end
  return true
end

function physics.begin(rack,shot)
  local pins,err=validateRack(rack)
  if not pins then return nil,err end
  if type(shot)~="table" then return nil,"shot is required" end
  if not finite(shot.deliveryId) or shot.deliveryId<1 or shot.deliveryId%1~=0 then return nil,"deliveryId must be a positive integer" end
  if not finite(shot.position) or shot.position<-.38 or shot.position>.38 then return nil,"position must be between -0.38 and 0.38" end
  if not finite(shot.aim) then return nil,"aim must be finite" end
  if not finite(shot.power) or shot.power<.25 or shot.power>1 then return nil,"power must be between 0.25 and 1" end
  if not finite(shot.hook) or shot.hook < -1 or shot.hook>1 then return nil,"hook must be between -1 and 1" end
  local byId,pinContacts={},{}
  for _,p in ipairs(pins) do
    p.vx,p.vz,p.tiltV=0,0,0
    p.settled=true
    if p.down then p.tilt=math.pi/2 end
    byId[p.id]=p
  end
  local speed=3.8+7.7*shot.power
  local sim={shot=shot,pins=pins,pinById=byId,pinContacts=pinContacts,contacts={},
    ball={x=0,y=lane.ballRadius,z=shot.position,gutter=false},
    vx=speed*math.cos(shot.aim),vz=speed*math.sin(shot.aim),
    time=0,steps=0,done=false,hookActive=true,hitAny=false,ballStopped=false,trajectory={}}
  appendSnapshot(sim,true)
  return sim
end

local function advanceStep(sim)
  local speed=math.sqrt(sim.vx*sim.vx+sim.vz*sim.vz)
  local subdivisions=math.max(1,math.min(8,math.ceil(speed*physics.step/.035)))
  local dt=physics.step/subdivisions
  for _=1,subdivisions do
    if substep(sim,dt) then return true end
  end
  sim.steps=sim.steps+1
  if sim.steps%4==0 then appendSnapshot(sim,false) end
  if settleComplete(sim) then return resultFor(sim,"ok") end
  return false
end

function physics.advance(sim,stepBudget)
  if type(sim)~="table" or sim.done then return true end
  if not finite(stepBudget) or stepBudget<0 then return resultFor(sim,"error","invalid step budget") end
  local n=math.min(math.floor(stepBudget),physics.maxBatch)
  for _=1,n do if advanceStep(sim) then return true end end
  return sim.done
end

function physics.simulate(rack,shot)
  local sim,err=physics.begin(rack,shot)
  if not sim then
    return {deliveryId=type(shot)=="table" and shot.deliveryId or nil,status="error",knocked={},standing={},duration=0,error=err},{}
  end
  while not sim.done do physics.advance(sim,physics.maxBatch) end
  return sim.result,sim.trajectory
end

physics.lane=lane
return physics
