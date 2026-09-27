-- Deterministic, turn-based dungeon state. No terminal or clock dependency.
local world={}
local maps={
  {
    "###########",
    "#@..#....>#",
    "#...#.....#",
    "#..g...$..#",
    "#....#....#",
    "#..P......#",
    "#......g..#",
    "#.........#",
    "###########",
  },
  {
    "###########",
    "#@...#...>#",
    "#..g.#....#",
    "#.........#",
    "#.#..s....#",
    "#.#....$..#",
    "#....P....#",
    "#.........#",
    "###########",
  },
  {
    "###########",
    "#@......#>#",
    "#..g....#.#",
    "#.....s...#",
    "#..#......#",
    "#..P.$....#",
    "#....g....#",
    "#.........#",
    "###########",
  },
}
world.maps=maps
local vectors={north={0,-1},south={0,1},west={-1,0},east={1,0}}
local glyph={g=true,s=true}
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
      elseif c==">" then state.exit={x=x,z=z}
      elseif glyph[c] then
        state.monsters[#state.monsters+1]={x=x,z=z,kind=c,hp=c=="s" and 3 or 2}
      elseif c=="P" or c=="$" then state.items[key(x,z)]=c end
    end
  end
end
function world.new()
  local state={player={x=0,z=0,hp=12,maxHp=12,potions=1,gold=0,facing="east"},
    turn=0,phase="play",message="Find the stairs on floor 3.",kills=0}
  loadFloor(state,1)
  return state
end
function world.tile(state,x,z)
  return state.tiles[z] and state.tiles[z][x] or "#"
end
function world.monsterAt(state,x,z)
  for i,m in ipairs(state.monsters) do if m.hp>0 and m.x==x and m.z==z then return m,i end end
end
local function attack(state,m)
  m.hp=m.hp-2
  if m.hp<=0 then state.kills=state.kills+1;state.message="You defeat the "..(m.kind=="s" and "shade" or "goblin").."."
  else state.message="You hit the "..(m.kind=="s" and "shade" or "goblin").."." end
end
local function enemiesAct(state)
  local p=state.player
  local hits=0
  for _,m in ipairs(state.monsters) do
    if m.hp>0 then
      local d=math.abs(p.x-m.x)+math.abs(p.z-m.z)
      if d==1 then hits=hits+(m.kind=="s" and 2 or 1)
      elseif d<=4 then
        local dx=p.x-m.x;local dz=p.z-m.z
        local attempts={}
        if math.abs(dx)>=math.abs(dz) then
          attempts={{m.x+(dx>0 and 1 or -1),m.z},{m.x,m.z+(dz>0 and 1 or -1)}}
        else attempts={{m.x,m.z+(dz>0 and 1 or -1)},{m.x+(dx>0 and 1 or -1),m.z}} end
        for _,pos in ipairs(attempts) do
          local x,z=pos[1],pos[2]
          if world.tile(state,x,z)~="#" and not (x==p.x and z==p.z)
            and not world.monsterAt(state,x,z) then m.x=x;m.z=z;break end
        end
      end
    end
  end
  if hits>0 then
    p.hp=math.max(0,p.hp-hits)
    state.message=state.message.." Monsters hit for "..hits.."."
    if p.hp==0 then state.phase="lost";state.message="You fall in the dungeon. NEW GAME or QUIT." end
  end
end
function world.act(state,action)
  if state.phase~="play" then return false end
  local p=state.player
  local consumed=false
  if vectors[action] then
    local v=vectors[action];p.facing=action
    local x,z=p.x+v[1],p.z+v[2]
    if world.tile(state,x,z)=="#" then state.message="A stone wall blocks the way.";return false end
    local m=world.monsterAt(state,x,z)
    if m then attack(state,m)
    else
      p.x=x;p.z=z;state.message="You move "..action.."."
      local item=state.items[key(x,z)]
      if item=="$" then p.gold=p.gold+5;state.message="You found 5 gold.";state.items[key(x,z)]=nil
      elseif item=="P" then p.potions=p.potions+1;state.message="You found a potion.";state.items[key(x,z)]=nil end
      if x==state.exit.x and z==state.exit.z then
        if state.floor==#maps then state.phase="won";state.message="You escaped with "..p.gold.." gold!"
        else loadFloor(state,state.floor+1);state.message="You descend to floor "..state.floor.."." end
        state.turn=state.turn+1;return true
      end
    end
    consumed=true
  elseif action=="attack" then
    local v=vectors[p.facing];local m=world.monsterAt(state,p.x+v[1],p.z+v[2])
    if m then attack(state,m) else state.message="Your swing finds empty air." end
    consumed=true
  elseif action=="heal" then
    if p.potions<1 then state.message="No potions remain.";return false end
    if p.hp==p.maxHp then state.message="Health is already full.";return false end
    p.potions=p.potions-1;p.hp=math.min(p.maxHp,p.hp+5)
    state.message="You drink a potion (+5 HP).";consumed=true
  elseif action=="wait" then state.message="You wait.";consumed=true
  end
  if consumed then state.turn=state.turn+1;enemiesAct(state) end
  return consumed
end
function world.symbol(state,x,z)
  if x==state.player.x and z==state.player.z then return "@" end
  local m=world.monsterAt(state,x,z);if m then return m.kind end
  if state.items[key(x,z)] then return state.items[key(x,z)] end
  if x==state.exit.x and z==state.exit.z then return ">" end
  return world.tile(state,x,z)
end
return world
