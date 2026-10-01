local pine=require('derby.vendor.Pine3D')
local scene=require('pinebox.scene')
local mesh=require('casino.mesh')
local M={}
M.minW,M.minH=39,19
-- The wide shot frames the tray and the board; throws push in on the dice.
M.wide={-12.5,8.5,0,1.2,.6,0}
local function line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y>h or y<1 then return end
 t.setCursorPos(1,y); t.setBackgroundColor(bg or colors.black); t.setTextColor(fg or colors.white)
 t.write((text..string.rep(' ',w)):sub(1,w))
end
function M.slots(w)
 local third=math.floor(w/3)
 return {{x1=1,x2=third},{x1=third+1,x2=2*third},{x1=2*third+1,x2=w}}
end
M.barColors={{colors.black,colors.white},{colors.black,colors.yellow},{colors.white,colors.red}}
function M.new(t)
 assert(t.isColor(),'Pine Shut the Box requires an advanced colour computer or monitor')
 require('casino.palette').apply(t)
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(1,2,w,math.max(1,h-4)); f:setBackgroundColor(colors.black)
 local stage=f:newObject(scene.stage(),0,0,0)
 local tiles={}
 for n=1,9 do
  tiles[n]={plain=scene.tileModel(n,false),lit=scene.tileModel(n,true)}
  tiles[n].obj=f:newObject(tiles[n].plain,scene.tile.x,0,scene.tileZ(n)); tiles[n].shown='plain'
 end
 local lampOn,lampOff=scene.lamp(colors.yellow),scene.lamp(colors.gray)
 local lamps={}
 for i,p in ipairs(scene.lamps()) do lamps[i]={on=f:newObject(lampOn,p[1],p[2],p[3]),off=f:newObject(lampOff,p[1],p[2],p[3])} end
 local base=scene.dieTriangles()
 local dice={f:newObject(base,0,-5,0),f:newObject(base,0,-5,0)}
 local cam=M.wide
 local function aim() f:setFoV(w/math.max(1,h-4)>3 and 66 or 56); mesh.look(f,table.unpack(cam)) end
 aim()
 term.redirect(old)
 local api={frame=f}
 -- v.tiles[n] = {down=0..1 (fallen), lit=bool, lift=y}; v.dice[i] = {pos, matrix} or nil;
 -- v.camera = {x,y,z, tx,ty,tz} (default: the wide shot)
 function api:draw(v)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(1,2,w,math.max(1,h-4)); aim() end
  if w<M.minW or h<M.minH then
   t.setBackgroundColor(colors.black); t.clear(); line(t,2,'SHUT THE BOX: display needs 39 x 19'); line(t,4,'Resize or use a larger monitor.')
   term.redirect(previous); return
  end
  local c=v.camera or M.wide
  if c~=cam then cam=c; aim() end
  local objects={stage}
  for n,tile in ipairs(tiles) do
   local s=v.tiles and v.tiles[n] or {}
   local want=s.lit and 'lit' or 'plain'
   if tile.shown~=want then tile.obj:setModel(tile[want]); tile.shown=want end
   tile.obj:setPos(scene.tile.x,s.lift or 0,scene.tileZ(n)); tile.obj:setRot(0,0,(s.down or 0)*1.5)
   objects[#objects+1]=tile.obj
  end
  for i,l in ipairs(lamps) do objects[#objects+1]=(v.lamps and v.lamps(i)) and l.on or l.off end
  for i,d in ipairs(dice) do
   local p=v.dice and v.dice[i]
   if p then d:setModel(scene.dieModel(base,p.matrix)); d:setPos(p.pos[1],p.pos[2],p.pos[3]); objects[#objects+1]=d end
  end
  f:drawObjects(objects); f:drawBuffer()
  local right=('CREDITS %s  BET %d '):format(tostring(v.credits or '--'),v.bet or 0)
  line(t,1,' '..(v.title or 'PINE SHUT THE BOX'),colors.yellow,colors.blue)
  t.setCursorPos(math.max(1,w-#right+1),1); t.setTextColor(colors.white); t.setBackgroundColor(colors.blue); t.write(right)
  line(t,h-2,' '..(v.info or ''),colors.white,colors.gray)
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
-- Camera for a throw at time t: chase the dice while they tumble, then the moment they
-- settle snap-zoom onto them (a fast punch-in that overshoots and springs back), hold,
-- and ease back to the wide shot by `back` seconds after they stop.
M.snap=.12
local function mix(a,b,u) local o={}; for i=1,6 do o[i]=a[i]+(b[i]-a[i])*u end; return o end
local function ease(u) u=math.max(0,math.min(1,u)); return u*u*(3-2*u) end
function M.follow(positions,t,duration,back)
 local x=(positions[1][1]+positions[2][1])/2; local z=(positions[1][3]+positions[2][3])/2
 local chase={x-8,6.2,z*.6,x+1,.4,z*.8}
 -- Pull the close-up back when the dice land far apart so both stay in the shot.
 local dx,dz=positions[1][1]-positions[2][1],positions[1][3]-positions[2][3]
 local k=math.max(1,math.min(2.4,math.sqrt(dx*dx+dz*dz)/2.2))
 local close={x-4.4*k,1+6*k,z*.9,x+.3,0,z}
 local punch=mix(chase,close,1.18)
 if t<.3 then return mix(M.wide,chase,ease(t/.3)) end
 if t<duration then return chase end
 local s=t-duration
 if s<M.snap then local u=s/M.snap; return mix(chase,punch,1-(1-u)^3) end
 if s<M.snap+.18 then return mix(punch,close,ease((s-M.snap)/.18)) end
 if s<back-.6 then return close end
 return mix(close,M.wide,ease((s-back+.6)/.6))
end
return M
