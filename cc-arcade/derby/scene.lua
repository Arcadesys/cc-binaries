local M={}
local pi=math.pi
-- A stadium oval: two 40-unit straights and two radius-16 bends.
M.length=80+32*pi
function M.pose(progress,lane)
 local d=(progress%1)*M.length; local r=16+(lane or 0)
 if d<40 then return -20+d,r,0
 elseif d<40+16*pi then local a=(d-40)/16; return 20+math.sin(a)*r,math.cos(a)*r,a
 elseif d<80+16*pi then return 20-(d-40-16*pi),-r,pi
 else local a=(d-80-16*pi)/16; return -20-math.sin(a)*r,-math.cos(a)*r,pi+a end
end
local function tri(m,a,b,c,color)
 m[#m+1]={x1=a[1],y1=a[2],z1=a[3],x2=b[1],y2=b[2],z2=b[3],x3=c[1],y3=c[2],z3=c[3],c=color,forceRender=true}
end
local function quad(m,a,b,c,d,color) tri(m,a,b,c,color); tri(m,a,c,d,color) end
function M.box(m,x,y,z,sx,sy,sz,c)
 local a={x,y,z}; local b={x+sx,y,z}; local d={x,y,z+sz}; local e={x,y+sy,z}; local f={x+sx,y+sy,z}; local g={x+sx,y+sy,z+sz}; local h={x,y+sy,z+sz}; local j={x+sx,y,z+sz}
 quad(m,a,b,f,e,c); quad(m,d,h,g,j,c); quad(m,a,e,h,d,c); quad(m,b,j,g,f,c); quad(m,e,f,g,h,c); quad(m,a,d,j,b,c)
end
function M.track(detail)
 local m={}; local steps=detail and 100 or 56
 quad(m,{-80,-.12,-65},{80,-.12,-65},{80,-.12,65},{-80,-.12,65},colors.green)
 for n=0,steps-1 do
  local a,b=n/steps,(n+1)/steps
  local x1,z1=M.pose(a,-3); local x2,z2=M.pose(a,5)
  local x3,z3=M.pose(b,5); local x4,z4=M.pose(b,-3)
  quad(m,{x1,0,z1},{x2,0,z2},{x3,0,z3},{x4,0,z4},colors.brown)
  for _,offset in ipairs({-3,5}) do
   local x,z=M.pose(a,offset); local xx,zz=M.pose(b,offset)
   quad(m,{x,.85,z},{xx,.85,zz},{xx,1.05,zz},{x,1.05,z},colors.white)
   if n%2==0 then M.box(m,x,.05,z,.14,.95,.14,colors.lightGray) end
  end
 end
 -- Starting gates and finish gantry, at the beginning of the near straight.
 for i=0,3 do M.box(m,-20,.05,13.4+i*2.1,.25,2,.25,colors.lightGray) end
 M.box(m,-20,2,13.4,.4,.3,6.7,colors.yellow)
 for _,z in ipairs({12.3,22}) do M.box(m,-19.7,0,z,.5,5,.5,colors.white) end
 M.box(m,-19.7,4.7,12.3,.5,.7,10.2,colors.black)
 for n=0,7 do
  quad(m,{-20,.02,13+n},{-19,.02,13+n},{-19,.02,14+n},{-20,.02,14+n},n%2==0 and colors.white or colors.black)
 end
 -- Tiered grandstand behind the far straight, so every camera looks across the track at it
 -- rather than through it. A shallow cantilevered roof covers only the back rows.
 for n=0,3 do M.box(m,-16,0,-32-n*2,32,1.2+n*1.2,2, n%2==0 and colors.lightGray or colors.gray) end
 M.box(m,-16,0,-40.5,32,6.2,.5,colors.gray)
 M.box(m,-17,6.2,-41,34,.25,5,colors.red)
 for _,x in ipairs({-16,15.6}) do M.box(m,x,0,-40.5,.4,6.2,.4,colors.white) end
 -- Tote board in the infield: three large light panels instead of tiny scenery text.
 M.box(m,5,0,-5,.5,6,.5,colors.gray); M.box(m,18,0,-5,.5,6,.5,colors.gray)
 M.box(m,4,4,-5.2,15,5,.5,colors.black)
 for i=1,3 do M.box(m,5,4+i,-4.65,12,.5,.1,colors.white) end
 return m
end
-- A box along a line in the side (x-y) plane: used for legs, neck, head and tail so the
-- horse reads as a silhouette instead of a stack of axis-aligned blocks.
function M.limb(m,x1,y1,x2,y2,thick,z,width,c)
 local dx,dy=x2-x1,y2-y1; local len=math.sqrt(dx*dx+dy*dy); if len==0 then return end
 local nx,ny=-dy/len*thick/2,dx/len*thick/2; local z1,z2=z-width/2,z+width/2
 local p={{x1+nx,y1+ny},{x2+nx,y2+ny},{x2-nx,y2-ny},{x1-nx,y1-ny}}
 local function v(k,zz) return {p[k][1],p[k][2],zz} end
 quad(m,v(1,z1),v(2,z1),v(3,z1),v(4,z1),c); quad(m,v(1,z2),v(2,z2),v(3,z2),v(4,z2),c)
 for k=1,4 do local n=k%4+1; quad(m,v(k,z1),v(n,z1),v(n,z2),v(k,z2),c) end
end
-- Coat, mane and jockey silks. Silks match sim.horses[i].color so the UI and track agree.
M.coats={{colors.pink,colors.black},{colors.black,colors.gray},{colors.lightGray,colors.gray}}
M.silks={colors.orange,colors.lightGray,colors.purple}
function M.horse(i,phase)
 local m={}; local coat,mane=M.coats[i][1],M.coats[i][2]; local silk=M.silks[i]
 -- Barrel, chest and rump, then a sloping neck and a head angled toward the ground.
 M.box(m,-.95,1.22,-.36,1.95,.78,.72,coat)
 M.limb(m,.7,1.5,1.3,2.5,.62,0,.52,coat)
 M.limb(m,1.2,2.58,1.95,2.06,.36,0,.4,coat)
 M.box(m,1.08,2.72,-.16,.12,.24,.1,coat); M.box(m,1.08,2.72,.06,.12,.24,.1,coat)
 M.limb(m,.5,1.9,1.08,2.76,.14,0,.2,mane)
 local sway=math.sin(phase)*.12
 M.limb(m,-.92,1.92,-1.5,1.2+sway,.22,0,.2,mane)
 -- Rotary gallop: each leg is a thigh plus a cannon that folds back as the leg swings forward.
 for _,leg in ipairs({{-.68,-.2,0},{-.68,.2,.7},{.68,-.2,pi},{.68,.2,pi+.7}}) do
  local hx,hz,off=leg[1],leg[2],leg[3]
  local swing=math.sin(phase+off)*.5; local fold=math.max(0,math.cos(phase+off))*.9
  local kx,ky=hx+math.sin(swing)*.62,1.4-math.cos(swing)*.62
  local lower=swing-fold
  local fx,fy=kx+math.sin(lower)*.56,ky-math.cos(lower)*.56
  local tx,ty=kx+math.sin(lower)*.72,ky-math.cos(lower)*.72
  M.limb(m,hx,1.45,kx,ky,.24,hz,.2,coat)
  M.limb(m,kx,ky,fx,fy,.16,hz,.17,coat)
  M.limb(m,fx,fy,tx,ty,.2,hz,.2,colors.black)
 end
 -- Saddlecloth and a crouched jockey in the horse's racing colours.
 M.box(m,-.5,1.5,-.39,.85,.55,.78,silk)
 M.limb(m,-.25,2.12,.3,1.98,.2,0,.66,colors.white)
 M.limb(m,-.2,2.15,.42,2.55,.4,0,.42,silk)
 M.limb(m,.32,2.45,.8,2.2,.12,0,.56,silk)
 M.box(m,.36,2.56,-.16,.32,.28,.32,silk)
 return m
end
return M
