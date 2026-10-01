local pine=require('derby.vendor.Pine3D')
local scene=require('pinejack.scene')
local mesh=require('casino.mesh')
local M={}
M.minW,M.minH=39,19
local function line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y>h or y<1 then return end
 t.setCursorPos(1,y); t.setBackgroundColor(bg or colors.black); t.setTextColor(fg or colors.white)
 t.write((text..string.rep(' ',w)):sub(1,w))
end
-- Three-way button bar on the bottom row: LEFT, CENTER, RIGHT cabinet buttons.
function M.slots(w)
 local third=math.floor(w/3)
 return {{x1=1,x2=third},{x1=third+1,x2=2*third},{x1=2*third+1,x2=w}}
end
M.barColors={{colors.black,colors.white},{colors.black,colors.yellow},{colors.white,colors.red}}
function M.new(t)
 assert(t.isColor(),'Pine Jack requires an advanced colour computer or monitor')
 require('casino.palette').apply(t)
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(1,2,w,math.max(1,h-5)); f:setBackgroundColor(colors.black); f:setFoV(58)
 local tableObj=f:newObject(scene.table(),0,0,0)
 -- Short, wide displays get a wider lens so the bet circles stay in view.
 local function aim() f:setFoV(w/math.max(1,h-5)>3 and 70 or 58); mesh.look(f,-9.6,7.4,0,.5,0,0) end
 aim()
 term.redirect(old)
 local cards,stacks={},{}
 local function cardModel(c)
  local k=c.rank..c.suit
  cards[k]=cards[k] or scene.cardModel(c.rank,c.suit); return cards[k],k
 end
 local function stackModel(n) stacks[n]=stacks[n] or scene.stack(n); return stacks[n],'chips'..n end
 local pool={}
 local api={frame=f}
 -- v.actors: {id, card={rank,suit} | chips=amount, x,y,z, rx, ry}
 function api:draw(v)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(1,2,w,math.max(1,h-5)); aim() end
  if w<M.minW or h<M.minH then
   t.setBackgroundColor(colors.black); t.clear(); line(t,2,'PINE JACK: display needs 39 x 19'); line(t,4,'Resize or use a larger monitor.')
   term.redirect(previous); return
  end
  local objects={tableObj}
  for _,a in ipairs(v.actors or {}) do
   local model,key
   if a.card then model,key=cardModel(a.card) else model,key=stackModel(a.chips) end
   local o=pool[a.id]
   if not o then o=f:newObject(model,a.x,a.y,a.z); o.key=key; pool[a.id]=o
   elseif o.key~=key then o:setModel(model); o.key=key end
   o:setPos(a.x,a.y,a.z); o:setRot(a.rx or 0,a.ry or 0,0)
   objects[#objects+1]=o
  end
  f:drawObjects(objects); f:drawBuffer()
  local right=('CREDITS %s  BET %d '):format(tostring(v.credits or '--'),v.bet or 0)
  line(t,1,' '..(v.title or 'PINE JACK'),colors.yellow,colors.blue)
  t.setCursorPos(math.max(1,w-#right+1),1); t.setTextColor(colors.white); t.setBackgroundColor(colors.blue); t.write(right)
  line(t,h-3,' '..(v.dealer or ''),colors.white,colors.gray)
  line(t,h-2,' '..(v.player or ''),colors.white,colors.gray)
  local msg=v.message or ''; local pad=math.max(0,math.floor((w-#msg)/2))
  line(t,h-1,string.rep(' ',pad)..msg,v.highlight and colors.black or colors.yellow,v.highlight and colors.yellow or colors.black)
  for i,s in ipairs(M.slots(w)) do
   local label=v.options and v.options[i] and v.options[i].label or ''
   local width=s.x2-s.x1+1; local lp=math.max(0,math.floor((width-#label)/2))
   local fg,bg=M.barColors[i][1],M.barColors[i][2]
   if label=='' then fg,bg=colors.gray,colors.black end
   t.setCursorPos(s.x1,h); t.setTextColor(fg); t.setBackgroundColor(bg)
   t.write((string.rep(' ',lp)..label..string.rep(' ',width)):sub(1,width))
  end
  term.redirect(previous)
 end
 return api
end
return M
