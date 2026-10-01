-- Deterministic, turn-based dungeon state. No terminal or clock dependency.
local world={}
local maps={
  {
    "###########",
    "#@..#....>#",
    "#...#.....#",
    "#..z...$..#",
    "#....#....#",
    "#..%......#",
    "#......z..#",
    "#.........#",
    "###########",
  },
  {
    "###########",
    "#@...#...>#",
    "#..z.#....#",
    "#.........#",
    "#.#..k....#",
    "#.#....$..#",
    "#....%....#",
    "#.........#",
    "###########",
  },
  { -- the Warden's arena: pillars block the sonic boom
    "###########",
    "#@........#",
    "#..#...#..#",
    "#.%.......#",
    "#....W...O#",
    "#.%.......#",
    "#..#...#..#",
    "#.........#",
    "###########",
  },
}
world.maps=maps
world.kinds={
  z={name="zombie",hp=2,dmg=1},
  k={name="skeleton",hp=3,dmg=2},
  W={name="Warden",hp=14,dmg=2},
}
world.spawns={{2,8},{10,8}} -- where the enraged Warden raises zombies
local BOOM_DAMAGE,BOOM_RANGE=4,5
local vectors={north={0,-1},south={0,1},west={-1,0},east={1,0}}
local facings={"north","east","south","west"}
local function key(x,z) return z..":"..x end
local function loadFloor(state,number)
  local rows=assert(maps[number])
  state.floor=number; state.width=#rows[1]; state.height=#rows
  state.tiles={};state.monsters={};state.items={}
  for z,row in ipairs(rows) do
    assert(#row==state.width,"uneven dungeon row")
    state.tiles[z]={}
    for x=1,#row do
      local c=row:sub(x,x)
      state.tiles[z][x]=c=="#" and "#" or "."
      if c=="@" then state.player.x=x;state.player.z=z
      elseif c==">" or c=="O" then state.exit={x=x,z=z};state.exitGlyph=c
      elseif world.kinds[c] then
        local hp=world.kinds[c].hp
        state.monsters[#state.monsters+1]={x=x,z=z,kind=c,hp=hp,maxHp=hp}
      elseif c=="%" or c=="$" then state.items[key(x,z)]=c end
    end
  end
end
function world.new()
  local state={player={x=0,z=0,hp=12,maxHp=12,potions=1,gold=0,facing="east"},
    turn=0,phase="play",message="Find the End Portal on floor 3.",kills=0}
  loadFloor(state,1)
  return state
end
function world.tile(state,x,z)
  return state.tiles[z] and state.tiles[z][x] or "#"
end
function world.monsterAt(state,x,z)
  for i,m in ipairs(state.monsters) do if m.hp>0 and m.x==x and m.z==z then return m,i end end
end
-- The living Warden on this floor, if any.
function world.boss(state)
  for _,m in ipairs(state.monsters) do if m.kind=="W" and m.hp>0 then return m end end
end
-- The End Portal stays sealed until the Warden falls.
function world.sealed(state)
  return state.floor==#maps and world.boss(state)~=nil
end
local function attack(state,m)
  local name=world.kinds[m.kind].name
  m.hp=m.hp-2
  if m.hp<=0 then
    state.kills=state.kills+1
    if m.kind=="W" then state.message="The Warden falls! The End Portal opens."
    else state.message="You defeat the "..name.."." end
  else state.message="You hit the "..name.."." end
end
local function stepToward(state,m)
  local p=state.player
  local dx=p.x-m.x;local dz=p.z-m.z
  local attempts
  if math.abs(dx)>=math.abs(dz) then
    attempts={{m.x+(dx>0 and 1 or -1),m.z},{m.x,m.z+(dz>0 and 1 or -1)}}
  else attempts={{m.x,m.z+(dz>0 and 1 or -1)},{m.x+(dx>0 and 1 or -1),m.z}} end
  for _,pos in ipairs(attempts) do
    local x,z=pos[1],pos[2]
    if world.tile(state,x,z)~="#" and not (x==p.x and z==p.z)
      and not world.monsterAt(state,x,z) then m.x=x;m.z=z;break end
  end
end
-- Straight row/column line with no wall between a and b.
local function lineOfSight(state,a,b,range)
  if a.x~=b.x and a.z~=b.z then return false end
  local d=math.abs(a.x-b.x)+math.abs(a.z-b.z)
  if d<1 or d>range then return false end
  local sx=b.x>a.x and 1 or b.x<a.x and -1 or 0
  local sz=b.z>a.z and 1 or b.z<a.z and -1 or 0
  for i=1,d-1 do
    if world.tile(state,a.x+sx*i,a.z+sz*i)=="#" then return false end
  end
  return true
end
-- Warden: slams when adjacent, otherwise telegraphs a two-turn sonic boom
-- down any open row or column. Returns damage dealt and an optional message.
local function bossAct(state,m)
  local p=state.player;local hits,msg=0,nil
  if not m.enraged and m.hp*2<=(m.maxHp or world.kinds.W.hp) then
    m.enraged=true;msg="The Warden roars! Zombies rise!"
    for _,s in ipairs(world.spawns) do
      if not (s[1]==p.x and s[2]==p.z) and not world.monsterAt(state,s[1],s[2]) then
        local hp=world.kinds.z.hp
        state.monsters[#state.monsters+1]={x=s[1],z=s[2],kind="z",hp=hp,maxHp=hp}
      end
    end
  end
  if m.rest and m.rest>0 then m.rest=m.rest-1;return hits,msg end
  if m.charging then
    m.charging=m.charging-1
    if m.charging>0 then return hits,msg or "WARDEN CHARGES! Break line of sight!" end
    m.charging=nil;m.rest=2
    if lineOfSight(state,m,p,BOOM_RANGE) then
      return BOOM_DAMAGE,"SONIC BOOM hits you for "..BOOM_DAMAGE.."!"
    end
    return 0,"The sonic boom misses you!"
  end
  local d=math.abs(p.x-m.x)+math.abs(p.z-m.z)
  if d==1 then hits=world.kinds.W.dmg;m.rest=1
  elseif lineOfSight(state,m,p,BOOM_RANGE) then
    m.charging=2;msg="WARDEN CHARGES! Break line of sight!"
  elseif m.enraged or state.turn%2==0 then stepToward(state,m) end
  return hits,msg
end
local function enemiesAct(state)
  local p=state.player
  local hits,bossMsg=0,nil
  for _,m in ipairs(state.monsters) do
    if m.hp>0 then
      if m.kind=="W" then
        local h,msg=bossAct(state,m);hits=hits+h;bossMsg=msg or bossMsg
      else
        local d=math.abs(p.x-m.x)+math.abs(p.z-m.z)
        if d==1 then hits=hits+world.kinds[m.kind].dmg
        elseif d<=4 then stepToward(state,m) end
      end
    end
  end
  if hits>0 then
    p.hp=math.max(0,p.hp-hits)
    if bossMsg then state.message=bossMsg
    else state.message=state.message.." Mobs hit for "..hits.."." end
    if p.hp==0 then state.phase="lost";state.message="You died! NEW GAME or QUIT." end
  elseif bossMsg then state.message=bossMsg end
end
function world.act(state,action)
  if state.phase~="play" then return false end
  local p=state.player
  local consumed=false
  if action=="turn_left" or action=="turn_right" then
    for i,facing in ipairs(facings) do
      if p.facing==facing then
        p.facing=facings[(i+(action=="turn_left" and 2 or 0))%4+1]
        break
      end
    end
    state.message=action=="turn_left" and "You turn left." or "You turn right."
    consumed=true
  elseif action=="forward" or action=="backward" then
    local v=vectors[p.facing];local step=action=="forward" and 1 or -1
    local x,z=p.x+v[1]*step,p.z+v[2]*step
    if world.tile(state,x,z)=="#" then state.message="A stone wall blocks the way.";return false end
    local m=world.monsterAt(state,x,z)
    if not m and x==state.exit.x and z==state.exit.z and world.sealed(state) then
      state.message="The End Portal is sealed while the Warden lives.";return false
    end
    if m then attack(state,m)
    else
      p.x=x;p.z=z;state.message="You step "..action.."."
      local item=state.items[key(x,z)]
      if item=="$" then p.gold=p.gold+5;state.message="You found 5 emeralds.";state.items[key(x,z)]=nil
      elseif item=="%" then p.potions=p.potions+1;state.message="You found a steak.";state.items[key(x,z)]=nil end
      if x==state.exit.x and z==state.exit.z then
        if state.floor==#maps then state.phase="won";state.message="You entered the End Portal with "..p.gold.." emeralds!"
        else
          loadFloor(state,state.floor+1);state.message="You climb down to floor "..state.floor.."."
          if state.floor==#maps then p.hp=p.maxHp;state.message="A campfire warms you. Hearts restored." end
        end
        state.turn=state.turn+1;return true
      end
    end
    consumed=true
  elseif action=="attack" then
    local v=vectors[p.facing];local m=world.monsterAt(state,p.x+v[1],p.z+v[2])
    if m then attack(state,m) else state.message="Your swing finds empty air." end
    consumed=true
  elseif action=="heal" then
    if p.potions<1 then state.message="No steak left.";return false end
    if p.hp==p.maxHp then state.message="Hearts are already full.";return false end
    p.potions=p.potions-1;p.hp=math.min(p.maxHp,p.hp+5)
    state.message="You eat a steak (+5 hearts).";consumed=true
  elseif action=="wait" then state.message="You wait.";consumed=true
  end
  if consumed then state.turn=state.turn+1;enemiesAct(state) end
  return consumed
end
function world.symbol(state,x,z)
  if x==state.player.x and z==state.player.z then return "@" end
  local m=world.monsterAt(state,x,z);if m then return m.kind end
  if state.items[key(x,z)] then return state.items[key(x,z)] end
  if x==state.exit.x and z==state.exit.z then return state.exitGlyph end
  return world.tile(state,x,z)
end
return world
