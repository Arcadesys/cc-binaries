-- Pine3D meshes for the blackjack table. Camera on -x looking +x and down; y is up and
-- +z is screen right. Cards lie flat with their top edge toward +x so they read upright.
local mesh=require('casino.mesh')
local M={}
local tri,quad,box=mesh.tri,mesh.quad,mesh.box
local UP={0,1,0}
-- A flat polygon on the plane y, from (u=z, v=x) points, fanned from the first point.
local function flat(m,y,pts,color,facing)
 for i=2,#pts-1 do
  tri(m,{pts[1][2],y,pts[1][1]},{pts[i][2],y,pts[i][1]},{pts[i+1][2],y,pts[i+1][1]},color,facing or UP)
 end
end
local function ring(cu,cv,r,n,stretch)
 local p={{cu,cv}}
 for i=0,n do local a=i/n*2*math.pi; p[#p+1]={cu+math.cos(a)*r,cv+math.sin(a)*r*(stretch or 1)} end
 return p
end
M.card={length=2,width=1.4}
local font=require('casino.font')
local function glyphs(m,y,text,u0,v0,cell,color) font.flat(m,y,text,u0,v0,cell,color) end
-- Suit pips centred on (cu, cv) with half-size s.
local function pip(m,y,suit,cu,cv,s,color)
 if suit=='D' then flat(m,y,{{cu,cv+s},{cu+s*.75,cv},{cu,cv-s},{cu-s*.75,cv}},color)
 elseif suit=='H' then
  flat(m,y,ring(cu-s*.45,cv+s*.35,s*.5,8),color); flat(m,y,ring(cu+s*.45,cv+s*.35,s*.5,8),color)
  flat(m,y,{{cu-s*.95,cv+s*.25},{cu+s*.95,cv+s*.25},{cu,cv-s}},color)
 elseif suit=='S' then
  flat(m,y,ring(cu-s*.45,cv-s*.2,s*.5,8),color); flat(m,y,ring(cu+s*.45,cv-s*.2,s*.5,8),color)
  flat(m,y,{{cu-s*.95,cv-s*.1},{cu,cv+s},{cu+s*.95,cv-s*.1}},color)
  flat(m,y,{{cu-s*.12,cv-s*.4},{cu+s*.12,cv-s*.4},{cu+s*.3,cv-s},{cu-s*.3,cv-s}},color)
 else
  flat(m,y,ring(cu,cv+s*.45,s*.42,8),color); flat(m,y,ring(cu-s*.5,cv-s*.15,s*.42,8),color); flat(m,y,ring(cu+s*.5,cv-s*.15,s*.42,8),color)
  flat(m,y,{{cu-s*.12,cv},{cu+s*.12,cv},{cu+s*.3,cv-s},{cu-s*.3,cv-s}},color)
 end
end
-- A card centred on the origin, face up (+y). Rotating rotX = pi shows the back.
function M.cardModel(rank,suit)
 local m={}; local L,W=M.card.length/2,M.card.width/2
 local color=(suit=='H' or suit=='D') and colors.red or colors.black
 flat(m,.02,{{-W,L},{W,L},{W,-L},{-W,-L}},colors.white)
 -- Index (rank and a small pip) in the left strip, which stays visible when cards fan
 -- to the right; a larger pip at the lower right shows on the top card.
 local cell=rank=='10' and .15 or .2
 glyphs(m,.035,rank,-W+.08,L-.1,cell,color)
 pip(m,.035,suit,-W+.38,L-1.45,.26,color)
 pip(m,.035,suit,.3,-.45,.32,color)
 -- Back: blue with a lighter inset, facing down.
 local D={0,-1,0}
 flat(m,0,{{-W,L},{W,L},{W,-L},{-W,-L}},colors.blue,D)
 flat(m,-.015,{{-W+.15,L-.15},{W-.15,L-.15},{W-.15,-L+.15},{-W+.15,-L+.15}},colors.lightBlue,D)
 flat(m,-.03,{{0,L-.45},{W-.35,0},{0,-L+.45},{-W+.35,0}},colors.blue,D)
 return m
end
M.chipColors={[1]=colors.white,[5]=colors.red,[10]=colors.blue,[25]=colors.lime,[100]=colors.black}
M.chipValues={100,25,10,5,1}
-- Split an amount into chips, largest first.
function M.chips(amount)
 local out={}
 for _,v in ipairs(M.chipValues) do while amount>=v and #out<12 do out[#out+1]=v; amount=amount-v end end
 return out
end
-- A stack of chips for an amount, sitting on y=0.
function M.stack(amount)
 local m={}; local h=.09
 for i,v in ipairs(M.chips(amount)) do
  local y0,y1=(i-1)*h,i*h-.012
  local p=ring(0,0,.36,8)
  local top={}; for k=2,#p do top[#top+1]=p[k] end
  for k=2,#top-1 do tri(m,{top[1][2],y1,top[1][1]},{top[k][2],y1,top[k][1]},{top[k+1][2],y1,top[k+1][1]},M.chipColors[v],UP) end
  for k=1,#top-1 do
   local a,b=top[k],top[k+1]; local mid={(a[2]+b[2])/2,0,(a[1]+b[1])/2}
   quad(m,{a[2],y0,a[1]},{b[2],y0,b[1]},{b[2],y1,b[1]},{a[2],y1,a[1]},k%2==0 and colors.white or M.chipColors[v],mid)
  end
 end
 return m
end
-- The table: felt, padded rail, betting spots, the insurance arc, shoe and chip tray.
function M.table()
 local m={}
 box(m,-5,-.4,-9,11,.4,18,colors.green)
 box(m,-5.8,-.4,-9.6,.8,.5,19.2,colors.brown)
 box(m,-5,-.4,-9.6,11,.5,.6,colors.brown); box(m,-5,-.4,9,11,.5,.6,colors.brown)
 for _,z in ipairs({-2.8,0,2.8}) do
  local outer=ring(z,-3.3,.62,12); local inner=ring(z,-3.3,.52,12)
  for k=2,#outer-1 do quad(m,{outer[k][2],.005,outer[k][1]},{outer[k+1][2],.005,outer[k+1][1]},{inner[k+1][2],.005,inner[k+1][1]},{inner[k][2],.005,inner[k][1]},colors.white,UP) end
 end
 -- Insurance line: a gold arc between the player's cards and the dealer's.
 local prev
 for n=0,16 do
  local a=(n/16-.5)*1.7; local x,z=-4.5+math.cos(a)*5.2,math.sin(a)*5.2
  if prev then quad(m,{prev[1],.006,prev[2]},{x,.006,z},{x+.08,.006,z},{prev[1]+.08,.006,prev[2]},colors.yellow,UP) end
  prev={x,z}
 end
 -- Shoe on the dealer's left (screen right) and the chip tray behind the dealer cards.
 box(m,3.2,0,5.4,1.8,.9,1.3,colors.red)
 box(m,3.0,.2,5.5,.25,.6,1.1,colors.black)
 box(m,4.4,0,-3.2,.9,.25,6.4,colors.gray)
 local x=4.5
 for i,v in ipairs(M.chipValues) do box(m,x,.25,-3.0+(i-1)*1.25,.7,.18,1.0,M.chipColors[v]) end
 return m
end
M.shoe={3.1,.8,6.0}
-- Where hands and bets sit: player cards, bet circles (one per split hand), dealer cards.
M.playerX,M.betX,M.dealerX=-1.9,-3.3,2.7
M.handZ={[1]={0},[2]={-2.8,2.8}}
M.fan={x=.25,z=.75}
return M
