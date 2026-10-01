-- Pine Jack checks: rules, reservations, and whole hands through the real event loop.
local rules=require('pinejack.rules')
local game=require('pinejack.game')
local wallets=require('casino.wallet')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local function cards(...) local out={}; for _,r in ipairs({...}) do out[#out+1]={rank=r,suit='S'} end; return out end
-- Rules.
eq(select(1,rules.total(cards('A','6'))),17,'Soft 17'); check(select(2,rules.total(cards('A','6'))),'Soft flag')
eq(select(1,rules.total(cards('A','6','K'))),17,'Hard 17 after ten'); eq(select(1,rules.total(cards('A','A','9'))),21,'Two aces')
check(not rules.dealerHits(cards('A','6')),'Dealer stands on soft 17'); check(rules.dealerHits(cards('10','6')),'Dealer hits 16')
eq(rules.handReturn({cards=cards('A','K'),stake=10},cards('10','9')),25,'Blackjack pays 3:2')
eq(rules.handReturn({cards=cards('A','K'),stake=10},cards('A','J')),10,'Blackjacks push')
eq(rules.handReturn({cards=cards('A','K'),stake=10,split=true},cards('10','9')),20,'Split 21 is not blackjack')
eq(rules.handReturn({cards=cards('10','9'),stake=10},cards('10','5','K')),20,'Dealer bust')
eq(rules.handReturn({cards=cards('10','5','K'),stake=10},cards('10','5','K')),0,'Player bust loses first')
eq(rules.maximum({{cards={},stake=10}}),25,'Opening reservation covers blackjack')
eq(rules.maximum({{cards=cards('8'),stake=10,split=true},{cards=cards('8'),stake=10,split=true}}),40,'Split reservation')
check(rules.canSplit({{}},{cards=cards('K','Q')}),'Ten-values split'); check(not rules.canSplit({{},{}},{cards=cards('8','8')}),'One split only')
for _,b in ipairs(rules.bets) do eq(b%2,0,'Even bets keep 3:2 whole') end
local shoe=rules.newShoe(function(lo,hi) return lo end); eq(#shoe.cards,312,'Six decks')
-- Whole hands. Deal order is player, dealer up, player, dealer hole, then draws.
local function stacked(list)
 return function()
  local s={cards={},next=1}
  for _,r in ipairs(list) do s.cards[#s.cards+1]={rank=r,suit='H'} end
  for _=#s.cards+1,312 do s.cards[#s.cards+1]={rank='2',suit='C'} end
  return s
 end
end
local function play(w,deck,steps)
 local now=0
 local log={}
 local opts={target=window.create(term.current(),1,1,51,19,false),wallet=w,newShoe=stacked(deck),
  clock=function() return now end,sound={play=function() end,tick=function() end},button=function(e,p) if e=='redstone' then return p end end}
 local co=coroutine.create(function() game.run(opts) end)
 local oldPull,oldTimer=os.pullEvent,os.startTimer
 os.pullEvent=function() return coroutine.yield() end; os.startTimer=function() return 1 end
 local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
 local function settle() for _=1,80 do now=now+.05; send('timer',1) end end
 send(); settle()
 for _,s in ipairs(steps) do
  if type(s)=='number' then send('key',({keys.one,keys.two,keys.three})[s])
  elseif s:match('^rs:') then send('redstone',s:sub(4))
  else send('key',keys[s]) end
  settle()
 end
 send('key',keys.q)
 os.pullEvent,os.startTimer=oldPull,oldTimer
 return coroutine.status(co)
end
local function spy()
 local w=wallets.exhibition('PINE JACK'); local calls={}
 local b,i,s=w.begin,w.increase,w.settle
 w.begin=function(self,stake,max) calls[#calls+1]={op='begin',stake=stake,max=max}; return b(self,stake,max) end
 w.increase=function(self,r,stake,max) calls[#calls+1]={op='increase',stake=stake,max=max}; return i(self,r,stake,max) end
 w.settle=function(self,r,amount) calls[#calls+1]={op='settle',amount=amount}; return s(self,r,amount) end
 return w,calls
end
-- Player blackjack against a nine.
local w,calls=spy()
eq(play(w,{'A','9','K','7'},{2}),'dead','Quit between hands')
eq(calls[1].stake,2,'Opening bet'); eq(calls[1].max,5,'Opening reservation'); eq(calls[2].amount,5,'Blackjack pays 3:2')
eq(w:session().balance,103,'Blackjack balance')
-- Dealer blackjack under an ace: peek, no decisions, player loses.
w,calls=spy(); play(w,{'10','A','9','K'},{2})
eq(#calls,2,'No decisions against dealer blackjack'); eq(calls[2].amount,0,'Dealer blackjack wins'); eq(w:session().balance,98,'Lost stake')
-- Hit and bust via the physical buttons; the dealer does not draw.
w,calls=spy(); play(w,{'10','6','6','10','K','5'},{'rs:CENTER','rs:LEFT'})
eq(calls[2].amount,0,'Bust settles zero'); eq(w:session().balance,98,'Bust balance')
-- Raise the bet to 4, double 11 into 21; dealer 16 draws to 25.
w,calls=spy(); play(w,{'6','6','5','10','10','9'},{1,2,3})
eq(calls[1].stake,4,'Bet button raises to 4'); eq(calls[2].op,'increase','Double raises the stake')
eq(calls[2].stake,4,'Double adds the stake'); eq(calls[2].max,16,'Double reserves the doubled win')
eq(calls[3].amount,16,'Doubled win'); eq(w:session().balance,108,'Double balance')
-- Split eights through MORE, double the first hand after the split, stand the second.
w,calls=spy(); play(w,{'8','6','8','10','3','K','10','9'},{2,3,2,3,2})
eq(calls[2].op,'increase','Split raises the stake'); eq(calls[2].max,8,'Split reservation')
eq(calls[3].op,'increase','Double after split'); eq(calls[3].max,12,'Double after split reservation')
eq(calls[4].amount,12,'Both split hands win'); eq(w:session().balance,106,'Split balance')
-- Split aces take one card each and stand.
w,calls=spy(); play(w,{'A','9','A','8','K','J'},{2,3,2})
eq(calls[#calls].op,'settle','Split aces settle without decisions'); eq(calls[#calls].amount,8,'Two split-ace 21s pay even money')
-- House offline at settlement: the table holds until RETRY succeeds.
w,calls=spy(); local failures=1
local s=w.settle; w.settle=function(self,r,a) if failures>0 then failures=failures-1; return false,'offline' end return s(self,r,a) end
local retried=0; w.retry=function() retried=retried+1; s(w,{},5); return true end
eq(play(w,{'A','9','K','7'},{2,1}),'dead','Recovers after retry'); eq(retried,1,'Retry pressed once'); eq(w:session().balance,103,'Paid once')
print('PASS '..passed..' Pine Jack assertions')
