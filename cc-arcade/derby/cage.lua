-- The cashier's cage: a Pine3D croupier's booth seen from the customer's side of the bars.
-- Camera on -x looking +x; y is up and +z is screen right, like the casino tables.
-- The brass pass-through tray in the middle of the bars carries the pile of diamonds
-- you are about to move; the vault plaque at the back shows the card's balance.
local pine=require('derby.vendor.Pine3D')
local mesh=require('casino.mesh')
local font=require('casino.font')
local M={}
M.minW,M.minH=39,19
local tri,quad,box=mesh.tri,mesh.quad,mesh.box
M.trayX,M.trayY=-3.6,1.42
M.vaultX=4.4
-- A cut gem centred on (cx,cy,cz) with half-width s: pale crown above, cyan pavilion below.
local function gem(m,cx,cy,cz,s)
 local top,bot={cx,cy+.55*s,cz},{cx,cy-.75*s,cz}
 local ring={{cx+s,cy,cz},{cx,cy,cz+s},{cx-s,cy,cz},{cx,cy,cz-s}}
 for i=1,4 do
  local a,b=ring[i],ring[i%4+1]
  local mid={(a[1]+b[1])/2,cy,(a[3]+b[3])/2}
  local up={mid[1]-cx,.8,mid[3]-cz}; local down={mid[1]-cx,-.8,mid[3]-cz}
  tri(m,a,b,top,i%2==0 and colors.white or colors.lightBlue,up)
  tri(m,a,b,bot,colors.cyan,down)
 end
end
-- A pyramid of n gems (at most 30) resting on y=0, filling the bottom layer first.
function M.pile(n)
 local m={}; local step,s=.5,.22
 local layers={4,3,2,1}; local placed=0
 for k,side in ipairs(layers) do
  local off=-(side-1)*step/2
  for row=0,side-1 do for col=0,side-1 do
   if placed>=n then return m end
   placed=placed+1
   gem(m,off+row*step,s*.75+(k-1)*.3,off+col*step,s)
  end end
 end
 return m
end
-- A stack of chips as stacked flat boxes, colour per stack.
local function chipStack(m,x,z,n,color)
 for i=0,n-1 do box(m,x,M.trayY-.12+i*.07,z,.42,.06,.42,i%2==0 and color or colors.white) end
end
-- Digits as lit glyphs on the vault plaque; blank (just the plaque) when there is no balance.
function M.plaque(text)
 local m={}
 box(m,M.vaultX+1.46,2.05,-2.6,.04,1.7,5.2,colors.yellow)
 box(m,M.vaultX+1.42,2.1,-2.5,.04,1.6,5,colors.black)
 if text and text~='' then
  local cell=math.min(.26,4.6/(#text*3.6))
  local w=font.width(text)*cell
  font.draw(m,text,-w/2,2.1+1.6/2+2.5*cell,cell,colors.lime,function(u,v) return {M.vaultX+1.41,v,u} end,{-1,0,0})
 else
  box(m,M.vaultX+1.41,2.7,-.6,.01,.1,1.2,colors.red)
 end
 return m
end
-- The fixed room: floor, panelled walls, croupier's table, safe, shelves, bars.
function M.room()
 local m={}
 local dark,wood,gold=colors.gray,colors.brown,colors.yellow
 box(m,-16,-.5,-9,28,.5,18,wood)
 -- Back and side walls: panelled below a gold rail, plaster above.
 box(m,M.vaultX+1.5,-.5,-9,.6,7,18,dark)
 box(m,M.vaultX+1.4,0,-9,.1,1.4,18,wood)
 box(m,M.vaultX+1.35,1.4,-9,.1,.12,18,gold)
 box(m,-16,-.5,9,28,7,.6,dark); box(m,-16,-.5,-9.6,28,7,.6,dark)
 box(m,-16,1.4,8.9,28,.12,.1,gold); box(m,-16,1.4,-8.9,28,.12,.1,gold)
 -- Croupier's table inside the cage: felt top, wooden skirt, chip racks along its back.
 box(m,-3.0,0,-5.6,4.6,1.3,11.2,wood)
 box(m,-3.0,1.3,-5.6,4.6,.1,11.2,colors.green)
 box(m,-3.0,1.3,-5.7,4.6,.2,.1,wood); box(m,-3.0,1.3,5.6,4.6,.2,.1,wood)
 box(m,1.5,1.3,-5.6,.1,.2,11.2,wood)
 local zs={-4.6,-3.8,-3.0,-2.2,2.2,3.0,3.8,4.6}
 local cs={colors.white,colors.red,colors.blue,colors.lime,colors.black,colors.lime,colors.blue,colors.red}
 for i,z in ipairs(zs) do chipStack(m,.4,z,3+i%4,cs[i]) end
 -- Ledger and a banker's lamp on the felt.
 box(m,-1.6,1.4,-4.4,1.1,.09,.8,colors.white); box(m,-1.6,1.4,-4.45,1.1,.1,.05,colors.red)
 box(m,-1.0,1.4,3.9,.1,.6,.1,gold); box(m,-1.2,2.0,3.7,.5,.2,.5,colors.green)
 -- Safe against the back wall, dial and handle toward the room.
 box(m,M.vaultX-.3,0,3.2,1.8,3.1,3.4,colors.lightGray)
 box(m,M.vaultX-.35,.3,3.4,.06,2.5,3.0,dark)
 box(m,M.vaultX-.42,1.3,4.3,.08,.5,.5,gold); box(m,M.vaultX-.42,1.1,5.0,.08,.9,.14,colors.red)
 -- Shelf of stored gems on the left of the back wall.
 box(m,M.vaultX+.6,1.2,-8.2,.9,.12,4.4,wood); box(m,M.vaultX+.6,2.5,-8.2,.9,.12,4.4,wood)
 for i=0,5 do
  gem(m,M.vaultX+1.0,1.45,-7.6+i*.7,.2); gem(m,M.vaultX+1.0,2.75,-7.6+i*.7,.2)
 end
 -- The cage front: posts, a lintel with the diamond mark, a counter panel and brass bars.
 local x=-3.7
 for _,z in ipairs({-6.2,6.0}) do box(m,x,0,z,.3,5.2,.3,gold) end
 box(m,x,4.4,-6.2,.3,.8,12.5,gold)
 box(m,x-.02,4.55,-.5,.05,.5,1,colors.black)
 quad(m,{x-.06,4.8,0},{x-.06,4.6,.35},{x-.06,4.4,0},{x-.06,4.6,-.35},colors.lightBlue,{-1,0,0})
 box(m,x,0,-6.2,.3,1.3,12.5,wood)
 box(m,x-.05,1.25,-6.3,.4,.07,12.7,gold)
 local z=-5.6
 while z<5.7 do
  if math.abs(z)>1.75 then box(m,x+.1,1.3,z,.07,3.1,.07,gold) end
  z=z+.62
 end
 -- The pass-through tray the diamonds ride on, with a low brass lip.
 box(m,M.trayX-1.0,M.trayY-.2,-1.55,2.2,.1,3.1,gold)
 box(m,M.trayX-1.0,M.trayY-.1,-1.55,2.2,.18,.08,gold); box(m,M.trayX-1.0,M.trayY-.1,1.47,2.2,.18,.08,gold)
 box(m,M.trayX-1.0,M.trayY-.1,-1.55,.08,.18,3.1,gold)
 return m
end
-- Pine3D view: v = {balance, count, dx, hidePile}. Text overlays are drawn below the scene.
local function line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y<1 or y>h then return end
 t.setCursorPos(1,y); t.setBackgroundColor(bg or colors.black); t.setTextColor(fg or colors.white)
 t.write((tostring(text)..string.rep(' ',w)):sub(1,w))
end
M.line=line
-- Three buttons across the bottom two rows; labels sit on the last row.
function M.slots(w)
 local third=math.floor(w/3)
 return {{x1=1,x2=third},{x1=third+1,x2=2*third},{x1=2*third+1,x2=w}}
end
M.barColors={{colors.black,colors.lime},{colors.black,colors.yellow},{colors.white,colors.red}}
function M.new(t)
 assert(t.isColor(),'The cashier cage requires an advanced colour computer or monitor')
 require('derby.palette').apply(t)
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(1,2,w,math.max(1,h-6)); f:setBackgroundColor(colors.black); f:setFoV(48)
 local roomObj=f:newObject(M.room(),0,0,0)
 local plaqueObj,plaqueText=f:newObject(M.plaque(nil),0,0,0),nil
 local piles,pileObj,pileKey={}, nil, nil
 local function aim() mesh.look(f,-13,3.8,0,0,1.7,0) end
 aim()
 term.redirect(old)
 local api={frame=f}
 -- v: balance (number|nil), count, dx (pile offset toward the vault, 0 at the tray),
 -- hidePile, title, info, prompt, status, hint, options={{label},{label},{label}}.
 function api:draw(v)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(1,2,w,math.max(1,h-6)); aim() end
  if w<M.minW or h<M.minH then
   t.setBackgroundColor(colors.black); t.clear(); line(t,2,'CASHIER: display needs 39 x 19'); line(t,4,'Resize or use a larger monitor.')
   term.redirect(previous); return
  end
  local text=v.balance and tostring(v.balance) or nil
  if text~=plaqueText then plaqueObj:setModel(M.plaque(text)); plaqueText=text end
  local objects={roomObj,plaqueObj}
  local n=math.max(1,math.min(30,v.count or 5))
  if not v.hidePile then
   local model=piles[n]; if not model then model=M.pile(n); piles[n]=model end
   if not pileObj then pileObj=f:newObject(model,0,0,0); pileKey=n
   elseif pileKey~=n then pileObj:setModel(model); pileKey=n end
   pileObj:setPos(M.trayX+(v.dx or 0),M.trayY-.1,0)
   objects[#objects+1]=pileObj
  end
  f:drawObjects(objects); f:drawBuffer()
  line(t,1,' '..(v.title or 'DIAMOND CASHIER'),colors.white,colors.blue)
  local right='1 DIAMOND = 1 CREDIT '
  t.setCursorPos(math.max(1,w-#right+1),1); t.setTextColor(colors.yellow); t.setBackgroundColor(colors.blue); t.write(right)
  line(t,h-5,' '..(v.info or ''),colors.white,colors.gray)
  line(t,h-4,' '..(v.prompt or ''),colors.yellow,colors.black)
  line(t,h-3,' '..(v.status or ''),colors.white,colors.black)
  line(t,h-2,' '..(v.hint or ''),colors.lightGray,colors.black)
  for i,s in ipairs(M.slots(w)) do
   local label=v.options and v.options[i] or ''
   local width=s.x2-s.x1+1; local lp=math.max(0,math.floor((width-#label)/2))
   local fg,bg=M.barColors[i][1],M.barColors[i][2]
   if label=='' then fg,bg=colors.gray,colors.black end
   for row=h-1,h do
    t.setCursorPos(s.x1,row); t.setTextColor(fg); t.setBackgroundColor(bg)
    t.write(row==h and (string.rep(' ',lp)..label..string.rep(' ',width)):sub(1,width) or string.rep(' ',width))
   end
  end
  term.redirect(previous)
 end
 return api
end
return M
