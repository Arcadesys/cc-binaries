-- Pine3D meshes for the cabinet. The pull arm and buttons are physical, in the world.
-- The camera sits on -x looking toward +x; y is up and
-- M.side is the z direction that appears on the right of the screen.
local reels=require('pineslots.reels')
local M={}
local pi=math.pi
M.side=1
M.radius=3
M.faces=reels.size
M.step=2*pi/M.faces
M.reelZ={-2.5,0,2.5}
M.halfWidth=1.05
M.window={y=1.72,z=3.85,x=-3.3}
local mesh=require('casino.mesh')
local tri,quad=mesh.tri,mesh.quad
M.tri=tri
M.box=mesh.box
-- Symbol artwork in face units: u right, v up, both within -0.5..0.5. Each shape is a
-- star-shaped outline fanned from its first point, so concave bells still fill correctly.
local function ring(cx,cy,rx,ry,n)
 local p={{cx,cy}}
 for i=0,n do local a=i/n*2*pi; p[#p+1]={cx+math.cos(a)*rx,cy+math.sin(a)*ry} end
 return p
end
local function fan(...) local p={...}; local cx,cy=0,0; for _,q in ipairs(p) do cx=cx+q[1]; cy=cy+q[2] end
 table.insert(p,1,{cx/#p,cy/#p}); p[#p+1]=p[2]; return p end
M.art={
 D={{colors.lightBlue,fan({-.3,.4},{.3,.4},{.48,.14},{-.48,.14})},{colors.cyan,fan({-.48,.14},{.48,.14},{0,-.48})},{colors.white,fan({-.12,.4},{.12,.4},{0,.2})}},
 S={{colors.red,fan({-.38,.48},{.42,.48},{.42,.3},{-.38,.3})},{colors.red,fan({.2,.3},{.42,.3},{-.02,-.48},{-.24,-.48})}},
 R={{colors.black,fan({-.48,.24},{.48,.24},{.48,-.24},{-.48,-.24})},{colors.yellow,fan({-.36,.05},{.36,.05},{.36,-.05},{-.36,-.05})}},
 B={{colors.yellow,fan({-.14,.42},{.14,.42},{.3,.2},{.33,-.18},{.47,-.32},{-.47,-.32},{-.33,-.18},{-.3,.2})},{colors.orange,fan({-.09,-.32},{.09,-.32},{.09,-.46},{-.09,-.46})}},
 C={{colors.lime,fan({-.2,-.1},{.1,.46},{.16,.42},{-.12,-.1})},{colors.lime,fan({.2,-.04},{.1,.46},{.16,.46},{.28,-.04})},{colors.red,ring(-.2,-.22,.22,.24,8)},{colors.red,ring(.22,-.14,.22,.24,8)}},
 P={{colors.purple,ring(0,-.06,.4,.4,10)},{colors.lime,fan({0,.3},{.32,.5},{.1,.26})}},
}
-- One drum. Face k is at angle k*step below the front, so stop k-1 sits above stop k.
-- Rotating the drum by rotZ = position*step brings that stop to the front.
function M.reel(i)
 local m={}; local R=M.radius; local hh=R*math.tan(M.step/2); local hw=M.halfWidth; local s=M.side
 for k=0,M.faces-1 do
  local a=k*M.step; local ca,sa=math.cos(a),math.sin(a)
  local n={-ca,-sa,0}; local up={-sa,ca,0}
  local function at(u,v,lift)
   return {-R*ca+v*up[1]+lift*n[1],-R*sa+v*up[2]+lift*n[2],u*s}
  end
  quad(m,at(-hw,hh,0),at(hw,hh,0),at(hw,-hh,0),at(-hw,-hh,0),colors.white,n)
  for layer,shape in ipairs(M.art[reels.symbol(i,k)]) do
   local p=shape[2]; local size=hh*1.62
   for j=2,#p-1 do
    tri(m,at(p[1][1]*size,p[1][2]*size,.04+layer*.03),at(p[j][1]*size,p[j][2]*size,.04+layer*.03),at(p[j+1][1]*size,p[j+1][2]*size,.04+layer*.03),shape[1],n)
   end
  end
 end
 return m
end
-- Static cabinet: front panel with the reel window, gold trim, topper, body and deck.
function M.cabinet()
 local m={}; local w=M.window; local s=M.side
 local function zbox(x,y,z1,sx,sy,z2,c) local a,b=math.min(z1*s,z2*s),math.max(z1*s,z2*s); M.box(m,x,y,a,sx,sy,b-a,c) end
 -- Body: back wall behind the drums plus side walls, so nothing sits in front of the reels.
 zbox(3.3,-6,-5.2,1,8.6,5.2,colors.black)
 zbox(-3.3,-6,-5.2,6.6,8.6,-4.9,colors.red)
 zbox(-3.3,-6,4.9,6.6,8.6,5.2,colors.red)
 zbox(-3.5,w.y,-5.2,.2,.9,5.2,colors.red)
 zbox(-3.5,-2.6,-5.2,.2,2.6-w.y,5.2,colors.red)
 zbox(-3.5,-w.y,-5.2,.2,2*w.y,-w.z,colors.red)
 zbox(-3.5,-w.y,w.z,.2,2*w.y,5.2,colors.red)
 for _,z in ipairs({-1.45,1.05}) do zbox(-3.45,-w.y,z,.15,2*w.y,z+.4,colors.gray) end
 -- Gold trim around the window.
 zbox(-3.62,w.y,-w.z-.15,.12,.15,w.z+.15,colors.yellow)
 zbox(-3.62,-w.y-.15,-w.z-.15,.12,.15,w.z+.15,colors.yellow)
 zbox(-3.62,-w.y,-w.z-.15,.12,2*w.y,-w.z,colors.yellow)
 zbox(-3.62,-w.y,w.z,.12,2*w.y,w.z+.15,colors.yellow)
 -- Topper with a diamond emblem.
 zbox(-3.4,2.6,-4.6,5,2.4,4.6,colors.blue)
 zbox(-3.55,2.75,-4.4,.15,.12,4.4,colors.yellow)
 zbox(-3.55,4.75,-4.4,.15,.12,4.4,colors.yellow)
 local e=-3.6
 tri(m,{e,4.45,-.6*s},{e,4.45,.6*s},{e,3.9,0},colors.lightBlue,{-1,0,0})
 tri(m,{e,4.45,-.6*s},{e,4.6,-.35*s},{e,4.45,0},colors.lightBlue,{-1,0,0})
 tri(m,{e,4.45,.6*s},{e,4.6,.35*s},{e,4.45,0},colors.lightBlue,{-1,0,0})
 quad(m,{e,4.6,-.35*s},{e,4.6,.35*s},{e,4.45,.6*s},{e,4.45,-.6*s},colors.lightBlue,{-1,0,0})
 tri(m,{e-.02,4.45,-.6*s},{e-.02,4.45,.6*s},{e-.02,3.9,0},colors.cyan,{-1,0,0})
 for _,z in ipairs({-3.2,-2.2,2.2,3.2}) do zbox(-3.6,3.6,z-.25,.1,.5,z+.25,colors.white) end
 -- Button deck below the window and the coin tray.
 zbox(-4.7,-3.3,-5.2,1.4,.7,5.2,colors.black)
 zbox(-4.8,-3.0,-5.3,.25,.12,5.3,colors.yellow)
 zbox(-4.5,-5.6,-2.5,1.2,.6,2.5,colors.gray)
 zbox(-4.55,-5.1,-2.3,.1,.1,2.3,colors.black)
 return m
end
-- A lamp, lit or dark.
function M.lamp(color)
 local m={}; M.box(m,-.15,-.15,-.15,.3,.3,.3,color); return m
end
-- Lamp positions: marquee chase above and below the window, payline lamps either side.
function M.lamps()
 local out={}
 for n=0,12 do local z=(-4.5+n*.75)*M.side; out[#out+1]={-3.7,2.17,z}; end
 for n=12,0,-1 do local z=(-4.5+n*.75)*M.side; out[#out+1]={-3.7,-2.17,z} end
 return out
end
-- {left, right} lamp positions for each payline.
function M.lineLamps()
 local L,Rz=-4.45*M.side,4.45*M.side; local row=2*M.radius*math.tan(M.step/2)
 return {{{-3.7,0,L},{-3.7,0,Rz}},{{-3.7,row,L},{-3.7,row,Rz}},{{-3.7,-row,L},{-3.7,-row,Rz}},
  {{-3.7,1.55,L},{-3.7,-1.55,Rz}},{{-3.7,-1.55,L},{-3.7,1.55,Rz}}}
end
return M
