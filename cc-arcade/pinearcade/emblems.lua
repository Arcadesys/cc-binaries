-- Pine3D emblems for the Pine Arcade carousel, one per game, each standing on y=0 about
-- 2.4 tall and 2 wide, its front toward -x (the camera); y is up and +z is screen right.
local mesh=require('casino.mesh')
local font=require('casino.font')
local M={}
local tri,quad,box=mesh.tri,mesh.quad,mesh.box
-- A solid of revolution about the y axis through (cx, cz). profile runs from the bottom
-- of the axis to the top as {radius, y} pairs; colors[i] paints band i (or one colour).
local function lathe(m,profile,n,colors_,cx,cz)
 cx,cz=cx or 0,cz or 0
 for i=1,#profile-1 do
  local r1,y1,r2,y2=profile[i][1],profile[i][2],profile[i+1][1],profile[i+1][2]
  local c=type(colors_)=='table' and (colors_[i] or colors_[#colors_]) or colors_
  -- Outward normal of the profile segment, in (radius, y).
  local nr,ny=y2-y1,-(r2-r1)
  for k=0,n-1 do
   local a,b=k/n*2*math.pi,(k+1)/n*2*math.pi
   local ca,sa,cb,sb=math.cos(a),math.sin(a),math.cos(b),math.sin(b)
   local mid=(a+b)/2
   local facing={math.cos(mid)*nr,ny,math.sin(mid)*nr}
   local p1,p2={cx+ca*r1,y1,cz+sa*r1},{cx+cb*r1,y1,cz+sb*r1}
   local p3,p4={cx+cb*r2,y2,cz+sb*r2},{cx+ca*r2,y2,cz+sa*r2}
   if r1==0 then tri(m,p1,p3,p4,c,facing)
   elseif r2==0 then tri(m,p1,p2,p3,c,facing)
   else quad(m,p1,p2,p3,p4,c,facing) end
  end
 end
end
local function ball(m,r,cx,cy,cz,c,n)
 local p={}
 for k=0,6 do local a=math.pi*(k/6-1)*-1; p[#p+1]={math.sin(a)*r,cy-math.cos(a)*r} end
 p[1][1],p[#p][1]=0,0
 lathe(m,p,n or 10,c,cx,cz)
end
-- Pedestal under every emblem; the ring lights when the game is the boot choice.
function M.pedestal(lit)
 local m={}
 lathe(m,{{0,-.35},{1.35,-.35},{1.35,-.05},{1.2,0},{0,0}},12,{colors.gray,lit and colors.lime or colors.gray,colors.lightGray,colors.lightGray})
 return m
end
-- Text on the front plane x, centred on z=0 with its top at v0.
local function front(m,x,text,v0,cell,color)
 font.draw(m,text,-font.width(text)*cell/2,v0,cell,color,function(u,v) return {x,v,u} end,{-1,0,0})
end
local E={}
function E.pineslots()
 local m={}
 box(m,-.6,0,-1,1.2,2.2,2,colors.red)
 box(m,-.65,2.2,-1.05,1.3,.35,2.1,colors.yellow)
 box(m,-.62,.95,-.85,.1,.95,1.7,colors.black)
 local reel={colors.red,colors.yellow,colors.purple}
 for k=1,3 do
  local z=-.82+(k-1)*.56
  box(m,-.66,1.0,z,.05,.85,.5,colors.white)
  box(m,-.7,1.27,z+.13,.05,.28,.24,reel[k])
 end
 box(m,-.65,.35,-.7,.1,.25,1.4,colors.lightGray)
 -- Pull arm on the right.
 box(m,-.12,1.1,1,.24,.2,.2,colors.lightGray)
 box(m,-.08,1.1,1.2,.16,1.15,.16,colors.lightGray)
 ball(m,.2,0,2.35,1.28,colors.red,8)
 return m
end
local function card(m,x,z,tilt,rank,suit,color)
 -- A standing card, leaning back by tilt, face toward -x.
 local W,H=.7,2.0
 local function pt(u,v) return {x+v*tilt,v,z+u} end
 quad(m,pt(-W,0),pt(W,0),pt(W,H),pt(-W,H),colors.white,{-1,0,tilt})
 quad(m,{x+.03,0,z-W},{x+.03,0,z+W},{x+.03+H*tilt,H,z+W},{x+.03+H*tilt,H,z-W},colors.blue,{1,0,-tilt})
 font.draw(m,rank,z-W+.12,H-.12,.17,color,function(u,v) return {x+v*tilt-.02,v,u} end,{-1,0,tilt})
 local cz,cy,s=z+.12,.85,.32
 local function p(u,v) return {x+(cy+v)*tilt-.02,cy+v,cz+u} end
 if suit=='D' then quad(m,p(0,s),p(s*.75,0),p(0,-s),p(-s*.75,0),color,{-1,0,tilt})
 else
  tri(m,p(-s*.9,0),p(0,s),p(s*.9,0),color,{-1,0,tilt}); tri(m,p(-s*.9,0),p(s*.9,0),p(0,-s*.45),color,{-1,0,tilt})
  quad(m,p(-.07,-.3),p(.07,-.3),p(.2,-s-.1),p(-.2,-s-.1),color,{-1,0,tilt})
 end
end
function E.pinejack()
 local m={}
 card(m,.15,-.45,.12,'A','S',colors.black)
 card(m,-.25,.4,.12,'K','D',colors.red)
 for k=0,4 do lathe(m,{{0,k*.11},{.38,k*.11},{.38,k*.11+.1},{0,k*.11+.1}},8,k%2==0 and colors.red or colors.white,-.6,-1.15) end
 return m
end
-- A die with pips on the faces toward the camera, the top and the right.
local function die(m,x,y,z,s,faces)
 box(m,x,y,z,s,s,s,colors.white)
 local r=s*.11
 local spots={[1]={{0,0}},[2]={{-1,-1},{1,1}},[3]={{-1,-1},{0,0},{1,1}},[4]={{-1,-1},{1,-1},{-1,1},{1,1}},
  [5]={{-1,-1},{1,-1},{0,0},{-1,1},{1,1}},[6]={{-1,-1},{1,-1},{-1,0},{1,0},{-1,1},{1,1}}}
 local h=s/2; local d=s*.27
 local function pips(n,point,facing)
  for _,q in ipairs(spots[n]) do
   local u,v=q[1]*d,q[2]*d
   quad(m,point(u-r,v-r),point(u+r,v-r),point(u+r,v+r),point(u-r,v+r),n==1 and colors.red or colors.black,facing)
  end
 end
 pips(faces[1],function(u,v) return {x-.01,y+h+v,z+h+u} end,{-1,0,0})
 pips(faces[2],function(u,v) return {x+h+v,y+s+.01,z+h+u} end,{0,1,0})
 pips(faces[3],function(u,v) return {x+h+u,y+h+v,z+s+.01} end,{0,0,1})
end
function E.pinebox()
 local m={}
 die(m,-.5,0,-1.05,1.1,{5,1,3})
 die(m,-.3,1.1,-.35,1,{6,4,2})
 die(m,-.6,0,.25,1,{3,2,6})
 return m
end
-- A horseshoe standing open end up, with nail holes.
function E.race()
 local m={}
 local n=14; local R,r=1.05,.68
 local prev
 for k=0,n do
  local a=math.pi*(-.15+k/n*1.3)
  local p={math.cos(a),math.sin(a)}
  if prev then
   local function at(rad,q,x) return {x,1.2-q[2]*rad,q[1]*rad} end
   local c=(k==4 or k==7 or k==10) and colors.orange or colors.yellow
   quad(m,at(R,prev,-.12),at(R,p,-.12),at(r,p,-.12),at(r,prev,-.12),c,{-1,0,0})
   quad(m,at(R,prev,.12),at(R,p,.12),at(r,p,.12),at(r,prev,.12),colors.orange,{1,0,0})
   quad(m,at(R,prev,-.12),at(R,p,-.12),at(R,p,.12),at(R,prev,.12),colors.orange,{0,-(prev[2]+p[2]),(prev[1]+p[1])})
   quad(m,at(r,prev,-.12),at(r,p,-.12),at(r,p,.12),at(r,prev,.12),colors.orange,{0,prev[2]+p[2],-(prev[1]+p[1])})
  end
  prev=p
 end
 for _,a in ipairs({.25,.75,1.05,1.55,1.85,2.3}) do
  local q={math.cos(math.pi*(-.15+a/2.6*1.3)),math.sin(math.pi*(-.15+a/2.6*1.3))}
  local cz,cy=q[1]*.87,1.2-q[2]*.87
  quad(m,{-.13,cy-.06,cz-.06},{-.13,cy-.06,cz+.06},{-.13,cy+.06,cz+.06},{-.13,cy+.06,cz-.06},colors.brown,{-1,0,0})
 end
 return m
end
function E.pineball()
 local m={}
 -- Bat leaning across the back, then the ball in front with red stitching.
 local function bat(y,z) return {.35,y,z} end
 for k=0,5 do
  local y1,y2=.1+k*.4,.1+(k+1)*.4
  local w1,w2=.07+k*.03,.07+(k+1)*.03
  local z1,z2=1.1-y1*.55,1.1-y2*.55
  quad(m,bat(y1,z1-w1),bat(y1,z1+w1),bat(y2,z2+w2),bat(y2,z2-w2),colors.brown,nil)
 end
 ball(m,.8,-.2,.85,-.1,colors.white,10)
 for k=0,7 do
  local a=k/8*math.pi*2
  local y,z=.85+math.cos(a)*.62,-.1+math.sin(a)*.62
  local x=-.2-math.sqrt(math.max(0,.64-(y-.85)^2-(z+.1)^2))-.01
  quad(m,{x,y-.05,z-.08},{x,y-.05,z+.08},{x,y+.05,z+.08},{x,y+.05,z-.08},colors.red,{-1,0,0})
 end
 return m
end
function E.pinelinks()
 local m={}
 lathe(m,{{0,0},{1.15,0},{1.15,.15},{0,.15}},10,colors.lime)
 lathe(m,{{0,.12},{.22,.12},{.22,.16},{0,.16}},8,colors.black,.2,.3)
 box(m,.17,.15,.27,.06,2.2,.06,colors.lightGray)
 tri(m,{.2,2.35,.3},{.2,1.85,.3},{.2,2.1,-.55},colors.red,nil)
 ball(m,.16,-.55,.31,-.4,colors.white,6)
 return m
end
function E.pinelanes()
 local m={}
 -- A pin, then the ball beside it.
 lathe(m,{{0,0},{.22,0},{.38,.4},{.42,.7},{.3,1.1},{.17,1.4},{.16,1.55},{.24,1.8},{.22,2.0},{.12,2.18},{0,2.22}},10,
  {colors.white,colors.white,colors.white,colors.white,colors.red,colors.white,colors.red,colors.white,colors.white,colors.white},.2,-.35)
 ball(m,.62,-.25,.62,.55,colors.blue,10)
 for _,h in ipairs({{.85,.4},{.95,.6},{.75,.65}}) do
  local y,z=h[1],h[2]+.15
  quad(m,{-.86,y-.06,z-.06},{-.86,y-.06,z+.06},{-.86,y+.06,z+.06},{-.86,y+.06,z-.06},colors.black,{-1,0,0})
 end
 return m
end
function E.pinedungeon()
 local m={}
 -- Sword point up, then a shield leaning in front.
 box(m,-.05,.95,-.12,.1,1.35,.24,colors.lightGray)
 tri(m,{-.05,2.3,-.12},{-.05,2.3,.12},{-.05,2.55,0},colors.lightGray,{-1,0,0})
 tri(m,{.05,2.3,-.12},{.05,2.3,.12},{.05,2.55,0},colors.lightGray,{1,0,0})
 box(m,-.1,.82,-.55,.2,.13,1.1,colors.yellow)
 box(m,-.06,.4,-.07,.12,.42,.14,colors.brown)
 box(m,-.09,.26,-.1,.18,.15,.2,colors.yellow)
 local s={}
 for k=0,10 do local a=k/10*math.pi; s[#s+1]={math.cos(a)*.6,.95+math.sin(a)*.25} end
 local x=-.4
 for k=1,#s-1 do tri(m,{x,.15,0},{x,s[k][2],s[k][1]},{x,s[k+1][2],s[k+1][1]},colors.purple,{-1,0,0}) end
 tri(m,{x,.95,-.6},{x,.95,.6},{x,.15,0},colors.purple,{-1,0,0})
 tri(m,{x-.01,.95,-.1},{x-.01,.95,.1},{x-.01,.35,0},colors.yellow,{-1,0,0})
 quad(m,{x-.01,.8,-.4},{x-.01,.8,.4},{x-.01,.7,.35},{x-.01,.7,-.35},colors.yellow,{-1,0,0})
 return m
end
-- The startup tile: a power symbol.
function E.boot(lit)
 local m={}
 local c=lit and colors.lime or colors.lightGray
 local n=16; local R,r,cy=.95,.68,1.2
 local function at(rad,ang,x) return {x,cy+math.cos(ang)*rad,math.sin(ang)*rad} end
 for k=0,n-1 do
  local a,b=k/n*2*math.pi,(k+1)/n*2*math.pi
  -- Leave a gap at the top for the bar.
  if math.cos((a+b)/2)<.9 then
   quad(m,at(R,a,-.1),at(R,b,-.1),at(r,b,-.1),at(r,a,-.1),c,{-1,0,0})
   quad(m,at(R,a,.1),at(R,b,.1),at(r,b,.1),at(r,a,.1),colors.gray,{1,0,0})
  end
 end
 box(m,-.12,1.05,-.14,.24,1.15,.28,c)
 return m
end
-- Anything without an emblem gets a small cabinet with its initials.
function E.default(name,title)
 local m={}
 box(m,-.6,0,-.9,1.2,2.3,1.8,colors.blue)
 box(m,-.65,1.2,-.7,.1,.8,1.4,colors.black)
 local text=(title or name or '?'):gsub('[^%u]',''):sub(1,2)
 local ok=true
 for ch in text:gmatch('.') do if not font.glyphs[ch] then ok=false end end
 if ok and #text>0 then front(m,-.67,text,1.85,.12,colors.yellow) end
 return m
end
function M.model(name,title,lit)
 if name=='boot' then return E.boot(lit) end
 return (E[name] or E.default)(name,title)
end
return M
