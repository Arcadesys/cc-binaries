local world=require("lib.world")
local bot=require("lib.bot")
local function check(value,message) assert(value,message) end
local W=world
-- Arena: every open tile and spawn is reachable from seat 1.
local s=world.new(1)
check(#s.spawns>=8 and s.seatSpawn[4],"four seat spawns and extra respawns")
local start=s.spawns[s.seatSpawn[1]]
local open=0
for z=1,s.height do for x=1,s.width do
  if world.tile(s,x,z)~="#" then
    open=open+1
    check(bot.route(s,start.x,start.z,x,z) or (x==start.x and z==start.z),"tile "..x..","..z.." reachable")
  end
end end
check(world.tile(s,0,0)=="#" and world.tile(s,99,3)=="#","outside is wall")
-- Fresh players: distinct spawns, full health, unshielded.
for i,p in ipairs(s.players) do
  check(p.hp==W.HP and p.alive and p.score==0,"seat "..i.." ready")
  for j=i+1,#s.players do check(p.x~=s.players[j].x or p.z~=s.players[j].z,"distinct spawns") end
end
-- A bare 7x5 room for mechanics.
local function room(rows)
  local r=world.new(3)
  r.tiles={};r.height=#rows;r.width=#rows[1]
  for z,row in ipairs(rows) do r.tiles[z]={};for x=1,#row do r.tiles[z][x]=row:sub(x,x)=="#" and "#" or "." end end
  r.spawns={{x=2,z=2},{x=6,z=4}}
  return r
end
local box={"#######","#.....#","#.....#","#.....#","#######"}
local r=room(box)
local p=r.players[1];p.x,p.z,p.yaw=2,3,0
for i=2,4 do r.players[i].alive=false;r.players[i].respawn=9999;r.players[i].x=-50 end
for _=1,30 do world.step(r,{W.FWD}) end
check(p.x<6.2 and p.x>5.9 and p.z==3,"walking east stops at the wall: "..p.x)
p.yaw=45
for _=1,30 do world.step(r,{W.FWD}) end
check(p.x<6.2 and p.z<4.2 and p.z>3.9,"diagonal into a corner slides then stops: "..p.x..","..p.z)
p.x,p.z,p.yaw=3,3,0
world.step(r,{W.RIGHT});check(p.yaw==15,"right turn adds yaw")
world.step(r,{W.LEFT});check(p.yaw==0,"left turn")
world.step(r,{W.LEFT});check(p.yaw==345,"yaw wraps")
-- Bullets: one at a time, stopped by walls, hit and tag.
r=room(box);for i=3,4 do r.players[i].alive=false;r.players[i].respawn=9999;r.players[i].x=-50 end
local a,b=r.players[1],r.players[2]
a.x,a.z,a.yaw=2,3,0;b.x,b.z,b.yaw=6,3,180;a.shield,b.shield=0,0
world.step(r,{W.FIRE})
check(r.bullets[1] and r.events[1].kind=="fire","fire spawns a bullet")
world.step(r,{W.FIRE});check(r.tick==2 and r.bullets[1],"one bullet in flight at a time")
local hits=0
for _=1,10 do world.step(r,{});for _,e in ipairs(r.events) do if e.kind=="hit" then hits=hits+1 end end end
check(hits==1 and b.hp==W.HP-1 and not r.bullets[1],"bullet hits the rival once")
local tagged
for _=1,2 do
  for _=1,W.COOLDOWN do world.step(r,{}) end
  world.step(r,{W.FIRE})
  for _=1,10 do
    world.step(r,{})
    for _,e in ipairs(r.events) do if e.kind=="tag" then tagged=r.tick end end
  end
end
check(tagged and not b.alive and a.score==1 and b.deaths==1,"third hit tags: score "..a.score)
local wait=r.tick-tagged
while not b.alive do world.step(r,{});wait=wait+1 end
check(wait==W.RESPAWN and b.hp==W.HP and b.shield==W.SHIELD,"respawn after "..wait.." ticks with a shield")
b.x,b.z=6,3
for _=1,W.COOLDOWN do world.step(r,{}) end
world.step(r,{W.FIRE});for _=1,10 do world.step(r,{}) end
check(b.hp==W.HP,"spawn shield blocks a hit")
-- Walls stop bullets.
local walled={"#######","#..#..#","#..#..#","#..#..#","#######"}
r=room(walled);for i=3,4 do r.players[i].alive=false;r.players[i].respawn=9999;r.players[i].x=-50 end
a,b=r.players[1],r.players[2];a.x,a.z,a.yaw=2,3,0;b.x,b.z=6,3;b.shield=0
check(not world.lineOfSight(r,a,b),"wall blocks sight")
world.step(r,{W.FIRE});for _=1,30 do world.step(r,{}) end
check(b.hp==W.HP and not r.bullets[1],"bullet stops at the wall")
-- Winning.
r=room(box);a,b=r.players[1],r.players[2]
for i=3,4 do r.players[i].alive=false;r.players[i].respawn=9999;r.players[i].x=-50 end
a.x,a.z,a.yaw=2,3,0;b.x,b.z=6,3;b.shield=0;b.hp=1;a.score=W.WIN-1
world.step(r,{W.FIRE});for _=1,10 do world.step(r,{}) end
check(r.phase=="over" and r.winner==1,"tenth tag wins")
local t=r.tick;world.step(r,{W.FWD});check(r.tick==t,"finished match is frozen")
-- Snapshot round trip.
s=world.new(5);world.step(s,{W.FWD+W.FIRE,W.RIGHT,0,W.FIRE})
local snap=world.snapshot(s,{"A","B","C","D"},"HBBB")
local copy=world.fromSnapshot(textutils.unserialize(textutils.serialize(snap)))
for i=1,4 do
  check(math.abs(copy.players[i].x-s.players[i].x)<.01 and copy.players[i].yaw==math.floor(s.players[i].yaw+.5)%360,"snapshot seat "..i)
end
check(copy.bullets[1] and copy.bullets[4] and copy.tiles and copy.width==16,"snapshot bullets and arena")
-- Four bots play a full match from a fixed seed.
local function botMatch(seed)
  local m=world.new(seed);local bots={}
  for i=1,4 do bots[i]=bot.new(seed*10+i) end
  local shots=0
  while m.phase=="play" and m.tick<6000 do
    local inputs={}
    for i=1,4 do inputs[i]=bots[i]:input(m,i) end
    world.step(m,inputs)
    for _,e in ipairs(m.events) do if e.kind=="fire" then shots=shots+1 end end
  end
  return m,shots
end
local m,shots=botMatch(42)
local scores={};for i,pl in ipairs(m.players) do scores[i]=pl.score end
check(m.phase=="over" and m.winner,"bot match finishes: tick "..m.tick.." scores "..table.concat(scores,","))
local m2=botMatch(42)
check(m2.tick==m.tick and m2.winner==m.winner,"bot matches are deterministic")
-- Networking through a fake rednet hub: host plus two clients, then a dropout.
local net=require("lib.net")
local clock=0
local function now() return clock end
local hub={queue={},hosted={}}
local function endpoint(id)
  return {isOpen=function() return true end,open=function() end,
    host=function(p,n) hub.hosted[p]=id end,unhost=function(p) hub.hosted[p]=nil end,
    lookup=function(p) return hub.hosted[p] end,
    send=function(to,msg,proto) hub.queue[#hub.queue+1]={to=to,from=id,msg=textutils.unserialize(textutils.serialize(msg)),proto=proto} end}
end
local function find(kind,fn) fn("top",{}) end
local nodes={}
local function pump()
  while #hub.queue>0 do
    local m=table.remove(hub.queue,1)
    if nodes[m.to] then nodes[m.to]:handle(m.from,m.msg,m.proto) end
  end
end
local host=net.host({rn=endpoint(10),now=now,find=find,name="HOSTY",seed=9})
nodes[10]=host
check(host.online and hub.hosted[net.PROTOCOL]==10,"host advertises the protocol")
local c1=net.client({rn=endpoint(11),now=now,find=find,name="ALICE"});nodes[11]=c1
local c2=net.client({rn=endpoint(12),now=now,find=find,name="BOB",hostId=10});nodes[12]=c2
check(c1:join() and c1.hostId==10,"client finds host by lookup");c2:join();pump()
check(c1.mySeat==2 and c2.mySeat==3 and c1.phase=="lobby","clients get seats 2 and 3")
check(host.seats[2].kind=="R" and host.seats[4].kind=="B" and c2.names[2]=="ALICE","lobby lists seats")
host:start();pump()
check(c1.phase=="play" and c1.state and c1.state.players[2],"start reaches clients with a snapshot")
local y0=host.state.players[2].yaw
clock=clock+100;c1:tick(W.RIGHT);pump()
host:tick(0);pump()
check(host.state.players[2].yaw==(y0+W.TURN)%360,"client input turns its own seat")
check(host.state.players[3].yaw==c2.state.players[3].yaw and c2.state.tick==host.state.tick,"clients mirror host ticks")
-- c2 goes silent: after the timeout a bot plays seat 3, and c2 can rejoin.
for _=1,35 do clock=clock+100;c1:tick(0);pump();host:tick(0);pump() end
check(host.seats[3].kind=="B" and host.seats[2].kind=="R","silent client replaced by a bot")
check(not c2:tick(0) and c2.phase=="play","dropped client still hears recent snapshots")
clock=clock+net.TIMEOUT+1
check(c2:tick(0) and c2.phase=="lost","silent host is noticed by the client")
for _=1,5 do clock=clock+100;c1:tick(0);pump();host:tick(0);pump() end
c2:join();pump()
check(c2.mySeat==3 and host.seats[3].kind=="R" and c2.phase=="play","dropped client rejoins its seat mid-match")
c1:close();pump()
check(host.seats[2].kind=="B","leaving frees the seat for a bot")
local c3=net.client({rn=endpoint(13),now=now,find=find,name="CAROL",hostId=10});nodes[13]=c3
local c4=net.client({rn=endpoint(14),now=now,find=find,name="DAN",hostId=10});nodes[14]=c4
local c5=net.client({rn=endpoint(15),now=now,find=find,name="EVE",hostId=10});nodes[15]=c5
c3:join();c4:join();c5:join();pump()
check(c3.mySeat and c4.mySeat and c5.phase=="lost","a fifth player is turned away")
local solo=net.host({rn=endpoint(20),now=now,find=function() end})
check(not solo.online and solo.seats[2].kind=="B","no modem means solo against bots")
solo:start();for _=1,20 do solo:tick(W.FWD) end
check(solo.state.tick==20,"solo host steps locally")
-- Input: held keys make a mask; taps pulse.
local input=require("lib.input")
local inp=input.new()
check(inp:event({"key",keys.up,false})=="held" and inp:mask()==W.FWD,"holding up moves")
check(inp:event({"key",keys.w,false})==nil and inp:event({"key_up",keys.up})==nil and inp:mask()==W.FWD,"two keys for one action")
check(inp:event({"key_up",keys.w})=="held" and inp:mask()==0,"release stops")
check(inp:event({"key",keys.enter,false})=="start" and inp:event({"key",keys.enter,true})==nil,"enter starts, repeats ignored")
local ui=require("lib.ui")
local lay=ui.layout(51,19,{phase="play",role="host"})
local fire;for _,b in ipairs(lay.buttons) do if b.id=="fire" then fire=b end end
check(inp:event({"mouse_click",1,fire.x,fire.y},lay.buttons)=="held" and inp:mask()==W.FIRE,"fire button pulses")
inp:decay();check(inp:mask()==0,"pulse decays")
check(inp:event({"monitor_touch","other",fire.x,fire.y},lay.buttons,"mon")==nil,"foreign monitor ignored")
for _,size in ipairs({{39,19},{51,19},{82,40}}) do
  local l=ui.layout(size[1],size[2],{phase="play",role="host"})
  for _,b in ipairs(l.buttons) do check(b.x>=1 and b.x+b.w-1<=size[1] and b.y+b.h-1<=size[2],"button bounds") end
  check(l.scene.y+l.scene.h-1<l.buttons[1].y,"scene above buttons")
end
check(ui.layout(30,12).small,"tiny screen")
-- Render every phase into an offscreen window, and dump screens for review.
local render=require("lib.render")
local function dump(t,name)
  if not fs.exists("/results") then return end
  local w,h=t.getSize();local lines={};local pal={}
  for y=1,h do local text,fg,bg=t.getLine(y);lines[y]={text=text,fg=fg,bg=bg} end
  for i=0,15 do local r,g,b=t.getPaletteColor(2^i);pal[colors.toBlit(2^i)]=math.floor(r*255)*65536+math.floor(g*255)*256+math.floor(b*255) end
  local f=fs.open("/results/"..name..".json","w");f.write(textutils.serializeJSON({w=w,h=h,palette=pal,lines=lines}));f.close()
end
for _,size in ipairs({{39,19},{51,19},{82,40}}) do
  local old=term.current();local t=window.create(old,1,1,size[1],size[2],false)
  term.redirect(t)
  local painter=render.new(t)
  local h=net.host({rn=endpoint(30),now=now,find=find,name="HOSTY",seed=4})
  local v=h:view();painter:draw(v)
  check(t.getLine(5):find("I N E",1,true) or t.getLine(4):find("I N E",1,true),"lobby title at "..size[1])
  dump(t,"lobby-"..size[1])
  h:start()
  -- Walk the host Smiley a little so the view has company.
  for _=1,40 do h:tick(0) end
  h.state.players[1].x,h.state.players[1].z,h.state.players[1].yaw=2,6,0
  local count=painter:draw(h:view())
  check(count and count>10,"scene draws objects at "..size[1]..": "..tostring(count))
  check(t.getLine(1):find("YOU",1,true),"scoreboard at "..size[1])
  dump(t,"play-"..size[1])
  h.state.players[1].score=W.WIN;h.state.phase="over";h.state.winner=1;h.phase="over"
  painter:draw(h:view());check(t.getLine(4):find("YOU WIN",1,true),"results at "..size[1])
  dump(t,"over-"..size[1])
  painter:close();term.redirect(old)
end
-- A close-up: face another Smiley.
do
  local old=term.current();local t=window.create(old,1,1,51,19,false);term.redirect(t)
  local painter=render.new(t)
  local h=net.host({rn=endpoint(31),now=now,find=find,seed=4});h:start()
  local me,them=h.state.players[1],h.state.players[2]
  me.x,me.z,me.yaw=2,2,0;them.x,them.z,them.yaw,them.shield=4,2,180,0
  h.state.players[3].alive=false;h.state.players[4].alive=false
  painter:draw(h:view());dump(t,"faceoff-51")
  painter:close();term.redirect(old)
end
-- The real event loop: solo, hold forward, fire, open help, quit. Wall-clock timing.
do
  local App=require("lib.app")
  local old=term.current();local t=window.create(old,1,1,51,19,false)
  local palette={};for i=0,15 do palette[i]={t.getPaletteColor(2^i)} end
  local frames,final=0,nil
  local opts={terminal=true,solo=true,seed=3,record=function(kind) if kind=="frame" then frames=frames+1 end end}
  term.redirect(t)
  parallel.waitForAll(function() final=App.run(opts) end,function()
    sleep(.2);os.queueEvent("key",keys.enter,false)
    sleep(.3);os.queueEvent("key",keys.left,false)
    sleep(.5);os.queueEvent("key_up",keys.left);os.queueEvent("key",keys.space,false)
    sleep(.3);os.queueEvent("key_up",keys.space);os.queueEvent("key",keys.f1,false)
    sleep(.3);os.queueEvent("key",keys.q,false)
  end)
  term.redirect(old)
  local st=final.session.state
  check(st and st.tick>=10 and st.tick<=30,"real loop ran about 1.4 s of ticks: "..tostring(st and st.tick))
  check(st.players[1].yaw~=0 or st.players[1].x~=2,"held key steered the host Smiley")
  check(frames>=8,"frames drawn: "..frames)
  check(final.overlay=="help","help opened from the keyboard")
  for i=0,15 do
    local r,g,b=t.getPaletteColor(2^i)
    check(math.abs(r-palette[i][1])<1e-6 and math.abs(b-palette[i][3])<1e-6,"palette restored")
  end
end
print("bot match: "..m.tick.." ticks, "..shots.." shots, winner P"..m.winner.." scores "..table.concat(scores,","))
print("PASS Pine Face arena, movement, bullets, tags, respawn, snapshot, bot match, net, input, render, event loop")
return true
