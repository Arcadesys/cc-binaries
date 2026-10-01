-- Pine Slots checks: paytable math, reel landing, controls, wallets and the real event loop.
local reels=require('pineslots.reels')
local machine=require('pineslots.machine')
local controls=require('pineslots.controls')
local wallets=require('casino.wallet')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..' expected '..tostring(b)..', got '..tostring(a)) end
-- Math: exact return, hit rate and per-bet house reservations.
local stats=reels.stats()
check(stats.rtp>.9 and stats.rtp<.97,'Return per credit '..stats.rtp)
check(stats.hit>.2,'Hit rate '..stats.hit)
for b,v in ipairs({200,203,204,205,206}) do eq(reels.maxReturn(b),v,'Maximum return for bet '..b) end
for _,s in ipairs(reels.strips) do eq(#s,reels.size,'Strip length') end
eq(reels.linePay('D','D','D'),200,'Three diamonds'); eq(reels.linePay('C','C','P'),3,'Two cherries')
eq(reels.linePay('C','P','C'),1,'One leading cherry'); eq(reels.linePay('P','C','C'),0,'Cherries must lead')
-- Find a stop combination with a centre-line seven and check only lit lines pay.
local function find(reel,sym) for k=0,reels.size-1 do if reels.symbol(reel,k)==sym then return k end end end
local sevens={find(1,'S'),find(2,'S'),find(3,'S')}
local total,wins=reels.evaluate(sevens,1); eq(total,80,'Centre sevens'); eq(wins[1].line,1,'Centre line')
-- Diagonal down: top-left, centre, bottom-right.
local diag={find(1,'D')+1,find(2,'D'),find(3,'D')-1}
eq(select(1,reels.evaluate(diag,4))-select(1,reels.evaluate(diag,3)),200,'Diagonal pays only once lit at bet 4')
-- Reel landing: each reel ends exactly on its stop, moving downward the whole way.
for _,case in ipairs({{0,7},{3.4,0},{15.9,15},{-30,2}}) do
 local p=machine.plan(case[1],case[2],1.5)
 eq(p.final%reels.size,case[2],'Lands on target'); eq(machine.position(p,10),p.final,'Rests on final stop')
 local last=math.huge
 for n=0,150 do local x=machine.position(p,n/100); check(x<=last+1e-9,'Reel never runs backward before the stop'); last=x end
 check(p.speed>=machine.speed,'Never slower than spin speed')
end
-- Controls: rising edges only; a lever left on does not fire again.
local level={right=true}
local c=controls.new({arm='right',bet='left',max='top',cash='back'},function(s) return level[s]==true end)
eq(#c:poll(),0,'Lever already on at boot does not spin')
level.right=false; c:poll(); level.right=true; level.left=true
local fired=c:poll(); eq(#fired,2,'Arm and bet edges'); eq(fired[1],'arm','Arm first')
eq(#c:poll(),0,'Held inputs do not repeat')
eq(controls.read('none'),false,'Unwired control reads off')
-- Live wallet over a fake credits module: lock, reserve, settle after card removal, cash out.
local calls={}; local inserted={path='disk',drive='drive_0',account='house-1'}
local fake={}
function fake.lock(p) calls[#calls+1]='lock' end
function fake.unlock(p) calls[#calls+1]='unlock' end
function fake.getName() return 'Ada' end
function fake.get() return 50 end
function fake.beginRound(game,stake,maximum,path) calls[#calls+1]={op='reserve',game=game,stake=stake,maximum=maximum}; return {account='house-1',round='r1',maximum=maximum} end
local failSettle=false
function fake.settleRound(round,amount) if failSettle then error('HOUSE: offline',0) end calls[#calls+1]={op='settle',amount=amount}; return 50-5+amount end
function fake.retry() return true,{ok=true,balance=99} end
local ejected
local oldDisk=disk; disk=setmetatable({eject=function(d) ejected=d end},{__index=oldDisk})
local live=wallets.live('pineslots','PINE SLOTS',fake,function() return inserted end)
check(live:refresh(),'Card detected'); eq(live:session().balance,50,'Balance read'); eq(live:session().name,'Ada','Name read')
local round=live:begin(5,reels.maxReturn(5)); eq(calls[2].maximum,206,'Reserves largest return'); eq(live:session().balance,45,'Stake deducted')
inserted=nil; live:refresh(); check(not live:session(),'Card removed')
local ok,bal=live:settle(round,12); check(ok and bal==57,'Settles against the round account after card removal')
inserted={path='disk',drive='drive_0',account='house-1'}; live:refresh()
eq(live:cashout(),50,'Cash out reports balance'); eq(ejected,'drive_0','Card ejected')
check(not live:refresh() and not live:session(),'Ejecting card is not re-read')
inserted=nil; live:refresh(); inserted={path='disk',drive='drive_0'}; live:refresh()
check(live.problem and not live:session(),'Non-house disk rejected')
disk=oldDisk
-- The real event loop, driven by fake time, inputs and a recording wallet.
local function harness(w,events,seq)
 local now=0; local level={}
 local sound={play=function() end,tick=function() end}
 local rolls=seq or {}
 local opts={target=window.create(term.current(),1,1,51,19,false),wallet=w,sound=sound,
  clock=function() return now end,random=function(lo) return table.remove(rolls,1) or lo end,
  controls=controls.new({arm='right',bet='left',max='top',cash='back'},function(s) return level[s]==true end)}
 local co=coroutine.create(function() machine.run(opts) end)
 local oldPull,oldTimer=os.pullEvent,os.startTimer
 os.pullEvent=function() return coroutine.yield() end; os.startTimer=function() return 1 end
 local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
 local function tick(dt) now=now+(dt or .05); send('timer',1) end
 local function press(name,side) level[side]=true; send('redstone'); level[side]=false; send('redstone') end
 send()
 local api={tick=tick,press=press,send=send,co=co,now=function() return now end}
 events(api)
 os.pullEvent,os.startTimer=oldPull,oldTimer
 return api
end
local ex=wallets.exhibition()
local beginCalls={}; local orig=ex.begin
ex.begin=function(self,stake,maximum) beginCalls[#beginCalls+1]={stake=stake,maximum=maximum}; return orig(self,stake,maximum) end
-- Max bet, pull, and a forced centre-line seven combination.
harness(ex,function(h)
 h.tick(); h.press('max','top'); h.press('arm','right')
 eq(#beginCalls,1,'Arm spins once'); eq(beginCalls[1].stake,5,'Max bet stake'); eq(beginCalls[1].maximum,206,'Max bet reservation')
 h.press('arm','right'); eq(#beginCalls,1,'Arm ignored while reels spin')
 for _=1,60 do h.tick() end
 h.press('bet','left'); eq(ex:session().balance>=0,true,'Meter valid')
 h.press('arm','right'); eq(beginCalls[2].stake,1,'Bet one wraps from max to one')
 for _=1,60 do h.tick() end
 h.send('key',keys.q); check(coroutine.status(h.co)=='dead','Q exits when idle')
end,{sevens[1],sevens[2],sevens[3]})
check(select(1,reels.evaluate(sevens,5))>=80,'Sevens include the centre line')
eq(ex:session().balance,100-5+reels.evaluate(sevens,5)-1+reels.evaluate({0,0,0},1),'Meter follows both spins exactly')
-- Touch the bottom bar and the reel window.
local ex2=wallets.exhibition()
harness(ex2,function(h)
 h.tick(); h.send('monitor_touch','top',45,19); eq(ex2:session().balance,100,'Cash out resets practice meter')
 h.send('mouse_click',1,25,19); h.send('mouse_click',1,25,8)
 for _=1,60 do h.tick() end
 eq(ex2:session().balance,95+reels.evaluate({0,0,0},5),'Touch: max bet then spin on the reels')
 h.send('key',keys.q)
end,{0,0,0})
-- House offline at settlement: hold, retry on the next pull, cash out refused meanwhile.
failSettle=true
local w=wallets.live('pineslots','PINE SLOTS',fake,function() return {path='disk',drive='drive_0',account='house-1'} end)
harness(w,function(h)
 h.tick(); h.press('arm','right')
 for _=1,60 do h.tick() end
 local cashBefore=ejected; h.press('cash','back'); eq(ejected,cashBefore,'No cash out with a payout pending')
 failSettle=false; h.press('arm','right')
 eq(w:session().balance,99,'Retry confirms payout'); h.send('key',keys.q)
end,{0,0,0})
print('PASS '..passed..' Pine Slots assertions')
