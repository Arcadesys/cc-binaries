-- Deterministic Smiley-tag arena. Fixed 0.1 s ticks; no terminal, clock or network.
-- Tile (x,z) covers [x-.5,x+.5] x [z-.5,z+.5]. Yaw is degrees: 0 faces +x (east),
-- 90 faces +z (south), so turning right adds yaw.
local world={}
world.map={
  "################",
  "#1.....#......2#",
  "#.##.#.#.##.#..#",
  "#.#..#...#..#.##",
  "#.#.##.#r#.##..#",
  "#......#.......#",
  "###.##.###.#.#.#",
  "#...#..r.....#.#",
  "#.#...##.##.r..#",
  "#.#.#..r.....#.#",
  "#...#.##.#.###.#",
  "#.#.......r....#",
  "#.#.##.#.#.##.##",
  "#..r...#.#..#..#",
  "#3...#.....#..4#",
  "################",
}
world.SEATS=4
world.FWD,world.BACK,world.LEFT,world.RIGHT,world.FIRE=1,2,4,8,16
world.TURN=15         -- degrees per tick
world.SPEED=.22       -- tiles per tick
world.RADIUS=.3       -- half-size of a player's collision box
world.HIT=.38         -- bullet-to-centre hit distance
world.BULLET_SPEED=.6
world.BULLET_LIFE=25
world.COOLDOWN=4
world.HP=3
world.RESPAWN=20
world.SHIELD=15
world.WIN=10
world.colors={"yellow","cyan","lime","red"}
local function bit(mask,b) return mask and math.floor(mask/b)%2==1 end
world.bit=bit
local function nextRandom(state)
  state.rng=state.rng*16807%2147483647
  return state.rng
end
function world.random(state,n) return nextRandom(state)%n+1 end
local function load(state)
  local rows=world.map
  state.width=#rows[1];state.height=#rows;state.tiles={};state.spawns={};state.seatSpawn={}
  for z,row in ipairs(rows) do
    assert(#row==state.width,"uneven arena row "..z)
    state.tiles[z]={}
    for x=1,#row do
      local c=row:sub(x,x)
      state.tiles[z][x]=c=="#" and "#" or "."
      if c~="#" and c~="." then
        state.spawns[#state.spawns+1]={x=x,z=z}
        local seat=tonumber(c);if seat then state.seatSpawn[seat]=#state.spawns end
      end
    end
  end
end
function world.tile(state,x,z)
  local row=state.tiles[z];return row and row[x] or "#"
end
local function tileAt(v) return math.floor(v+.5) end
world.tileAt=tileAt
function world.solid(state,px,pz)
  return world.tile(state,tileAt(px),tileAt(pz))=="#"
end
-- Does a box of half-size r centred at (px,pz) touch a wall?
local function blocked(state,px,pz,r)
  for z=tileAt(pz-r),tileAt(pz+r) do
    for x=tileAt(px-r),tileAt(px+r) do
      if world.tile(state,x,z)=="#" then return true end
    end
  end
  return false
end
world.blocked=blocked
-- Yaw from (ax,az) toward (bx,bz), in degrees.
function world.bearing(ax,az,bx,bz)
  return math.deg(math.atan2 and math.atan2(bz-az,bx-ax) or math.atan(bz-az,bx-ax))
end
function world.wrap(a)
  a=a%360;if a>180 then a=a-360 end;return a
end
-- Straight segment with no wall tile on it.
function world.lineOfSight(state,a,b)
  local dx,dz=b.x-a.x,b.z-a.z
  local steps=math.max(1,math.ceil(math.sqrt(dx*dx+dz*dz)/.1))
  for i=1,steps-1 do
    if world.solid(state,a.x+dx*i/steps,a.z+dz*i/steps) then return false end
  end
  return true
end
local function facingCentre(state,x,z)
  return world.bearing(x,z,(state.width+1)/2,(state.height+1)/2)
end
local function place(state,p,spawn)
  p.x,p.z=spawn.x,spawn.z
  p.yaw=math.floor(facingCentre(state,p.x,p.z)/90+.5)*90%360
  p.hp=world.HP;p.alive=true;p.respawn=0;p.shield=world.SHIELD;p.cooldown=0
end
-- The spawn farthest from every living player; ties go to the seeded RNG.
local function freeSpawn(state,who)
  local best,bestD={},-1
  for _,s in ipairs(state.spawns) do
    local d=math.huge
    for _,o in ipairs(state.players) do
      if o~=who and o.alive then d=math.min(d,(o.x-s.x)^2+(o.z-s.z)^2) end
    end
    if d>bestD+1e-9 then best={s};bestD=d elseif math.abs(d-bestD)<=1e-9 then best[#best+1]=s end
  end
  return best[world.random(state,#best)]
end
function world.new(seed)
  local state={tick=0,phase="play",rng=(seed or 1)%2147483646+1,players={},bullets={},events={},
    message="First to "..world.WIN.." tags wins!"}
  load(state)
  for seat=1,world.SEATS do
    local p={seat=seat,score=0,deaths=0}
    place(state,p,state.spawns[state.seatSpawn[seat]])
    p.shield=0
    state.players[seat]=p
  end
  return state
end
local function event(state,e) state.events[#state.events+1]=e end
local function hit(state,victim,owner)
  if victim.shield>0 then event(state,{kind="block",seat=victim.seat,by=owner});return end
  victim.hp=victim.hp-1
  event(state,{kind="hit",seat=victim.seat,by=owner})
  if victim.hp>0 then return end
  victim.alive=false;victim.respawn=world.RESPAWN;victim.deaths=victim.deaths+1
  local shooter=state.players[owner];shooter.score=shooter.score+1
  event(state,{kind="tag",seat=victim.seat,by=owner})
  state.message="P"..owner.." tagged P"..victim.seat.."!"
  if shooter.score>=world.WIN and state.phase=="play" then
    state.phase="over";state.winner=owner;state.message="P"..owner.." WINS!"
  end
end
local function crowded(state,p,x,z)
  for _,o in ipairs(state.players) do
    if o~=p and o.alive then
      local before=(o.x-p.x)^2+(o.z-p.z)^2;local after=(o.x-x)^2+(o.z-z)^2
      if after<(2*world.RADIUS)^2 and after<before then return true end
    end
  end
  return false
end
local function move(state,p,dx,dz)
  if dx~=0 and not blocked(state,p.x+dx,p.z,world.RADIUS) and not crowded(state,p,p.x+dx,p.z) then p.x=p.x+dx end
  if dz~=0 and not blocked(state,p.x,p.z+dz,world.RADIUS) and not crowded(state,p,p.x,p.z+dz) then p.z=p.z+dz end
end
local function stepPlayer(state,p,mask)
  if not p.alive then
    p.respawn=p.respawn-1
    if p.respawn<=0 then place(state,p,freeSpawn(state,p));event(state,{kind="spawn",seat=p.seat}) end
    return
  end
  if p.shield>0 then p.shield=p.shield-1 end
  if p.cooldown>0 then p.cooldown=p.cooldown-1 end
  if bit(mask,world.LEFT) then p.yaw=(p.yaw-world.TURN)%360 end
  if bit(mask,world.RIGHT) then p.yaw=(p.yaw+world.TURN)%360 end
  local dir=(bit(mask,world.FWD) and 1 or 0)-(bit(mask,world.BACK) and 1 or 0)
  if dir~=0 then
    local r=math.rad(p.yaw)
    move(state,p,math.cos(r)*world.SPEED*dir,math.sin(r)*world.SPEED*dir)
  end
  if bit(mask,world.FIRE) and p.cooldown==0 and not state.bullets[p.seat] then
    local r=math.rad(p.yaw);local cx,cz=math.cos(r),math.sin(r)
    local bx,bz=p.x+cx*.3,p.z+cz*.3
    p.cooldown=world.COOLDOWN
    if not world.solid(state,bx,bz) then
      state.bullets[p.seat]={x=bx,z=bz,dx=cx*world.BULLET_SPEED,dz=cz*world.BULLET_SPEED,
        life=world.BULLET_LIFE,owner=p.seat}
      event(state,{kind="fire",seat=p.seat})
    end
  end
end
local SUBSTEPS=4
local function stepBullet(state,b)
  for _=1,SUBSTEPS do
    b.x=b.x+b.dx/SUBSTEPS;b.z=b.z+b.dz/SUBSTEPS
    if world.solid(state,b.x,b.z) then return false end
    for _,p in ipairs(state.players) do
      if p.alive and p.seat~=b.owner and (p.x-b.x)^2+(p.z-b.z)^2<world.HIT^2 then
        hit(state,p,b.owner);return false
      end
    end
  end
  b.life=b.life-1
  return b.life>0
end
-- inputs[seat] is a FWD|BACK|LEFT|RIGHT|FIRE mask.
function world.step(state,inputs)
  state.events={}
  if state.phase~="play" then return end
  state.tick=state.tick+1
  for seat,p in ipairs(state.players) do stepPlayer(state,p,inputs and inputs[seat] or 0) end
  for seat=1,world.SEATS do
    local b=state.bullets[seat]
    if b and not stepBullet(state,b) then state.bullets[seat]=nil end
  end
end
local function round(v) return math.floor(v*100+.5)/100 end
-- Compact copy for the wire. Names and kinds ride along so clients need no lobby state.
function world.snapshot(state,names,kinds)
  local p,b={},{}
  for i,pl in ipairs(state.players) do
    p[i]={round(pl.x),round(pl.z),math.floor(pl.yaw+.5)%360,pl.hp,pl.score,pl.alive and 1 or 0,
      pl.shield,pl.respawn,pl.deaths}
  end
  for seat=1,world.SEATS do
    local bl=state.bullets[seat];if bl then b[#b+1]={round(bl.x),round(bl.z),seat} end
  end
  return {t=state.tick,ph=state.phase,w=state.winner,m=state.message,p=p,b=b,e=state.events,
    n=names,k=kinds}
end
-- A render-ready state rebuilt from a snapshot.
function world.fromSnapshot(snap,base)
  local state=base or {}
  if not state.tiles then load(state) end
  state.tick=snap.t;state.phase=snap.ph;state.winner=snap.w;state.message=snap.m
  state.events=snap.e or {};state.players=state.players or {};state.bullets={}
  for i,v in ipairs(snap.p) do
    local pl=state.players[i] or {seat=i};state.players[i]=pl
    pl.x,pl.z,pl.yaw,pl.hp,pl.score=v[1],v[2],v[3],v[4],v[5]
    pl.alive=v[6]==1;pl.shield=v[7];pl.respawn=v[8];pl.deaths=v[9]
  end
  for _,v in ipairs(snap.b or {}) do state.bullets[v[3]]={x=v[1],z=v[2],owner=v[3]} end
  return state
end
return world
