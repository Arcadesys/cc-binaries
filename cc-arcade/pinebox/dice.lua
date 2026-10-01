-- Dice that are thrown, not faked. Two cubes are simulated as rigid bodies (gravity,
-- corner contacts with the tray floor and walls, restitution, friction, die-to-die
-- bumps) until they come to rest, and the trajectory is recorded for playback.
-- The values are drawn first, uniformly. Whichever face physics leaves on top is
-- relabelled by a rotation of the cube so it shows the drawn value: the tumble is real
-- and the odds stay exact.
local M={}
M.half=.62
M.tray={xmin=-6.2,xmax=4.6,zmin=-3.7,zmax=3.7}
M.step=1/240
M.frameTime=1/30
M.maxTime=6
local G=26
local function v(x,y,z) return {x,y,z} end
local function add(a,b,s) s=s or 1; return {a[1]+b[1]*s,a[2]+b[2]*s,a[3]+b[3]*s} end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function cross(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
local function len(a) return math.sqrt(dot(a,a)) end
local function add4(a,b,s) return {a[1]+b[1]*s,a[2]+b[2]*s,a[3]+b[3]*s,a[4]+b[4]*s} end
local function scale(a,s) return {a[1]*s,a[2]*s,a[3]*s} end
-- Quaternions {w,x,y,z}.
local function qmul(a,b)
 return {a[1]*b[1]-a[2]*b[2]-a[3]*b[3]-a[4]*b[4],a[1]*b[2]+a[2]*b[1]+a[3]*b[4]-a[4]*b[3],
  a[1]*b[3]-a[2]*b[4]+a[3]*b[1]+a[4]*b[2],a[1]*b[4]+a[2]*b[3]-a[3]*b[2]+a[4]*b[1]}
end
local function qnorm(q) local n=math.sqrt(q[1]^2+q[2]^2+q[3]^2+q[4]^2); return {q[1]/n,q[2]/n,q[3]/n,q[4]/n} end
local function qaxis(axis,angle) local s=math.sin(angle/2); local n=len(axis); if n<1e-9 then return {1,0,0,0} end
 return {math.cos(angle/2),axis[1]/n*s,axis[2]/n*s,axis[3]/n*s} end
function M.matrix(q)
 local w,x,y,z=q[1],q[2],q[3],q[4]
 return {{1-2*(y*y+z*z),2*(x*y-w*z),2*(x*z+w*y)},{2*(x*y+w*z),1-2*(x*x+z*z),2*(y*z-w*x)},{2*(x*z-w*y),2*(y*z+w*x),1-2*(x*x+y*y)}}
end
local function apply(m,p) return {m[1][1]*p[1]+m[1][2]*p[2]+m[1][3]*p[3],m[2][1]*p[1]+m[2][2]*p[2]+m[2][3]*p[3],m[3][1]*p[1]+m[3][2]*p[2]+m[3][3]*p[3]} end
M.apply=apply
local function slerp(a,b,u)
 local d=a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4]
 if d<0 then b={-b[1],-b[2],-b[3],-b[4]}; d=-d end
 if d>.9995 then return qnorm({a[1]+(b[1]-a[1])*u,a[2]+(b[2]-a[2])*u,a[3]+(b[3]-a[3])*u,a[4]+(b[4]-a[4])*u}) end
 local th=math.acos(d); local s=math.sin(th)
 local p,r=math.sin((1-u)*th)/s,math.sin(u*th)/s
 return {a[1]*p+b[1]*r,a[2]*p+b[2]*r,a[3]*p+b[3]*r,a[4]*p+b[4]*r}
end
M.slerp=slerp
-- Face normals in die space: opposite faces add to seven.
M.faces={[1]=v(0,1,0),[6]=v(0,-1,0),[2]=v(1,0,0),[5]=v(-1,0,0),[3]=v(0,0,1),[4]=v(0,0,-1)}
-- The 24 rotations of a cube, as signed permutation matrices with determinant +1.
local rotations={}
do
 local perms={{1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1}}
 for _,p in ipairs(perms) do for sx=-1,1,2 do for sy=-1,1,2 do for sz=-1,1,2 do
  local m={{0,0,0},{0,0,0},{0,0,0}}; local s={sx,sy,sz}
  for r=1,3 do m[r][p[r]]=s[r] end
  local det=m[1][1]*(m[2][2]*m[3][3]-m[2][3]*m[3][2])-m[1][2]*(m[2][1]*m[3][3]-m[2][3]*m[3][1])+m[1][3]*(m[2][1]*m[3][2]-m[2][2]*m[3][1])
  if det>0 then rotations[#rotations+1]=m end
 end end end end
end
M.rotations=rotations
-- The face (value) whose normal ends up pointing most nearly up.
function M.upFace(q)
 local m=M.matrix(q); local top,value=-2,nil
 for n,normal in pairs(M.faces) do local up=apply(m,normal)[2]; if up>top then top,value=up,n end end
 return value,top
end
-- A cube rotation taking the face showing `want` to where face `landed` sits.
function M.relabel(landed,want)
 local target=M.faces[landed]
 for _,r in ipairs(rotations) do
  local p=apply(r,M.faces[want])
  if p[1]==target[1] and p[2]==target[2] and p[3]==target[3] then return r end
 end
end
local function newDie(rng,z)
 local h=M.half
 return {pos=v(-5.4,2.0+rng()*.6,z),vel=v(5.5+rng()*3.5,1.5+rng()*2,(rng()-.5)*2.5),
  q=qnorm({rng()-.5,rng()-.5,rng()-.5,rng()-.5}),w=v(0,0,0),
  spin=12+rng()*14,still=0,h=h}
end
-- Simulate a throw. rng() returns [0,1); values are the two drawn results.
function M.throw(rng,values)
 local h=M.half
 local dice={newDie(rng,-1.1),newDie(rng,1.1)}
 for _,d in ipairs(dice) do
  local a=qnorm({0,rng()-.5,rng()-.5,rng()-.5}); d.w=scale({a[2],a[3],a[4]},d.spin)
 end
 local mass,iinv=1,6/(4*h*h)
 local corners={}
 for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do corners[#corners+1]=v(x*h,y*h,z*h) end end end
 local T=M.tray
 local planes={{n=v(0,1,0),d=0,e=.38},{n=v(1,0,0),d=T.xmin,e=.5},{n=v(-1,0,0),d=-T.xmax,e=.55},{n=v(0,0,1),d=T.zmin,e=.5},{n=v(0,0,-1),d=-T.zmax,e=.5}}
 local frames={}; local t,nextFrame=0,0
 local function record() frames[#frames+1]={{pos=dice[1].pos,q=dice[1].q},{pos=dice[2].pos,q=dice[2].q},bumps=dice.bumps} ; dice.bumps=nil end
 local resting=false
 while t<M.maxTime and not resting do
  if t>=nextFrame then record(); nextFrame=nextFrame+M.frameTime end
  for _,d in ipairs(dice) do
   d.vel=add(d.vel,v(0,-G*M.step,0))
   d.pos=add(d.pos,d.vel,M.step)
   d.q=qnorm(add4(d.q,qmul({0,d.w[1],d.w[2],d.w[3]},d.q),.5*M.step))
   local m=M.matrix(d.q); local touching=false
   for _=1,2 do
    for _,c in ipairs(corners) do
     local r=apply(m,c); local p=add(d.pos,r)
     for _,pl in ipairs(planes) do
      local depth=pl.d-dot(pl.n,p)
      if depth>0 then
       touching=touching or pl.n[2]>0
       local vel=add(d.vel,cross(d.w,r)); local vn=dot(vel,pl.n)
       if vn<0 then
        local rn=cross(r,pl.n)
        local k=1/mass+iinv*dot(cross(rn,r),pl.n)
        local j=-(1+(vn<-1.2 and pl.e or 0))*vn/k
        d.vel=add(d.vel,pl.n,j/mass); d.w=add(d.w,rn,iinv*j)
        if math.abs(vn)>2.5 then dice.bumps=(dice.bumps or 0)+math.abs(vn) end
        -- Coulomb friction against the sliding direction.
        vel=add(d.vel,cross(d.w,r)); local vt=add(vel,pl.n,-dot(vel,pl.n)); local speed=len(vt)
        if speed>1e-6 then
         local tdir=scale(vt,-1/speed); local rt=cross(r,tdir)
         local kt=1/mass+iinv*dot(cross(rt,r),tdir)
         local jt=math.min(speed/kt,.45*j)
         d.vel=add(d.vel,tdir,jt/mass); d.w=add(d.w,rt,iinv*jt)
        end
       end
       d.pos=add(d.pos,pl.n,depth*.6)
      end
     end
    end
   end
   if touching then d.w=scale(d.w,.996); d.vel={d.vel[1]*.998,d.vel[2],d.vel[3]*.998} end
   if touching and len(d.vel)<.2 and len(d.w)<.5 then d.still=d.still+M.step else d.still=0 end
  end
  -- Dice knock into each other as spheres a little smaller than their corners.
  local a,b=dice[1],dice[2]; local delta=add(b.pos,a.pos,-1); local dist=len(delta); local minD=h*1.75
  if dist<minD and dist>1e-6 then
   local n=scale(delta,1/dist); local rel=dot(add(b.vel,a.vel,-1),n)
   if rel<0 then local j=-(1.5)*rel/2; a.vel=add(a.vel,n,-j); b.vel=add(b.vel,n,j); dice.bumps=(dice.bumps or 0)+math.abs(rel) end
   a.pos=add(a.pos,n,-(minD-dist)/2); b.pos=add(b.pos,n,(minD-dist)/2)
  end
  t=t+M.step
  resting=dice[1].still>.15 and dice[2].still>.15
 end
 record()
 -- Settle exactly flat over a few frames, then pick the relabelling for each die.
 local result={frames=frames,relabel={},landed={}}
 local finals={}
 for i,d in ipairs(dice) do
  local landed=M.upFace(d.q)
  local up=apply(M.matrix(d.q),M.faces[landed])
  local axis=cross(up,v(0,1,0)); local angle=math.acos(math.max(-1,math.min(1,up[2])))
  finals[i]={pos=v(d.pos[1],h,d.pos[3]),q=qnorm(qmul(qaxis(axis,angle),d.q))}
  result.landed[i]=landed; result.relabel[i]=M.relabel(landed,values[i])
 end
 for k=1,6 do
  local u=k/6
  frames[#frames+1]={}
  for i,d in ipairs(dice) do frames[#frames][i]={pos=add(d.pos,add(finals[i].pos,d.pos,-1),u),q=slerp(d.q,finals[i].q,u)} end
 end
 result.duration=(#frames-1)*M.frameTime
 return result
end
-- Pose of die i at time t: position and rotation matrix (relabel applied first).
function M.pose(throw,i,t)
 local f=throw.frames; local x=math.max(0,t/M.frameTime); local k=math.floor(x)+1
 if k>=#f then local last=f[#f][i]; return last.pos,M.compose(M.matrix(last.q),throw.relabel[i]) end
 local u=x-(k-1); local a,b=f[k][i],f[k+1][i]
 local pos=add(a.pos,add(b.pos,a.pos,-1),u)
 return pos,M.compose(M.matrix(slerp(a.q,b.q,u)),throw.relabel[i])
end
function M.compose(a,b)
 local m={{0,0,0},{0,0,0},{0,0,0}}
 for r=1,3 do for c=1,3 do for k=1,3 do m[r][c]=m[r][c]+a[r][k]*b[k][c] end end end
 return m
end
-- Bumps (impact strength) recorded between two times, for clack sounds.
function M.bumps(throw,t0,t1)
 local n=0
 for k=math.floor(t0/M.frameTime)+2,math.floor(t1/M.frameTime)+1 do local f=throw.frames[k]; if f and f.bumps then n=n+f.bumps end end
 return n
end
return M
