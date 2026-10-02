-- Race-day sound: countdown, start, hoofbeats, finishers, result and betting feedback.
local sfx=require('derby.sfx')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function recorder()
 local r={notes={},ticks=0}
 function r:play(at,instrument,volume,pitch) self.notes[#self.notes+1]={at=at,i=instrument,v=volume,p=pitch} end
 function r:tick() self.ticks=self.ticks+1 end
 function r:count(instrument,pitch) local n=0; for _,x in ipairs(self.notes) do if x.i==instrument and (not pitch or x.p==pitch) then n=n+1 end end; return n end
 return r
end
local INSTRUMENTS={harp=1,basedrum=1,snare=1,hat=1,bass=1,flute=1,bell=1,guitar=1,chime=1,xylophone=1,iron_xylophone=1,cow_bell=1,didgeridoo=1,bit=1,banjo=1,pling=1}

-- Joining mid-race is silent: no start gun or fanfare for a change that was never seen.
local r=recorder(); local s=sfx.new(r)
s:hear({phase='RUNNING',order={},positions={0,0,0}},0)
check(r:count('bell')==0 and r:count('snare')==0,'Mid-race join is quiet')
check(r:count('basedrum')==1,'A race already underway still gallops')

-- A full race: countdown ticks, the gun, hoofbeats, three finishers, the fanfare.
r=recorder(); s=sfx.new(r)
local t=0
for seconds=5,1,-1 do
 s:hear({phase='LOCKED',seconds=seconds,order={}},t); s:hear({phase='LOCKED',seconds=seconds,order={}},t+50); t=t+1000
end
check(r:count('hat')==2 and r:count('pling')==3,'One tick per second, rising for the last three: '..r:count('hat')..'/'..r:count('pling'))
local before=#r.notes
s:hear({phase='RUNNING',order={}},t)
check(r:count('snare')==1 and r:count('bell')==4,'Start gun')
for k=1,10 do t=t+100; s:hear({phase='RUNNING',order={}},t) end
local beats=r:count('basedrum')-1
check(beats>=2 and beats<=3,'Hoofbeats gallop about every 450 ms, got '..beats)
t=t+100; s:hear({phase='RUNNING',order={2}},t); s:hear({phase='RUNNING',order={2}},t+10)
check(r:count('bell',24)==2,'First finisher rings once (plus the gun) ')
t=t+100; s:hear({phase='RUNNING',order={2,1}},t); s:hear({phase='RUNNING',order={2,1,3}},t+10)
check(r:count('bell',19)>=2 and r:count('bell',14)==1,'Second and third finishers')
local before=r:count('bell')
t=t+100; s:hear({phase='RESULT',order={2,1,3}},t)
check(r:count('bell')==before+6 and r:count('chime',24)==1,'Result fanfare')
local n=#r.notes; s:hear({phase='RESULT',order={2,1,3}},t+500); check(#r.notes==n,'RESULT sounds once')
check(r.ticks>20,'Every frame drains the queue')

-- A cancelled race buzzes; the betting station has its own two cues.
r=recorder(); s=sfx.new(r)
s:hear({phase='CANCELLED'},0); check(r:count('bass')==3,'Cancelled race buzzer')
r=recorder(); s=sfx.new(r)
s:move(0); check(r:count('hat',20)==1,'Station focus tick')
s:ticket(true,0); check(r:count('bell')==3,'Ticket accepted')
s:ticket(false,0); check(r:count('bass')==2,'Ticket refused')
for _,x in ipairs(r.notes) do check(INSTRUMENTS[x.i] and x.v>0 and x.v<=3 and x.p>=0 and x.p<=24,'Playable note '..x.i..':'..x.p) end

-- The real queue in casino.sound holds notes until their time.
local played={}
local oldFind=peripheral.find
peripheral.find=function(kind) if kind=='speaker' then return {playNote=function(i,v,p) played[#played+1]=i..':'..p end} end return oldFind(kind) end
local real=sfx.new(); peripheral.find=oldFind
real:ticket(true,1000)
check(#played==1 and played[1]=='bell:12','Only the first note is due at once')
real:tick(1250); check(#played==3,'The rest follow on schedule')
print('PASS race sound ('..passed..' checks)')
return true
