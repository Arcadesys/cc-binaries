local pine=require('derby.vendor.Pine3D')
local scene=require('pinebox.scene')
local mesh=require('casino.mesh')
local M={}
M.minW,M.minH=39,19
-- The wide shot frames the tray and the board; throws push in on the dice.
M.wide={-13.5,8.2,0,1.6,1.5,0}
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
M.playerColors={colors.cyan,colors.orange,colors.lime,colors.pink}
-- Rows under the 3D view for the tile strip: big teletext digits when there is room.
function M.strip(h) if h>=34 then return 4,2 elseif h>=24 then return 2,1 end return 1,0 end
-- The 3D view sits between the title row and the strip.
function M.view(w,h) local rows=M.strip(h); return 1,2,w,math.max(1,h-4-rows) end
-- Nine chips centred across the width, one blank column between them.
function M.chips(w)
 local cw=math.max(1,math.floor((w+1)/9)-1); local left=math.floor((w-(9*cw+8))/2)+1
 local out={}; for n=1,9 do out[n]={x1=left+(n-1)*(cw+1),x2=left+(n-1)*(cw+1)+cw-1} end
 return out
end
local font=require('casino.font')
local hex='0123456789abcdef'
local function code(c) local i=math.floor(math.log(c,2)+.5)+1; return hex:sub(i,i) end
-- One chip: digit in fg on bg, drawn with 2x3 teletext subpixels at the given scale
-- (scale 0 writes the plain character on the middle row).
local function chip(t,x,y,cw,rows,scale,text,fg,bg)
 local F,B=code(fg),code(bg)
 if scale==0 then
  local lp=math.floor((cw-#text)/2)
  for r=0,rows-1 do
   local s=r==math.floor((rows-1)/2) and (string.rep(' ',lp)..text..string.rep(' ',cw)):sub(1,cw) or string.rep(' ',cw)
   t.setCursorPos(x,y+r); t.blit(s,F:rep(cw),B:rep(cw))
  end
  return
 end
 local g=font.glyphs[text]; local gw,gh=#g[1]*scale,#g*scale
 local W,H=cw*2,rows*3
 local ox,oy=math.floor((W-gw)/2),math.floor((H-gh)/2)
 local function on(px,py)
  local gx,gy=math.floor((px-ox)/scale),math.floor((py-oy)/scale)
  if px<ox or py<oy or gx>=#g[1] or gy>=#g then return false end
  return g[gy+1]:sub(gx+1,gx+1)=='#'
 end
 for r=0,rows-1 do
  local chars,fgs,bgs={},{},{}
  for c=0,cw-1 do
   local bits=0
   for k=0,5 do if on(c*2+k%2,r*3+math.floor(k/2)) then bits=bits+2^k end end
   if bits>=32 then chars[#chars+1]=string.char(128+(63-bits)); fgs[#fgs+1]=B; bgs[#bgs+1]=F
   else chars[#chars+1]=string.char(128+bits); fgs[#fgs+1]=F; bgs[#bgs+1]=B end
  end
  t.setCursorPos(x,y+r); t.blit(table.concat(chars),table.concat(fgs),table.concat(bgs))
 end
end
function M.new(t)
 assert(t.isColor(),'Pine Shut the Box requires an advanced colour computer or monitor')
 require('casino.palette').apply(t)
 local old=term.redirect(t)
 local w,h=t.getSize()
 local f=pine.newFrame(M.view(w,h)); f:setBackgroundColor(colors.black)
 local stage=f:newObject(scene.stage(),0,0,0)
 local tiles={}
 for n=1,9 do
  tiles[n]={plain=scene.tileModel(n,false),lit=scene.tileModel(n,true)}
  tiles[n].obj=f:newObject(tiles[n].plain,scene.tile.x,scene.tile.y,scene.tileZ(n)); tiles[n].shown='plain'
 end
 local lampOn,lampOff=scene.lamp(colors.yellow),scene.lamp(colors.gray)
 local lamps={}
 for i,p in ipairs(scene.lamps()) do lamps[i]={on=f:newObject(lampOn,p[1],p[2],p[3]),off=f:newObject(lampOff,p[1],p[2],p[3])} end
 local base=scene.dieTriangles()
 local dice={f:newObject(base,0,-5,0),f:newObject(base,0,-5,0)}
 local cam=M.wide
 local function aim() local _,_,vw,vh=M.view(w,h); f:setFoV(vw/vh>3 and 66 or 56); mesh.look(f,table.unpack(cam)) end
 aim()
 term.redirect(old)
 local api={frame=f}
 -- v.tiles[n] = {down=0..1 (fallen), lit=bool, lift=y}; v.dice[i] = {pos, matrix} or nil;
 -- v.camera = {x,y,z, tx,ty,tz} (default: the wide shot)
 function api:draw(v)
  local previous=term.redirect(t)
  local ww,hh=t.getSize()
  if ww~=w or hh~=h then w,h=ww,hh; f:setSize(M.view(w,h)); aim() end
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
   tile.obj:setPos(scene.tile.x,scene.tile.y+(s.lift or 0),scene.tileZ(n)); tile.obj:setRot(0,0,(s.down or 0)*1.5)
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
  -- Tile strip: standing tiles white, the chosen tiles gold, shut tiles dark.
  local rows,scale=M.strip(h)
  t.setBackgroundColor(colors.black)
  for y=h-2-rows,h-3 do t.setCursorPos(1,y); t.clearLine() end
  for n,c in ipairs(M.chips(w)) do
   local s=v.tiles and v.tiles[n] or {}
   local fg,bg=colors.red,colors.white
   if s.lit then fg,bg=colors.black,colors.yellow elseif (s.down or 0)>.5 then fg,bg=colors.gray,colors.black end
   chip(t,c.x1,h-2-rows,c.x2-c.x1+1,rows,scale,tostring(n),fg,bg)
  end
  -- Info row: the players' scores, the one to play lit in their colour, then the info.
  line(t,h-2,'',colors.white,colors.gray); t.setCursorPos(1,h-2)
  local players=v.players
  if players and #players.list>1 then
   for i,score in ipairs(players.list) do
    local pc=M.playerColors[i]
    local tag=(' P%d %s '):format(i,score and tostring(score) or (i==players.current and 'UP' or '--'))
    if i==players.current then t.setTextColor(colors.black); t.setBackgroundColor(pc) else t.setTextColor(pc); t.setBackgroundColor(colors.black) end
    t.write(tag); t.setBackgroundColor(colors.gray); t.write(' ')
   end
  end
  t.setTextColor(colors.white); t.setBackgroundColor(colors.gray); t.write(' '..(v.info or ''))
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
