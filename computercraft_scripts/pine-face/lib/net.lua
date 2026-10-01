-- Sessions over rednet protocol pine-face-v1. The host owns the only world and steps it;
-- clients send held-key masks and draw the host's snapshots. Seat 1 is always the host.
-- `rn` is the rednet API (or a test double) and `now` returns milliseconds.
local world=require("lib.world")
local bot=require("lib.bot")
local net={PROTOCOL="pine-face-v1",TIMEOUT=3000,KEEPALIVE=500}
local function openModems(rn,find)
  local any=false
  if not rn then return false end
  find("modem",function(name)
    if not rn.isOpen(name) then pcall(rn.open,name) end
    any=any or rn.isOpen(name)
  end)
  return any
end
net.openModems=openModems
local function defaultFind(kind,fn) if peripheral then peripheral.find(kind,fn) end end

local Host={};Host.__index=Host
-- opts: rn, now, find, name, seed, solo
function net.host(opts)
  opts=opts or {}
  local self=setmetatable({rn=opts.rn,now=opts.now or function() return os.epoch("utc") end,
    phase="lobby",seed=opts.seed or 1,seats={},message="",role="host",mySeat=1},Host)
  self.seats[1]={kind="H",name=opts.name or "HOST",isLocal=true}
  for i=2,world.SEATS do self.seats[i]={kind="B",name="BOT"} end
  if not opts.solo and self.rn and openModems(self.rn,opts.find or defaultFind) then
    self.online=true
    pcall(self.rn.host,net.PROTOCOL,opts.hostname or ("pineface-"..(os.getComputerID and os.getComputerID() or 0)))
  end
  self.message=self.online and "ENTER starts. Open seats play as bots."
    or "No modem: you vs 3 bots. ENTER starts."
  return self
end
function Host:names()
  local n,k={},{}
  for i,s in ipairs(self.seats) do n[i]=s.name;k[i]=s.kind end
  return n,table.concat(k)
end
function Host:send(id,msg) if self.online then self.rn.send(id,msg,net.PROTOCOL) end end
function Host:remotes()
  local out={}
  for i,s in ipairs(self.seats) do if s.kind=="R" then out[#out+1]={seat=i,id=s.id} end end
  return out
end
function Host:lobbyMsg()
  local n,k=self:names()
  return {t="lobby",n=n,k=k,ph=self.phase}
end
function Host:announce(msg)
  for _,r in ipairs(self:remotes()) do self:send(r.id,msg) end
end
local function seatFor(self,id)
  for i,s in ipairs(self.seats) do if s.id==id then return i,s end end
end
function Host:handle(sender,msg,protocol)
  if protocol~=net.PROTOCOL or type(msg)~="table" then return false end
  local now=self.now()
  if msg.t=="join" then
    local seat,s=seatFor(self,sender)
    -- A computer that dropped gets its old seat back (seatFor matches the kept id);
    -- otherwise take a bot seat, preferring one nobody has dropped from.
    for pass=1,2 do
      for i,v in ipairs(self.seats) do
        if not seat and v.kind=="B" and (pass==2 or not v.id) then seat,s=i,v end
      end
    end
    if not seat then self:send(sender,{t="full"});return true end
    s.kind="R";s.id=sender;s.name=tostring(msg.name or ("PC"..sender)):sub(1,8);s.mask=0;s.last=now
    s.bot=nil
    self.message=s.name.." joined as P"..seat.."."
    self:send(sender,{t="seat",seat=seat})
    self:announce(self:lobbyMsg())
    if self.phase~="lobby" then self:send(sender,{t="start"}) end
    return true
  end
  local seat,s=seatFor(self,sender)
  if not seat or s.kind~="R" then return false end
  s.last=now
  if msg.t=="in" then s.mask=tonumber(msg.mask) or 0
  elseif msg.t=="leave" then self:drop(seat,s.name.." left; a bot takes P"..seat..".") end
  return true
end
function Host:drop(seat,message)
  local s=self.seats[seat]
  s.kind="B";s.mask=0;s.name="BOT";s.bot=nil -- keep s.id so that computer can rejoin
  self.message=message
  self:announce(self:lobbyMsg())
end
function Host:checkTimeouts()
  local now=self.now()
  for i,s in ipairs(self.seats) do
    if s.kind=="R" and now-s.last>net.TIMEOUT then self:drop(i,"P"..i.." timed out; a bot takes over.") end
  end
end
function Host:start()
  self.seed=self.seed+1
  self.state=world.new(self.seed)
  for i,s in ipairs(self.seats) do s.bot=nil;s.mask=0 end
  self.phase="play";self.message=""
  self:announce({t="start"})
  self:broadcastSnap()
end
function Host:broadcastSnap()
  local n,k=self:names()
  self.snap=world.snapshot(self.state,n,k)
  for _,r in ipairs(self:remotes()) do self:send(r.id,{t="snap",s=self.snap}) end
end
-- One fixed tick. localMask is the host keyboard's held keys.
function Host:tick(localMask)
  self:checkTimeouts()
  if self.phase~="play" then
    -- Keep clients from timing out while nobody is playing.
    local now=self.now()
    if now-(self.lastLobby or 0)>=1000 then
      self.lastLobby=now
      self:announce(self:lobbyMsg())
      if self.snap then for _,r in ipairs(self:remotes()) do self:send(r.id,{t="snap",s=self.snap}) end end
    end
    return false
  end
  local inputs={}
  for i,s in ipairs(self.seats) do
    if s.isLocal then inputs[i]=localMask or 0
    elseif s.kind=="R" then inputs[i]=s.mask or 0
    else
      s.bot=s.bot or bot.new(self.seed*10+i)
      inputs[i]=s.bot:input(self.state,i)
    end
  end
  world.step(self.state,inputs)
  if self.state.phase=="over" then self.phase="over" end
  self:broadcastSnap()
  return true
end
function Host:view()
  local n,k=self:names()
  return {role="host",phase=self.phase,state=self.state,mySeat=1,names=n,kinds=k,
    message=self.message,online=self.online}
end
function Host:close()
  if self.online then
    self:announce({t="end"})
    pcall(self.rn.unhost,net.PROTOCOL)
  end
end

local Client={};Client.__index=Client
-- opts: rn, now, find, name, hostId
function net.client(opts)
  opts=opts or {}
  local self=setmetatable({rn=opts.rn,now=opts.now or function() return os.epoch("utc") end,
    name=opts.name or "PLAYER",hostId=opts.hostId,phase="joining",role="client",mask=0,
    lastSent=0,lastHeard=0,message="Looking for a Pine Face host..."},Client)
  self.online=self.rn and openModems(self.rn,opts.find or defaultFind)
  if not self.online then self.phase="lost";self.message="No modem attached." end
  return self
end
function Client:join()
  if not self.online then return false end
  if not self.hostId then
    local ok,id=pcall(self.rn.lookup,net.PROTOCOL)
    self.hostId=ok and id or nil
  end
  if not self.hostId then self.phase="lost";self.message="No Pine Face host found. R retries.";return false end
  self.phase="joining";self.message="Joining host #"..self.hostId.."..."
  self.lastHeard=self.now()
  self.rn.send(self.hostId,{t="join",name=self.name},net.PROTOCOL)
  return true
end
function Client:handle(sender,msg,protocol)
  if protocol~=net.PROTOCOL or sender~=self.hostId or type(msg)~="table" then return false end
  self.lastHeard=self.now()
  if msg.t=="seat" then self.mySeat=msg.seat;if self.phase=="joining" then self.phase="lobby" end
    self.message="You are P"..msg.seat..". Waiting for the host to start."
  elseif msg.t=="lobby" then self.names=msg.n;self.kinds=msg.k
  elseif msg.t=="full" then self.phase="lost";self.message="That game is full."
  elseif msg.t=="start" then self.phase="play";self.message=""
  elseif msg.t=="end" then self.phase="lost";self.message="The host closed the game."
  elseif msg.t=="snap" and type(msg.s)=="table" then
    self.snap=msg.s;self.state=world.fromSnapshot(msg.s,self.state)
    self.names=msg.s.n or self.names;self.kinds=msg.s.k or self.kinds
    if self.phase~="lost" then self.phase=msg.s.ph=="over" and "over" or "play" end
    return "snap"
  end
  return true
end
-- Send the held-key mask when it changes, and a keepalive otherwise.
function Client:tick(mask)
  if not self.online or not self.hostId or self.phase=="lost" then return false end
  local now=self.now()
  if now-self.lastHeard>net.TIMEOUT then
    self.phase="lost";self.message="Lost the host. R rejoins.";return true
  end
  if mask~=self.mask or now-self.lastSent>=net.KEEPALIVE then
    self.mask=mask;self.lastSent=now
    self.rn.send(self.hostId,{t="in",mask=mask},net.PROTOCOL)
  end
  return false
end
function Client:view()
  return {role="client",phase=self.phase,state=self.state,mySeat=self.mySeat,names=self.names or {},
    kinds=self.kinds or "",message=self.message,online=self.online,hostId=self.hostId}
end
function Client:close()
  if self.online and self.hostId and self.phase~="lost" then
    pcall(self.rn.send,self.hostId,{t="leave"},net.PROTOCOL)
  end
end
return net
