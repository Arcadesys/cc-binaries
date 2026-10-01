-- Bot Smileys: chase the nearest rival through the maze, turn to face it, fire when lined up.
-- Each bot keeps a little memory (route, jitter, stuck counter) but reads only world state.
local world=require("lib.world")
local bot={}
local Bot={};Bot.__index=Bot
function bot.new(seed)
  return setmetatable({rng=(seed or 7)%2147483646+1,route=nil,routeAge=0,jitter=0,
    stuck=0,lastX=nil,lastZ=nil,wander=0},Bot)
end
function Bot:random(n)
  self.rng=self.rng*16807%2147483647
  return self.rng%n+1
end
local dirs={{1,0},{-1,0},{0,1},{0,-1}}
-- Breadth-first route from tile a to tile b; returns the list of tiles after a.
local function route(state,ax,az,bx,bz)
  local key=function(x,z) return z*256+x end
  local prev={[key(ax,az)]=false};local q={{ax,az}};local head=1
  while q[head] do
    local x,z=q[head][1],q[head][2];head=head+1
    if x==bx and z==bz then
      local path={};local k=key(x,z)
      while prev[k] do path[#path+1]={k%256,math.floor(k/256)};k=prev[k] end
      local out={};for i=#path,1,-1 do out[#out+1]=path[i] end
      return out
    end
    for _,d in ipairs(dirs) do
      local nx,nz=x+d[1],z+d[2];local k=key(nx,nz)
      if prev[k]==nil and world.tile(state,nx,nz)~="#" then prev[k]=key(x,z);q[#q+1]={nx,nz} end
    end
  end
end
bot.route=route
local function steer(mask,diff,tolerance)
  if diff>tolerance then mask=mask+world.RIGHT elseif diff<-tolerance then mask=mask+world.LEFT end
  return mask
end
function Bot:input(state,seat)
  local me=state.players[seat]
  if not me or not me.alive or state.phase~="play" then self.route=nil;return 0 end
  local target,best=nil,math.huge
  for _,o in ipairs(state.players) do
    if o.seat~=seat and o.alive then
      local d=(o.x-me.x)^2+(o.z-me.z)^2
      if d<best then best=d;target=o end
    end
  end
  if state.tick%15==0 then self.jitter=self:random(13)-7 end
  -- Unstick: if pressing forward got us nowhere, back off and turn for a moment.
  if self.lastX and math.abs(me.x-self.lastX)+math.abs(me.z-self.lastZ)<.01 and self.pushing then
    self.stuck=self.stuck+1 else self.stuck=0 end
  self.lastX,self.lastZ=me.x,me.z;self.pushing=false
  if self.wander>0 then
    self.wander=self.wander-1;self.route=nil
    return world.BACK+(self.wanderDir or world.LEFT)
  end
  if self.stuck>6 then
    self.stuck=0;self.wander=4;self.wanderDir=self:random(2)==1 and world.LEFT or world.RIGHT
    return world.BACK+self.wanderDir
  end
  local mask=0
  if target and world.lineOfSight(state,me,target) then
    self.route=nil;self.seen=(self.seen or 0)+1
    local diff=world.wrap(world.bearing(me.x,me.z,target.x,target.z)-me.yaw+self.jitter*.5)
    mask=steer(mask,diff,world.TURN/2)
    -- A short reaction time keeps bots from snap-firing the moment you round a corner.
    if self.seen>3 and math.abs(diff)<9 and not state.bullets[seat] then mask=mask+world.FIRE end
    if best>2.5^2 and math.abs(diff)<40 then mask=mask+world.FWD;self.pushing=true
    elseif best<1.2^2 then mask=mask+world.BACK end
    return mask
  end
  self.seen=0
  -- Out of sight: follow a grid route toward the target (or a random spawn point).
  local tx,tz=world.tileAt(me.x),world.tileAt(me.z)
  self.routeAge=self.routeAge+1
  if not self.route or #self.route==0 or self.routeAge>12 then
    local goal=target
    if not goal then goal=state.spawns[self:random(#state.spawns)] end
    self.route=route(state,tx,tz,world.tileAt(goal.x),world.tileAt(goal.z)) or {}
    self.routeAge=0
  end
  local step=self.route[1]
  while step and step[1]==tx and step[2]==tz do table.remove(self.route,1);step=self.route[1] end
  if not step then return 0 end
  local aimX,aimZ=step[1],step[2]
  -- Re-centre in the current tile before turning a corner so the box clears the walls.
  if step[1]~=tx and math.abs(me.z-tz)>.12 then aimX,aimZ=(tx+step[1])/2,tz
  elseif step[2]~=tz and math.abs(me.x-tx)>.12 then aimX,aimZ=tx,(tz+step[2])/2 end
  local diff=world.wrap(world.bearing(me.x,me.z,aimX,aimZ)-me.yaw)
  mask=steer(mask,diff,world.TURN/2)
  if math.abs(diff)<35 then mask=mask+world.FWD;self.pushing=true end
  return mask
end
return bot
