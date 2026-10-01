-- Pine3D meshes for the grand prize stage: a felt dice tray with padded rails, the
-- nine-number board behind it, and the dice. Camera on -x looking +x; +z is screen right.
local mesh=require('casino.mesh')
local font=require('casino.font')
local dice=require('pinebox.dice')
local M={}
local tri,quad,box=mesh.tri,mesh.quad,mesh.box
-- Big tiles standing on a ledge (y) above the back rail, so every number reads from
-- across the room. The marquee sits on top (M.header).
M.tile={width=1.45,height=2.4,gap=.2,x=5.8,y=.5}
M.header=M.tile.y+M.tile.height+.55
function M.tileZ(n) return (n-5)*(M.tile.width+M.tile.gap) end
function M.stage()
 local m={}; local T=dice.tray
 box(m,-14,-.6,-16,34,.5,32,colors.blue)
 box(m,T.xmin,-.2,T.zmin,T.xmax-T.xmin,.2,T.zmax-T.zmin,colors.green)
 -- Rails: low at the front so the camera sees in, taller behind as a backboard.
 box(m,T.xmin-.5,-.2,T.zmin-.5,.5,.55,T.zmax-T.zmin+1,colors.red)
 box(m,T.xmax,-.2,T.zmin-.5,.5,1.1,T.zmax-T.zmin+1,colors.red)
 box(m,T.xmin,-.2,T.zmin-.5,T.xmax-T.xmin,.8,.5,colors.red)
 box(m,T.xmin,-.2,T.zmax,T.xmax-T.xmin,.8,.5,colors.red)
 box(m,T.xmin-.55,.33,T.zmin-.55,.6,.08,T.zmax-T.zmin+1.1,colors.yellow)
 -- Number board: a dark panel with a gold frame and a marquee header.
 local half=4.5*(M.tile.width+M.tile.gap)+.35; local H=M.header
 box(m,M.tile.x+.25,-.2,-half,.5,H,2*half,colors.black)
 box(m,M.tile.x+.15,H-.25,-half-.2,.6,.25,2*half+.4,colors.yellow)
 box(m,M.tile.x+.25,H,-half,.5,1.2,2*half,colors.purple)
 box(m,M.tile.x+.15,H+1.2,-half-.2,.6,.2,2*half+.4,colors.yellow)
 return m
end
-- A number tile standing on its bottom edge (origin), face toward the camera.
function M.tileModel(n,lit)
 local m={}; local w,h=M.tile.width/2,M.tile.height
 local face=lit and colors.yellow or colors.white
 box(m,-.08,0,-w,.16,h,2*w,face)
 local cell=.38; local text=tostring(n)
 local u0=-font.width(text)*cell/2
 font.draw(m,text,u0,h/2+2.5*cell,cell,colors.red,function(u,vv) return {-.1,vv,u} end,{-1,0,0})
 return m
end
-- A die centred on the origin, red with white pips, in its unrotated pose.
local pipLayout={
 [1]={{0,0}},[2]={{-1,-1},{1,1}},[3]={{-1,-1},{0,0},{1,1}},[4]={{-1,-1},{1,-1},{-1,1},{1,1}},
 [5]={{-1,-1},{1,-1},{0,0},{-1,1},{1,1}},[6]={{-1,-1},{1,-1},{-1,0},{1,0},{-1,1},{1,1}},
}
function M.dieTriangles()
 local h=dice.half; local out={}
 box(out,-h,-h,-h,2*h,2*h,2*h,colors.red)
 for value,n in pairs(dice.faces) do
  -- Two axes spanning the face.
  local a=n[1]~=0 and {0,1,0} or {1,0,0}
  local b={n[2]*a[3]-n[3]*a[2],n[3]*a[1]-n[1]*a[3],n[1]*a[2]-n[2]*a[1]}
  local s,p=h*.5,h*.17
  for _,pip in ipairs(pipLayout[value]) do
   local function at(du,dv)
    local u,vv=pip[1]*s+du,pip[2]*s+dv
    return {n[1]*(h+.01)+a[1]*u+b[1]*vv,n[2]*(h+.01)+a[2]*u+b[2]*vv,n[3]*(h+.01)+a[3]*u+b[3]*vv}
   end
   quad(out,at(-p,-p),at(p,-p),at(p,p),at(-p,p),colors.white,n)
  end
 end
 return out
end
-- The die triangles rotated by matrix m (die space to world). Red faces are lit from
-- above, so the top face reads bright and the sides dark and the cube keeps its edges.
function M.dieModel(base,m)
 local out={}
 for i,t in ipairs(base) do
  local a=dice.apply(m,{t.x1,t.y1,t.z1}); local b=dice.apply(m,{t.x2,t.y2,t.z2}); local c=dice.apply(m,{t.x3,t.y3,t.z3})
  local color=t.c
  if color==colors.red then
   local ux,uy,uz=b[1]-a[1],b[2]-a[2],b[3]-a[3]; local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
   local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
   local n=math.sqrt(nx*nx+ny*ny+nz*nz)
   if n>0 and math.abs(ny/n)<.6 then color=colors.magenta end
  end
  out[i]={x1=a[1],y1=a[2],z1=a[3],x2=b[1],y2=b[2],z2=b[3],x3=c[1],y3=c[2],z3=c[3],c=color,forceRender=t.forceRender}
 end
 return out
end
function M.lamp(color) local m={}; box(m,-.15,-.15,-.15,.3,.3,.3,color); return m end
function M.lamps()
 local out={}; local half=4.5*(M.tile.width+M.tile.gap)
 for n=0,16 do out[#out+1]={M.tile.x+.1,M.header+.6,-half+n*(2*half/16)} end
 return out
end
return M
