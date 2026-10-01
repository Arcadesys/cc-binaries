-- Triangle helpers shared by the Pine3D casino scenes.
local M={}
-- Pine3D culls a triangle unless its screen winding matches; facing (outward normal)
-- orients each triangle so only its front side draws. nil facing draws both sides.
M.wind=1
local function sub(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
local function cross(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
function M.tri(m,a,b,c,color,facing)
 if facing and dot(cross(sub(b,a),sub(c,a)),facing)*M.wind<0 then b,c=c,b end
 m[#m+1]={x1=a[1],y1=a[2],z1=a[3],x2=b[1],y2=b[2],z2=b[3],x3=c[1],y3=c[2],z3=c[3],c=color,forceRender=not facing}
end
function M.quad(m,a,b,c,d,color,facing) M.tri(m,a,b,c,color,facing); M.tri(m,a,c,d,color,facing) end
-- Axis-aligned box from (x,y,z) to (x+sx,y+sy,z+sz), faces pointing outward.
function M.box(m,x,y,z,sx,sy,sz,c)
 local x2,y2,z2=x+sx,y+sy,z+sz
 local q=M.quad
 q(m,{x,y,z},{x,y2,z},{x,y2,z2},{x,y,z2},c,{-1,0,0})
 q(m,{x2,y,z},{x2,y2,z},{x2,y2,z2},{x2,y,z2},c,{1,0,0})
 q(m,{x,y,z},{x2,y,z},{x2,y,z2},{x,y,z2},c,{0,-1,0})
 q(m,{x,y2,z},{x2,y2,z},{x2,y2,z2},{x,y2,z2},c,{0,1,0})
 q(m,{x,y,z},{x2,y,z},{x2,y2,z},{x,y2,z},c,{0,0,-1})
 q(m,{x,y,z2},{x2,y,z2},{x2,y2,z2},{x,y2,z2},c,{0,0,1})
end
-- Point camera at (x,y,z) toward (tx,ty,tz).
function M.look(frame,x,y,z,tx,ty,tz)
 local dx,dz=tx-x,tz-z
 frame:setCamera({x=x,y=y,z=z,rotX=-90,rotY=math.deg(math.atan2(dz,dx)),rotZ=math.deg(math.atan2(ty-y,math.sqrt(dx*dx+dz*dz)))})
end
return M
