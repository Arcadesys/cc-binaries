-- Table logic over an in-memory loopback with a fake clock. The real seat and host
-- objects run; only rednet and time are replaced. tables/tests/cluster.lua runs the
-- same code over real rednet between separate emulated computers.
local host=require('tables.host')
local seat=require('tables.seat')
local view=require('tables.view')
local bank=require('tables.bank')
local highcard=require('tables.games.highcard')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..': expected '..tostring(b)..', got '..tostring(a)) end
for _,f in ipairs({'net','view','bank','host','seat','app','games/highcard'}) do check(loadfile('/arcade/tables/'..f..'.lua'),'syntax '..f) end
check(loadfile('/arcade/tables.lua'),'syntax launcher')

-- A table with seat computers 11..14 and a controllable clock and shuffle.
local function rig(opts)
 opts=opts or {}
 local clock={t=1000}
 local r={clock=clock,seats={},cards={},offline={},sent=0}
 local wallet=opts.bank or bank.exhibition()
 r.bank=wallet
 local seed=opts.seed or 1
 local function rng(n) seed=(seed*1103515245+12345)%2147483648; return seed%n+1 end
 r.host=host.new({id=1,seats={11,12,13,14},game=opts.game or highcard,bank=wallet,now=function() return clock.t end,rng=rng,exhibition=opts.exhibition~=false,
  send=function(id,msg) r.sent=r.sent+1; if not r.offline[id] then r.seats[id-10]:receive(msg) end end})
 for i=1,4 do
  r.seats[i]=seat.new({table=1,now=function() return clock.t end,card=function() return r.cards[i] end,
   send=function(msg) if not r.offline[10+i] then r.host:receive(10+i,msg) end end})
 end
 -- One heartbeat from every connected seat, then advance time.
 function r.beat(dt)
  for i=1,4 do if not r.offline[10+i] then r.seats[i]:hello() end end
  clock.t=clock.t+(dt or 1); r.host:tick()
 end
 function r.wait(seconds) for _=1,seconds do r.beat() end end
 function r.buttons(i) local out={}; for _,b in ipairs(r.seats[i]:current().buttons or {}) do out[#out+1]=b.id end; return table.concat(out,',') end
 return r
end
local function has(log,line) for _,l in ipairs(log) do if l==line then return true end end return false end

-- Seats connect, see the lobby, and an unknown computer is ignored.
local r=rig()
check(not r.seats[1]:connected(),'Seat starts disconnected')
eq(r.seats[1]:current().status,'Connecting to table #1...','Offline seat view')
r.beat()
check(r.seats[1]:connected(),'Seat connected after hello')
eq(r.seats[1]:current().status,'Insert your house card','Empty seat prompt')
eq(r.buttons(1),'guest','Exhibition offers guest join')
r.host:receive(99,{t='hello'}); r.host:receive(99,{t='press',seq=1,button='guest'})
for i=1,4 do check(not r.host.seats[i].account,'Stranger cannot take a seat') end

-- Solo: one guest against the house starts immediately and pays by the house rule.
check(r.seats[1]:press('guest'),'Guest join pressed')
eq(r.buttons(1),'ready,leave','Guest can ready or leave')
check(r.seats[1]:press('ready'),'Ready pressed')
eq(r.host.phase,'PLAYING','Solo starts when everyone seated is ready')
check(has(r.host.log,'start 1'),'Only seat 1 plays')
eq(r.bank:balance('guest:11'),95,'Ante taken')
eq(r.buttons(1),'flip','Player sees flip')
eq(r.buttons(2),'','Unseated seat has no game buttons')
check(r.seats[1]:press('flip'),'Flip pressed')
eq(r.host.phase,'RESULT','Hand resolves')
local paid=r.host.round.payouts[1]
local s=r.host.state; local p=s.players[1]
eq(paid,p.card.rank>s.dealer.rank and 10 or p.card.rank==s.dealer.rank and 5 or 0,'House rule payout')
eq(r.bank:balance('guest:11'),95+paid,'Payout credited')
r.wait(host.RESULT)
eq(r.host.phase,'LOBBY','Result times out to lobby')
eq(r.buttons(1),'ready,leave','Ready resets after a hand')

-- A press for a button the seat is not offered (double tap, delayed packet) does nothing.
r.host:receive(11,{t='press',seq=0,button='unready'})
check(not r.host.seats[1].ready,'Unoffered unready ignored')
r.host:receive(11,{t='press',seq=0,button='flip'})
eq(r.host.phase,'LOBBY','Unoffered flip ignored in lobby')
check(has(r.host.log,'ignored 1 flip'),'Ignored press logged')

-- Three players with real cards: the pot is redistributed exactly.
r=rig({seed=7})
r.cards={{account='house-1',diskID=1},{account='house-2',diskID=2},{account='house-3',diskID=3}}
r.beat()
eq(r.buttons(1),'ready','Card holder gets ready, no guest button')
for i=1,3 do r.seats[i]:press('ready') end
eq(r.host.phase,'PLAYING','All seated ready starts the table')
check(has(r.host.log,'start 1,2,3'),'Three players')
-- Seat 2 presses against the view it had before seat 1 flipped (as over a real
-- network, where another player's move can land first); it must still count.
local before=r.seats[2].seq
r.seats[1]:press('flip')
check(r.seats[2].seq>before,'Seat 1 flipping changed seat 2 view')
r.host:receive(12,{t='press',seq=before,button='flip'})
check(has(r.host.log,'press 2 flip'),'Concurrent press not lost')
r.host:receive(12,{t='press',seq=before,button='flip'})
check(not has(r.host.log,'auto 2'),'Double flip harmless')
eq(r.host.phase,'PLAYING','Waits for every flip')
eq(r.seats[1]:current().status,'Waiting for other players','Flipped player waits')
-- A hidden card is not in another seat's view until it is flipped.
local seen=textutils.serialize(r.seats[1]:current().lines)
check(seen:find('Seat 3 house-3: ?? (hidden)',1,true),'Unflipped card hidden from other seats')
r.seats[3]:press('flip')
eq(r.host.phase,'RESULT','Resolves after all flips')
for i=1,3 do local st=r.seats[i]:current().status; check(st:find('^YOU WIN') or st=='No win this hand' or st:find('^PUSH'),'Result status '..st) end
local total=0; for i=1,3 do total=total+r.bank:balance('house-'..i) end
eq(total,300,'Player-vs-player conserves credits')

-- Countdown: a seated player who never readies is left out when it expires.
r=rig()
r.cards={{account='house-1',diskID=1},{account='house-2',diskID=2}}
r.beat(); r.seats[1]:press('ready')
eq(r.host.phase,'LOBBY','Waits for the second seated player')
check(r.seats[1]:current().status:match('^Starting in'),'Ready player sees countdown')
for _=1,host.COUNTDOWN do r.beat() end
eq(r.host.phase,'PLAYING','Countdown expires and deals')
check(has(r.host.log,'start 1'),'Unready seat sits out')
eq(r.seats[2]:current().status,'Game in progress. Next hand soon.','Spectating seat')

-- A seat that drops mid-hand is flipped automatically after the timeout.
r=rig()
r.cards={{account='house-1',diskID=1},{account='house-2',diskID=2}}
r.beat(); r.seats[1]:press('ready'); r.seats[2]:press('ready')
r.seats[1]:press('flip')
r.offline[12]=true
for _=1,require('tables.net').TIMEOUT do r.beat() end
eq(r.host.phase,'PLAYING','Not dropped inside the timeout')
r.beat()
check(has(r.host.log,'auto 2'),'Dropped seat auto-flips')
eq(r.host.phase,'RESULT','Hand completes without the dropped seat')
eq(r.bank:balance('house-1')+r.bank:balance('house-2'),200,'Dropped seat still paid')
eq(r.host:publicView().lines[1][1],'Pot: 10 credits','Public view shows the pot')

-- An idle (connected) player is flipped after IDLE seconds.
r=rig()
r.cards={{account='house-1',diskID=1}}
r.beat(); r.seats[1]:press('ready')
for _=1,host.IDLE do r.beat() end
eq(r.host.phase,'PLAYING','Not idle yet')
r.beat()
check(has(r.host.log,'auto 1'),'Idle player auto-flips')

-- Pulling the card mid-hand still pays the account that staked.
r=rig()
r.cards={{account='house-1',diskID=1}}
r.beat(); r.seats[1]:press('ready')
r.cards[1]={account='house-9',diskID=9}; r.beat(0)
r.seats[1]:press('flip')
eq(r.host.phase,'RESULT','Hand finishes')
eq(r.bank:balance('house-1'),95+r.host.round.payouts[1],'Winnings follow the staking account')
eq(r.bank:balance('house-9'),100,'New card untouched')

-- No credits, no seat in the hand.
local poor=bank.exhibition(); poor:stake('house-1',98)
r=rig({bank=poor})
r.cards={{account='house-1',diskID=1}}
r.beat(); r.seats[1]:press('ready')
eq(r.host.phase,'LOBBY','Cannot ante with 2 credits')
check(textutils.serialize(r.seats[1]:current().lines):find('Not enough credits'),'Seat told why')

-- A game that tries to pay more than its stakes is stopped before crediting anyone.
local greedy=setmetatable({payouts=function(s)
 if not highcard.payouts(s) then return nil end
 local o={}; for seat in pairs(s.players) do o[seat]=999 end; return o
end},{__index=highcard})
r=rig({game=greedy})
r.cards={{account='house-1',diskID=1},{account='house-2',diskID=2}}
r.beat(); r.seats[1]:press('ready'); r.seats[2]:press('ready')
r.seats[1]:press('flip')
local ok,err=pcall(function() r.seats[2]:press('flip') end)
check(not ok and tostring(err):find('exceeds limit'),'Overpayment rejected')
eq(r.bank:balance('house-1'),95,'Nothing credited on overpayment')

-- Without exhibition there is no guest seat.
r=rig({exhibition=false}); r.beat()
eq(r.buttons(1),'','No guest button at a house table')

-- Many hands at every table size conserve credits and pay within limits.
for players=1,4 do
 r=rig({seed=players*31})
 for i=1,players do r.cards[i]={account='house-'..i,diskID=i} end
 local houseNet=0
 for _=1,150 do
  r.beat(0)
  for i=1,players do r.seats[i]:press('ready') end
  eq(r.host.phase,'PLAYING','Deals '..players)
  for i=1,players do r.seats[i]:press('flip') end
  local paid=0; for _,v in pairs(r.host.round.payouts) do paid=paid+v end
  houseNet=houseNet+players*highcard.ante-paid
  if players>1 then eq(paid,players*highcard.ante,'Pot paid exactly') end
  r.wait(host.RESULT)
  -- keep everyone funded
  for i=1,players do if r.bank:balance('house-'..i)<highcard.ante then r.bank:pay('house-'..i,100) end end
 end
 if players>1 then eq(houseNet,0,'No house take at '..players) end
end

-- Rendering fits a standard terminal and a small monitor; touches hit buttons.
for _,size in ipairs({{51,19},{29,12},{18,10}}) do
 local win=window.create(term.current(),1,1,size[1],size[2],false)
 local v={title='T',status='S',lines={'a','b','c'},buttons={{id='x',label='X'},{id='y',label='Y'}}}
 view.draw(win,v)
 local boxes=view.layout(win,v)
 eq(view.hit(win,v,boxes[2].y).id,'y','Hit second button '..size[1])
 eq(view.hit(win,v,boxes[1].y+boxes[1].height-1).id,'x','Hit first button bottom row '..size[1])
 check(view.hit(win,v,1)==nil,'Title is not a button')
 check(boxes[2].y+boxes[2].height-1<=size[2]-1,'Buttons clear the footer '..size[1])
end
print('tables: '..passed..' assertions passed')
