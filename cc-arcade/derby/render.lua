local pine=require('derby.vendor.Pine3D')
local scene=require('derby.scene')
local sim=require('derby.sim')
local M={}
local function line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y>h or y<1 then return end
 t.setCursorPos(1,y); t.setBackgroundColor(bg or colors.black); t.setTextColor(fg or colors.white)
 t.write((text..string.rep(' ',w)):sub(1,w))
end
M.line=line
function M.new(t)
 assert(t.isColor(),'Pine3D Derby requires an advanced colour computer or monitor')
 require('derby.palette').apply(t)
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(1,4,w,math.max(1,h-8)); f:setBackgroundColor(colors.lightBlue); f:setFoV(65)
 local track=f:newObject(scene.track(false),0,0,0)
 local horses={}; local objects={track}; local frames={}
 for i=1,3 do
  frames[i]={}; for p=1,8 do frames[i][p]=scene.horse(i,(p-1)*math.pi/4) end
  horses[i]=f:newObject(frames[i][1],0,0,0); objects[#objects+1]=horses[i]
 end
 term.redirect(old)
 local api={}
 local smooth
 local function look(x,y,z,tx,ty,tz)
  local dx,dz=tx-x,tz-z
  f:setCamera({x=x,y=y,z=z,rotX=-90,rotY=math.deg(math.atan2(dz,dx)),rotZ=math.deg(math.atan2(ty-y,math.sqrt(dx*dx+dz*dz)))})
 end
 function api:draw(v,camera,exhibition)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(1,4,w,math.max(1,h-8)) end
  if w<39 or h<19 then
   t.setBackgroundColor(colors.black); t.clear(); line(t,2,'DERBY: display needs 39 x 19'); line(t,4,'Resize or use a larger monitor.'); term.redirect(previous); return
  end
  local positions=v.positions or {0,0,0}; local leader=1
  for i=2,3 do if positions[i]>positions[leader] then leader=i end end
  for i,o in ipairs(horses) do
   local x,z,a=scene.pose(positions[i]>=1 and .999 or positions[i],(i-1)*2)
   local running=v.phase=='RUNNING'; local p=running and math.floor((v.tick or 0)*.8)%8+1 or 1
   o:setModel(frames[i][p]); o:setPos(x,running and math.abs(math.sin((v.tick or 0)*.45+i))*.13 or 0,z); o:setRot(0,a,0)
  end
  if camera~='follow' then smooth=nil end
  if camera=='overview' then look(-65,58,60,0,0,0); f:setFoV(68)
  elseif camera=='finish' then look(-36,9,30,-17,1,16); f:setFoV(70)
  elseif v.phase~='RUNNING' then look(-43,15,36,-9,1,16); f:setFoV(70)
  else
   local progress=(positions[1]+positions[2]+positions[3])/3
   local x,z,a=scene.pose(math.min(.999,progress),2)
   local target={x-math.cos(a)*15+math.sin(a)*13,10,z+math.sin(a)*15+math.cos(a)*13,x,1.3,z}
   smooth=smooth or target
   for i=1,6 do smooth[i]=smooth[i]+(target[i]-smooth[i])*.2 end
   look(table.unpack(smooth)); f:setFoV(76)
  end
  f:drawObjects(objects); f:drawBuffer()
  line(t,1,' PINE3D DERBY'..(exhibition and ' | EXHIBITION - NO MONEY' or ' | '..tostring(v.id or 'CONNECTING')),colors.white,colors.blue)
  line(t,2,' '..(v.paused and 'PAUSED' or v.phase or 'CONNECTING')..((v.seconds or 0)>0 and (' | '..v.seconds..' seconds') or ''),colors.yellow)
  local win=v.order and v.order[1]
  line(t,3,win and (' WINNER: '..win..' '..sim.horses[win].name) or ' Same race. Three horses. Pick your winner.',colors.white)
  for i=1,3 do line(t,h-5+i,' '..i..' '..sim.horses[i].name..'  '..math.floor((positions[i] or 0)*100)..'%',colors.white) end
  line(t,h-1,' [C] Camera: '..(camera or 'follow')..'  [Q] Exit',colors.yellow)
  line(t,h,exhibition and ' Practice only | 1=Follow 2=Overview 3=Finish' or ' Bet at a station | 1=Follow 2=Overview 3=Finish',colors.white)
  term.redirect(previous)
 end
 return api
end
return M
