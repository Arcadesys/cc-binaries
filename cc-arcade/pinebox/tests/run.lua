-- Pine Shut the Box checks: rules, odds, and whole rounds through the real event loop.
local rules=require('pinebox.rules')
local game=require('pinebox.game')
local wallets=require('casino.wallet')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local function mask(...) local m=0; for _,n in ipairs({...}) do m=m+2^(n-1) end; return m end
-- Rules and the exact solver.
eq(rules.sum(rules.full),45,'Board total')
eq(#rules.moves(rules.full,7),5,'Ways to make 7 on a full board')
eq(rules.moves(rules.full,7)[1],mask(7),'Single tile listed first')
eq(#rules.moves(mask(1,2),12),0,'Dead roll'); eq(#rules.moves(mask(2),2),1,'One way')
check(math.abs(rules.chance(rules.full)-.0714316)<1e-5,'Best-play clear chance '..rules.chance(rules.full))
check(rules.prize*rules.chance(rules.full)<1,'Grand prize keeps a house edge')
eq(rules.chance(0),1,'Empty board is won'); eq(rules.chance(mask(1)),0,'A lone 1 can never be rolled')
for roll=2,12 do local b=rules.best(rules.full,roll); check(b and rules.sum(b)==roll,'Best move makes the roll') end
-- Whole rounds. Dice values come from a queue; physics randomness from a fixed LCG.
local function play(w,values,steps,inspect)
 local now=0; local seed=99
 local t=window.create(term.current(),1,1,51,19,false)
 local opts={target=t,wallet=w,clock=function() return now end,sound={play=function() end,tick=function() end},
  button=function(e,p) if e=='redstone' then return p end end,
  random=function(lo,hi)
   if lo==1 and hi==6 then return assert(table.remove(values,1),'Ran out of dice values') end
   seed=(seed*1103515245+12345)%2147483648; return lo+seed%(hi-lo+1)
  end}
 local co=coroutine.create(function() game.run(opts) end)
 local oldPull,oldTimer=os.pullEvent,os.startTimer
 os.pullEvent=function() return coroutine.yield() end; os.startTimer=function() return 1 end
 local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
 local function settle() for _=1,180 do now=now+.05; send('timer',1) end end
 send(); settle()
 for _,s in ipairs(steps) do
  if type(s)=='function' then s(t)
  elseif type(s)=='table' then send('key',keys[s.key]); for _=1,s.time*20 do now=now+.05; send('timer',1); s.watch(t) end
  elseif type(s)=='number' then send('key',({keys.one,keys.two,keys.three})[s]); settle()
  elseif s=='wait' then settle()
  elseif s:match('^rs:') then send('redstone',s:sub(4)); settle()
  else send('key',keys[s]); settle() end
 end
 send('key',keys.q)
 os.pullEvent,os.startTimer=oldPull,oldTimer
 return coroutine.status(co)
end
local function spy()
 local w=wallets.exhibition('PINE SHUT THE BOX'); local calls={}
 local b,s=w.begin,w.settle
 w.begin=function(self,stake,max) calls[#calls+1]={op='begin',stake=stake,max=max}; return b(self,stake,max) end
 w.settle=function(self,r,amount) calls[#calls+1]={op='settle',amount=amount}; return s(self,r,amount) end
 return w,calls
end
local function row(t,y) return (t.getLine(y)) end
-- Grand prize: pick rolls that keep the board clearable while always taking the best move.
-- PLAY opens the seat screen; FEWER drops the default two players to one, CENTER starts.
local board,values,steps=rules.full,{},{2,1,2}
while board>0 do
 local pick,top
 for total=2,12 do
  local b=rules.best(board,total)
  if b then local after=bit32.band(board,bit32.bnot(b)); local c=rules.chance(after)
   if not top or c>top then pick,top=total,c end end
 end
 values[#values+1]=math.max(1,pick-6); values[#values+1]=pick-math.max(1,pick-6)
 board=bit32.band(board,bit32.bnot(rules.best(board,pick)))
 steps[#steps+1]='rs:CENTER'; steps[#steps+1]=2
end
local w,calls=spy()
eq(play(w,values,steps),'dead','Quits between rounds')
eq(calls[1].max,13,'Reserves the grand prize'); eq(calls[2].amount,13,'Grand prize paid'); eq(w:session().balance,112,'Grand prize balance')
-- Dead roll: 1+1 takes the 2, then 1+1 again has no tiles left to make it.
w,calls=spy()
play(w,{1,1,1,1},{'space','left','space','space','space','space'})
eq(#calls,2,'One round'); eq(calls[2].amount,0,'Dead roll loses'); eq(w:session().balance,99,'Stake lost')
-- OTHER steps to another way of making 7, and TAKE removes exactly those tiles.
local moves=rules.moves(rules.full,7); local best=rules.best(rules.full,7)
local at; for i,m in ipairs(moves) do if m==best then at=i end end
local other=moves[at%#moves+1]
local seen
w,calls=spy()
play(w,{3,4,6,6},{1,2,1,2,2,3,2,function(t) seen=row(t,17) end})
eq(calls[1].stake,2,'BET raised the stake to 2')
local expect={}; for n=1,9 do expect[n]=rules.has(other,n) and '.' or tostring(n) end
check(seen:find('BOARD '..table.concat(expect,' '),1,true),'Board after taking the other move: '..seen)
-- Matches play for a pot. A fake house with two cards: tests swap the card in the drive.
local function house()
 local cards={ann={name='Ann',account='ann',balance=50},bo={name='Bo',account='bo',balance=50}}
 local w={mode='live',title='T',cards=cards,want=cards.ann,log={}}
 function w:refresh() if self.want~=self.current then self.current=self.want; return true end return false end
 function w:session() return self.current end
 function w:begin(stake,max)
  local c=self.current; c.balance=c.balance-stake
  self.log[#self.log+1]='begin '..c.account..' '..stake..'/'..max
  return {account=c.account,stake=stake}
 end
 function w:increase(r,stake,max) cards[r.account].balance=cards[r.account].balance-stake; r.stake=r.stake+stake; self.log[#self.log+1]='increase '..r.account; return true end
 function w:settle(r,amount) cards[r.account].balance=cards[r.account].balance+amount; self.log[#self.log+1]='settle '..r.account..' '..amount; return true end
 function w:refund(r) cards[r.account].balance=cards[r.account].balance+r.stake; self.log[#self.log+1]='refund '..r.account; return true end
 function w:retry() return true end
 return w
end
local function swap(w,name) return function() w.want=w.cards[name] end end
-- Ann antes, Bo antes, Ann dies on 43, Bo takes the best 3 and scores lower: Bo takes 2.
local after=bit32.band(rules.full,bit32.bnot(rules.best(rules.full,3)))
local p2=45-rules.sum(rules.best(rules.full,3))
w=house()
values={1,1,1,1,1,2,1,1}
steps={'space','space','space',swap(w,'bo'),'wait','space','space','space','space','space','space','space'}
if rules.has(after,2) then values[#values+1]=1; values[#values+1]=1; steps[#steps+1]='space'; steps[#steps+1]='space'; p2=p2-2 end
local banner,scores
steps[#steps]={key='space',time=12,watch=function(t) if row(t,18):find('WINS WITH',1,true) then banner=row(t,18); scores=row(t,17) end end}
play(w,values,steps)
check(banner and banner:find('BO WINS WITH '..p2..': +2',1,true),'Winner banner: '..tostring(banner))
check(scores:find('P1 43',1,true) and scores:find('P2 '..p2,1,true),'Scoreboard: '..scores)
eq(table.concat(w.log,','),'begin ann 1/2,begin bo 1/2,settle ann 0,settle bo 2','Antes reserve the pot; the winner is paid it')
eq(w.cards.ann.balance,49,'Loser pays the ante'); eq(w.cards.bo.balance,51,'Winner takes the pot')
-- Same rolls for both: a tie splits the pot. Shared card: two seats, one round.
w=house()
banner=nil
play(w,{1,1,1,1,1,1,1,1},{'space','space','space','space','space','space','space','space','space',
 {key='space',time=12,watch=function(t) if row(t,18):find('TIE',1,true) then banner=row(t,18) end end}})
check(banner and banner:find('TIE AT 43: PLAYER 1 & PLAYER 2 SPLIT 2',1,true),'Tie banner: '..tostring(banner))
eq(table.concat(w.log,','),'begin ann 1/2,increase ann,settle ann 2','One card, one round')
eq(w.cards.ann.balance,50,'Shared card breaks even on a tie')
-- Cancel after one ante: it comes back.
w=house()
play(w,{},{'space','space','space','left'})
eq(table.concat(w.log,','),'begin ann 1/2,refund ann','Cancel refunds the ante'); eq(w.cards.ann.balance,50,'Ante returned')
print('PASS '..passed..' Pine Shut the Box assertions')
