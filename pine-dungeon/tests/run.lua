local world=require("lib.world")
local App=require("lib.app")
local input=require("lib.input")
local ui=require("lib.ui")
local render=require("lib.render")
local function check(value,message) assert(value,message) end
local function pathExists(rows)
  local start,goal
  for z,row in ipairs(rows) do for x=1,#row do
    local c=row:sub(x,x)
    if c=="@" then start={x,z} elseif c==">" then goal={x,z} end
  end end
  check(start and goal,"each floor has a start and exit")
  local q={start};local seen={[start[1]..":"..start[2]]=true};local head=1
  while q[head] do
    local here=q[head];head=head+1
    if here[1]==goal[1] and here[2]==goal[2] then return true end
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local x,z=here[1]+d[1],here[2]+d[2]
      if rows[z] and rows[z]:sub(x,x)~="#" and x>=1 and x<=#rows[z] then
        local k=x..":"..z
        if not seen[k] then seen[k]=true;q[#q+1]={x,z} end
      end
    end
  end
  return false
end
for i,rows in ipairs(world.maps) do
  check(pathExists(rows),"floor "..i.." has a reachable exit")
end
local function routeToExit(s)
  local q={{s.player.x,s.player.z,nil}};local seen={[s.player.x..":"..s.player.z]=true};local head=1
  local dirs={{1,0,"east"},{0,1,"south"},{-1,0,"west"},{0,-1,"north"}}
  while q[head] do
    local here=q[head];head=head+1
    if here[1]==s.exit.x and here[2]==s.exit.z then return here[3] end
    for _,d in ipairs(dirs) do
      local x,z=here[1]+d[1],here[2]+d[2]
      local k=x..":"..z
      if not seen[k] and world.tile(s,x,z)~="#" then
        seen[k]=true;q[#q+1]={x,z,here[3] or d[3]}
      end
    end
  end
end
local facingIndex={north=1,east=2,south=3,west=4}
local function relativeAction(s,direction)
  if not direction then return nil end
  local difference=(facingIndex[direction]-facingIndex[s.player.facing])%4
  return ({[0]="forward",[1]="turn_right",[2]="backward",[3]="turn_left"})[difference]
end
local campaign=world.new()
for _=1,300 do
  if campaign.phase~="play" then break end
  local action=campaign.player.hp<=5 and campaign.player.potions>0 and "heal"
    or relativeAction(campaign,routeToExit(campaign))
  check(action,"campaign route exists")
  world.act(campaign,action)
end
check(campaign.phase=="won","full three-floor campaign is winnable with ordinary moves")
local s=world.new()
check(s.floor==1 and s.player.hp==12 and #s.monsters>0,"new adventure")
s.monsters={}
local turn=s.turn
check(world.act(s,"turn_left") and s.player.facing=="north" and s.player.x==2
  and s.player.z==2 and s.turn==turn+1,"left turn rotates in place and consumes a turn")
check(not world.act(s,"forward") and s.turn==turn+1 and s.player.facing=="north",
  "wall does not consume a turn or change facing")
check(world.act(s,"turn_right") and s.player.facing=="east","right turn rotates in place")
s.monsters={{x=s.player.x+1,z=s.player.z,kind="g",hp=2}}
check(world.act(s,"forward"),"attack by moving into monster")
check(s.kills==1 and s.player.x==2 and s.turn==3,"monster defeated without entering its square")
check(world.act(s,"forward") and s.player.x==3,"dead monster no longer blocks")
s.items["3:3"]="$";s.monsters={}
check(world.act(s,"turn_right") and s.player.facing=="south","turn toward gold")
check(world.act(s,"forward") and s.player.gold==5,"gold pickup")
s.items["3:4"]="P";check(world.act(s,"turn_left") and s.player.facing=="east","turn toward potion")
check(world.act(s,"forward") and s.player.potions==2,"potion pickup")
check(world.act(s,"backward") and s.player.x==3 and s.player.z==3
  and s.player.facing=="east","backward step keeps facing")
local rear=world.new();rear.monsters={{x=2,z=2,kind="g",hp=2}};rear.player.x=3
check(world.act(rear,"backward") and rear.kills==1 and rear.player.x==3
  and rear.player.facing=="east","backward step attacks a monster behind without turning")
local turning=world.new();turning.monsters={{x=3,z=2,kind="g",hp=2}}
check(world.act(turning,"turn_left") and turning.player.hp==11,
  "turning consumes a turn and allows adjacent monster attack")
turning.monsters={}
for _=1,4 do world.act(turning,"turn_right") end
check(turning.player.facing=="north" and turning.player.x==2 and turning.player.z==2,
  "four right turns return to the same position and facing")
s.player.hp=4;check(world.act(s,"heal") and s.player.hp==9 and s.player.potions==1,"healing consumes potion")
check(world.act(s,"attack") and s.turn==11,"empty attack consumes turn")
local death=world.new();death.monsters={{x=death.player.x+1,z=death.player.z,kind="s",hp=3}}
death.player.hp=1;world.act(death,"wait")
check(death.phase=="lost" and death.player.hp==0,"enemy turn can defeat player")
local stairs=world.new();stairs.monsters={}
stairs.exit={x=stairs.player.x+1,z=stairs.player.z}
world.act(stairs,"forward");check(stairs.floor==2 and stairs.player.hp==12,"stairs retain player state")
stairs.monsters={};stairs.floor=3;stairs.exit={x=stairs.player.x+1,z=stairs.player.z}
world.act(stairs,"forward");check(stairs.phase=="won","last stairs end game")
check(not world.act(stairs,"backward"),"ended game cannot move")
local app=App.new()
app:action("forward");local x,turn,facing=app.state.player.x,app.state.turn,app.state.player.facing
app:action("help");app:action("turn_left")
check(app.state.player.x==x and app.state.turn==turn and app.state.player.facing==facing,
  "help preserves position, turn, and facing")
app:action("help");app:action("map");check(app.map,"map toggles")
app:action("menu");app:action("new")
check(app.state.turn==0 and not app.overlay and not app.map,"new game resets state and view")
local buttons=ui.layout(39,19,"play")
check(buttons[1].id=="forward" and buttons[2].id=="backward"
  and buttons[3].id=="turn_left" and buttons[3].label2=="LEFT"
  and buttons[4].id=="turn_right" and buttons[4].label2=="RIGHT",
  "relative movement is clearly labeled on the minimum-size touch display")
for _,b in ipairs(buttons) do
  check(b.h>=2 and b.x>=1 and b.y>=1 and b.x+b.w-1<=39 and b.y+b.h-1<=19,
    "39x19 button bounds and tap height")
end
local tiny=ui.layout(24,12,"play")
check(tiny.small and tiny[1].id=="quit","small screen has quit")
check(input.action({"monitor_touch","right",buttons[1].x,buttons[1].y},buttons,"left")==nil,
  "foreign monitor touch rejected")
check(input.action({"monitor_touch","left",buttons[1].x,buttons[1].y},buttons,"left")=="forward",
  "monitor tap uses visible rectangle")
check(input.action({"key",keys.right,true},buttons,nil)==nil,"held key ignored")
check(input.action({"key",keys.right,false},buttons,nil)=="turn_right","keyboard turn")
check(input.action({"key",keys.down,false},buttons,nil)=="backward","keyboard backward")
for _,size in ipairs({{39,19},{51,19}}) do
  local old=term.current();local t=window.create(old,1,1,size[1],size[2],false)
  term.redirect(t)
  local painter=render.new(t)
  painter:draw(App.new():view())
  local title=t.getLine(1)
  check(title:find("PINE DUNGEON",1,true)~=nil,"rendered title at "..size[1])
  check(#painter.buttons>=11,"visible actions at "..size[1])
  painter:close();term.redirect(old)
end
print("PASS Pine Dungeon maps, combat, loot, stairs, input, state, 39x19 and 51x19 Pine3D")
return true
