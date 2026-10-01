local pine=require('derby.vendor.Pine3D')
local scene=require('pineslots.scene')
local M={}
M.minW,M.minH=39,19
local function line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y>h or y<1 then return end
 t.setCursorPos(1,y); t.setBackgroundColor(bg or colors.black); t.setTextColor(fg or colors.white)
 t.write((text..string.rep(' ',w)):sub(1,w))
end
M.line=line
-- Bottom-row button bar; returns the x ranges so touches map to the same buttons.
function M.buttons(w)
 local third=math.floor(w/3)
 return {{x1=1,x2=third,name='bet',label='BET ONE',fg=colors.black,bg=colors.white},
  {x1=third+1,x2=2*third,name='max',label='MAX BET',fg=colors.black,bg=colors.yellow},
  {x1=2*third+1,x2=w,name='cash',label='CASH OUT',fg=colors.white,bg=colors.red}}
end
function M.new(t)
 assert(t.isColor(),'Pine Slots requires an advanced colour computer or monitor')
 require('casino.palette').apply(t)
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(1,2,w,math.max(1,h-3)); f:setBackgroundColor(colors.black); f:setFoV(52)
 local cabinet=f:newObject(scene.cabinet(),0,0,0)
 local reels={}
 for i=1,3 do reels[i]=f:newObject(scene.reel(i),0,0,scene.reelZ[i]*scene.side) end
 local lampOn,lampOff,lineOn,lineOff=scene.lamp(colors.yellow),scene.lamp(colors.gray),scene.lamp(colors.lime),scene.lamp(colors.black)
 local lamps={}
 for i,p in ipairs(scene.lamps()) do lamps[i]={on=f:newObject(lampOn,p[1],p[2],p[3]),off=f:newObject(lampOff,p[1],p[2],p[3])} end
 local lineLamps={}
 for i,pair in ipairs(scene.lineLamps()) do
  lineLamps[i]={}
  for j,p in ipairs(pair) do lineLamps[i][j]={on=f:newObject(lineOn,p[1],p[2],p[3]),off=f:newObject(lineOff,p[1],p[2],p[3])} end
 end
 f:setCamera({x=-17,y=.9,z=0,rotX=-90,rotY=0,rotZ=-2})
 term.redirect(old)
 local api={frame=f}
 -- view: positions[3], lamps(i)->bool, lines[5]->bool, pressed{name=true},
 -- title, credits, bet, win, message, highlight
 function api:draw(v)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(1,2,w,math.max(1,h-3)) end
  if w<M.minW or h<M.minH then
   t.setBackgroundColor(colors.black); t.clear(); line(t,2,'PINE SLOTS: display needs 39 x 19'); line(t,4,'Resize or use a larger monitor.')
   term.redirect(previous); return
  end
  local objects={cabinet}
  for i=1,3 do reels[i]:setRot(0,0,(v.positions[i] or 0)*scene.step) end
  for i,l in ipairs(lamps) do objects[#objects+1]=(v.lamps and v.lamps(i)) and l.on or l.off end
  for i,pair in ipairs(lineLamps) do for _,l in ipairs(pair) do objects[#objects+1]=(v.lines and v.lines[i]) and l.on or l.off end end
  for i=1,3 do objects[#objects+1]=reels[i] end
  f:drawObjects(objects); f:drawBuffer()
  local right=('CREDITS %s  BET %d '):format(tostring(v.credits or '--'),v.bet or 1)
  line(t,1,' '..(v.title or 'PINE SLOTS'),colors.yellow,colors.blue)
  t.setCursorPos(math.max(1,w-#right+1),1); t.setTextColor(colors.white); t.setBackgroundColor(colors.blue); t.write(right)
  local msg=v.message or ''
  local pad=math.max(0,math.floor((w-#msg)/2))
  line(t,h-1,string.rep(' ',pad)..msg,v.highlight and colors.black or colors.yellow,v.highlight and colors.yellow or colors.black)
  for _,b in ipairs(M.buttons(w)) do
   local width=b.x2-b.x1+1; local label=b.label; local lp=math.max(0,math.floor((width-#label)/2))
   local down=v.pressed and v.pressed[b.name]
   t.setCursorPos(b.x1,h); t.setTextColor(down and b.bg or b.fg); t.setBackgroundColor(down and colors.gray or b.bg)
   t.write((string.rep(' ',lp)..label..string.rep(' ',width)):sub(1,width))
  end
  term.redirect(previous)
 end
 return api
end
return M
