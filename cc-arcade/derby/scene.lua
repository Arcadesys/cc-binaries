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
 -- Tiered grandstand on the near straight, with a bold roof and simplified seating.
 for n=0,3 do M.box(m,-12,0,27+n*2,32,1.5+n*1.2,2, n%2==0 and colors.lightGray or colors.gray) end
 M.box(m,-14,7.5,26,36,.5,10,colors.red)
 for _,x in ipairs({-13,20}) do M.box(m,x,0,33,.45,7.5,.45,colors.white) end
 -- Tote board in the infield: three large light panels instead of tiny scenery text.
 M.box(m,5,0,-5,.5,6,.5,colors.gray); M.box(m,18,0,-5,.5,6,.5,colors.gray)
 M.box(m,4,4,-5.2,15,5,.5,colors.black)
 for i=1,3 do M.box(m,5,4+i,-4.65,12,.5,.1,colors.white) end
 return m
end
function M.horse(i,phase)
 local m={}; local body=({colors.orange,colors.lightGray,colors.purple})[i]
 M.box(m,-1.1,1, -.42,2.1,.85,.84,body)
 M.box(m,.55,1.6,-.3,.55,1.1,.6,body)
 M.box(m,.7,2.3,-.31,1,.5,.62,body)
 M.box(m,.8,2.72,-.25,.17,.28,.14,body); M.box(m,.8,2.72,.12,.17,.28,.14,body)
 M.box(m,-1.65,1.4,-.12,.6,.2,.24,colors.black)
 for j=1,4 do
  local x=j<3 and -.75 or .65; local z=j%2==0 and .27 or -.38
  local swing=math.sin(phase+((j==1 or j==4) and 0 or pi))*.3
  M.box(m,x+swing,.12,z,.24,1.05,.23,body)
  M.box(m,x+swing,.05,z,.3,.2,.25,colors.black)
 end
 -- White saddlecloth with a large black numeral on both sides.
 M.box(m,-.5,1.2,-.46,.9,.65,.92,colors.white)
 local patterns={ {'010','110','010','010','111'}, {'111','001','111','100','111'}, {'111','001','111','001','111'} }
 for row,line in ipairs(patterns[i]) do for col=1,3 do if line:sub(col,col)=='1' then
  for _,z in ipairs({-.478,.466}) do M.box(m,-.42+(col-1)*.22,1.82-row*.105,z,.18,.09,.012,colors.black) end
 end end end
 return m
end
return M
