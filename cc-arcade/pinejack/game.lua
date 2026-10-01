-- Pine Jack: the table loop. The round is a script (a coroutine) that deals, asks for
-- decisions and waits on animations; the event loop animates, reads the three cabinet
-- buttons and resumes the script. The house reserves the stake plus the largest possible
-- return on DEAL, is raised on double or split, and settles once when the hand ends.
local rules=require('pinejack.rules')
local scene=require('pinejack.scene')
local renderer=require('pinejack.render')
local M={}
M.dealTime=.42
M.tray={4.8,.4,0}
M.discard={3.6,.3,-6.5}
local function lerp(a,b,u) return a+(b-a)*u end
-- Actors are cards and chip stacks gliding between table positions.
local function actors(clock)
 local list={}; local api={list=list}; local n=0
 function api:add(a) n=n+1; a.id=a.id or ('a'..n); list[#list+1]=a; return a end
 -- Move to (x,y,z) with face rotation rx, starting after delay, over dur, lifted by arc.
 function api:move(a,to,dur,delay,arc)
  local now=clock(); local x,y,z,rx=api.pose(a,now)
  a.from={x,y,z,rx}; a.to={to[1],to[2],to[3],to[4] or rx}; a.t0=now+(delay or 0); a.dur=dur or M.dealTime; a.arc=arc or 0
 end
 function api.pose(a,now)
  if not a.to then return a.from[1],a.from[2],a.from[3],a.from[4] end
  local u=math.max(0,math.min(1,(now-a.t0)/a.dur)); local e=1-(1-u)^3
  return lerp(a.from[1],a.to[1],e),lerp(a.from[2],a.to[2],e)+a.arc*math.sin(math.pi*u),lerp(a.from[3],a.to[3],e),lerp(a.from[4],a.to[4],u)
 end
 function api:remove(a) for i,b in ipairs(list) do if b==a then table.remove(list,i); return end end end
 function api:clear() for i=#list,1,-1 do list[i]=nil end end
 function api:frame(now)
  local out={}
  for _,a in ipairs(list) do
   if not a.hidden then
    local x,y,z,rx=api.pose(a,now)
    out[#out+1]={id=a.id,card=a.card,chips=a.chips,x=x,y=y,z=z,rx=rx,ry=a.ry}
   end
  end
  return out
 end
 return api
end
local sounds=require('casino.sound')
local KEYS={[keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.left]=1,[keys.up]=2,[keys.right]=3,[keys.space]=2,[keys.enter]=2}
local HOTKEYS={[keys.h]='hit',[keys.s]='stand',[keys.d]='double',[keys.p]='split',[keys.b]='bet',[keys.c]='cash'}
-- opts: target, wallet, clock(), random(lo,hi), button(event,p1)->'LEFT'|'CENTER'|'RIGHT',
-- sound, newShoe() (tests stack the deck)
function M.run(opts)
 local t=opts.target
 local wallet=opts.wallet
 local clock=opts.clock or function() return os.epoch('utc')/1000 end
 local random=opts.random or math.random
 local button=opts.button or function(e,p) if e=='redstone' then return require('input').getButton(e,p) end end
 local sound=opts.sound or sounds()
 local view=renderer.new(t)
 local act=actors(clock)
 local betIndex=1
 local newShoe=opts.newShoe or function() return rules.newShoe(random) end
 local shoe=newShoe()
 local hands,dealer,active={},{},0
 local message,highlight='',false
 local request -- what the script is waiting for: {wait=time} or {ask=options}
 local results -- per-hand outcome labels after settlement
 local function say(text,hi) message=text; highlight=hi or false end
 local function bet() return rules.bets[betIndex] end
 local function balance() local s=wallet:session(); return s and s.balance end
 local function wait(s) coroutine.yield({wait=clock()+s}) end
 local function ask(options,card) return coroutine.yield({ask=options,card=card}) end
 -- Table geometry.
 local function handZ(h) return scene.handZ[#hands][h] end
 local function playerSpot(h,i) return {scene.playerX+(i-1)*scene.fan.x,.012*i,handZ(h)-.75+(i-1)*scene.fan.z,0} end
 local function dealerSpot(i,down) return {scene.dealerX,.012*i,-.9+(i-1)*scene.fan.z,down and math.pi or 0} end
 local function deal(target,down)
  local c=rules.draw(shoe)
  local a=act:add({card=c,from={scene.shoe[1],scene.shoe[2],scene.shoe[3],math.pi},ry=0})
  act:move(a,target,M.dealTime,0,.9)
  sound:play(clock(),'hat',.8,12+random(0,6))
  return c,a
 end
 local function dealPlayer(h)
  local hand=hands[h]; local c,a=deal(playerSpot(h,#hand.cards+1))
  hand.cards[#hand.cards+1]=c; hand.actors[#hand.actors+1]=a
  wait(M.dealTime)
 end
 local function dealDealer(down)
  local c,a=deal(dealerSpot(#dealer.cards+1,down),down)
  dealer.cards[#dealer.cards+1]=c; dealer.actors[#dealer.actors+1]=a
  wait(M.dealTime)
 end
 local function revealHole()
  if not dealer.hidden then return end
  dealer.hidden=false
  local a=dealer.actors[2]; local s=dealerSpot(2,false)
  act:move(a,s,.45,0,.6); sound:play(clock(),'hat',.8,20)
  wait(.5)
 end
 local function placeBet(h)
  local hand=hands[h]
  if hand.chips then act:move(hand.chips,{scene.betX,0,handZ(h)},.3); hand.chips.chips=hand.stake
  else hand.chips=act:add({chips=hand.stake,from={scene.betX,0,handZ(h),0}}) end
 end
 local function sweep()
  for i,a in ipairs(act.list) do act:move(a,{M.discard[1],M.discard[2],M.discard[3],a.card and math.pi or 0},.4,(i-1)*.03,.5) end
  if #act.list>0 then wait(.5) end
  act:clear(); hands,dealer,results={},{},nil
 end
 local function describe(cards,hidden)
  local out={}
  for i,c in ipairs(cards) do out[#out+1]=(hidden and i==2) and '??' or rules.describe(c) end
  return table.concat(out,' ')
 end
 local function totalText(cards)
  local n,soft=rules.total(cards)
  if n>21 then return n..' BUST' end
  if #cards==2 and n==21 then return 'BLACKJACK' end
  return (soft and 'SOFT ' or '')..n
 end
 -- Settle with the house; on failure hold the table until a retry succeeds.
 local function settle(round,amount)
  local ok,err=wallet:settle(round,amount)
  while not ok do
   say('HOUSE OFFLINE: PAYOUT PENDING')
   local a=ask({{name='retry',label='RETRY'},{name='retry',label='RETRY'},{name='retry',label='RETRY'}})
   if a=='retry' then ok,err=wallet:retry() end
  end
 end
 -- Keep the tentative double/split intact while its exact raise is uncertain.
 -- A definite refusal rolls it back; a recovered receipt resumes it once.
 local function increase(round,stake,maximum)
  local ok,err,context=wallet:increase(round,stake,maximum)
  while not ok and context and context.pending do
   say('HOUSE OFFLINE: RAISE PENDING')
   local a=ask({{name='retry',label='RETRY'},{name='retry',label='RETRY'},{name='retry',label='RETRY'}})
   if a=='retry' then
    ok,err,context=wallet:retry()
    if context and context.matches==false then context.pending=true end
   end
  end
  return ok,err,context and context.status and context.status~='open'
 end
 local function decide(h)
  local hand=hands[h]
  while rules.total(hand.cards)<21 and not hand.done do
   local options={{name='hit',label='HIT'},{name='stand',label='STAND'}}
   local extra={}
   if rules.canDouble(hand) and (balance() or 0)>=hand.stake then extra[#extra+1]={name='double',label='DOUBLE'} end
   if rules.canSplit(hands,hand) and (balance() or 0)>=hand.stake then extra[#extra+1]={name='split',label='SPLIT'} end
   if #extra==1 then options[3]=extra[1] elseif #extra==2 then options[3]={name='more',label='MORE...'} end
   say(#hands>1 and ('HAND %d: %s'):format(h,totalText(hand.cards)) or totalText(hand.cards))
   local a=ask(options)
   if a=='more' then
    a=ask({extra[1],extra[2],{name='back',label='BACK'}})
   end
   if a=='hit' then dealPlayer(h)
   elseif a=='stand' then hand.done=true
   elseif a=='double' and rules.canDouble(hand) then
    local stake=hand.stake
    hand.doubled=true; hand.stake=stake*2
    local ok,err,closed=increase(hands.round,stake,rules.maximum(hands))
    if closed then hands.aborted=true; return end
    if not ok then hand.doubled=false; hand.stake=stake; say(tostring(err):upper()); wait(1)
    else placeBet(h); sound:play(clock(),'snare',.7,10); dealPlayer(h); hand.done=true end
   elseif a=='split' and rules.canSplit(hands,hand) then
    local second={cards={table.remove(hand.cards)},actors={table.remove(hand.actors)},stake=hand.stake,split=true}
    hand.split=true; hands[2]=second
    local ok,err,closed=increase(hands.round,hand.stake,rules.maximum(hands))
    if closed then hands.aborted=true; return end
    if not ok then
     hands[2]=nil; hand.split=false; hand.cards[2]=second.cards[1]; hand.actors[2]=second.actors[1]
     say(tostring(err):upper()); wait(1)
    else
     -- Slide both hands apart and give each its second card.
     for i,a in ipairs(hand.actors) do act:move(a,playerSpot(1,i),.35) end
     act:move(second.actors[1],playerSpot(2,1),.35)
     placeBet(1); placeBet(2); wait(.4)
     local aces=hand.cards[1].rank=='A'
     dealPlayer(1); dealPlayer(2)
     if aces then hand.aces=true; second.aces=true; hand.done=true; second.done=true end
    end
   end
  end
 end
 local function round()
  local stake=bet()
  local r,err=wallet:begin(stake,rules.maximum({{cards={},stake=stake}}))
  if not r then say(tostring(err):upper()); return end
  hands={{cards={},actors={},stake=stake},round=r}
  dealer={cards={},actors={},hidden=true}
  placeBet(1); wait(.2)
  dealPlayer(1); dealDealer(false); dealPlayer(1); dealDealer(true)
  local up=rules.value(dealer.cards[1].rank)
  local dealerBJ=rules.total(dealer.cards)==21
  if up==1 or up==10 then say('DEALER CHECKS FOR BLACKJACK'); wait(.8) end
  local playerBJ=rules.blackjack(hands[1])
  if (up==1 or up==10) and dealerBJ or playerBJ then
   revealHole()
  else
   for h=1,2 do if hands[h] then active=h; decide(h); if hands.aborted then break end end end
   if hands.aborted then
    say('ROUND CLOSED BY HOUSE: HAND CANCELLED'); wait(1.5); act:clear(); hands,dealer,results={},{},nil; return
   end
   active=0
   revealHole()
   local live=false
   for _,hand in ipairs(hands) do if not rules.bust(hand.cards) then live=true end end
   while live and rules.dealerHits(dealer.cards) do dealDealer(false) end
  end
  -- Settle every hand together, then move chips to show it.
  local total=0; results={}
  for h,hand in ipairs(hands) do
   local back,label=rules.handReturn(hand,dealer.cards)
   total=total+back; results[h]=label
   if back==0 then act:move(hand.chips,{M.tray[1],M.tray[2],M.tray[3]},.5,.1*h,.6)
   elseif back>hand.stake then
    local win=act:add({chips=back-hand.stake,from={M.tray[1],M.tray[2],M.tray[3],0}})
    act:move(win,{scene.betX,0,handZ(h)+.8},.5,.1*h,.8)
   end
  end
  settle(r,total)
  local staked=0; for _,hand in ipairs(hands) do staked=staked+hand.stake end
  local summary={}; for h,label in ipairs(results) do summary[#summary+1]=(#results>1 and h..' ' or '')..label end
  local net=total-staked
  say(table.concat(summary,' / ')..(net>0 and ('  +'..net) or net<0 and ('  '..net) or '  EVEN'),net>0)
  if net>0 then for n,p in ipairs({12,16,19,24}) do sound:play(clock()+.4+n*.1,'bell',1,p) end
  elseif net<0 then sound:play(clock()+.3,'bass',1,6) end
  wait(.6)
 end
 local function script()
  while true do
   if rules.needsShuffle(shoe) then shoe=newShoe(); say('SHUFFLING A FRESH SHOE'); wait(1) end
   local s=wallet:session()
   local options
   if s then options={{name='bet',label='BET '..bet()},{name='deal',label='DEAL'},{name='cash',label=wallet.mode=='live' and 'CASH OUT' or 'RESET'}}
   else options={}; if #hands==0 then say(wallet.problem and wallet.problem:upper() or 'INSERT YOUR HOUSE CARD TO PLAY') end end
   if s and #hands==0 then say(('%s: CHOOSE A BET, THEN DEAL'):format(s.name:upper())) end
   local a=ask(options,true)
   if a=='bet' then betIndex=betIndex%#rules.bets+1; say(('BET %d'):format(bet())); sound:play(clock(),'pling',.6,6+betIndex*3)
   elseif a=='cash' then
    if #hands>0 then sweep() end
    if wallet.mode=='live' then
     local had=wallet:cashout()
     if had then say(('CARD RETURNED: %d CREDITS ON YOUR ACCOUNT'):format(had),true) end
    else wallet:cashout(); say('PRACTICE METER RESET TO 100') end
    wait(1.5)
   elseif a=='deal' then
    if (balance() or 0)<bet() then say('NOT ENOUGH CREDITS: LOWER THE BET'); wait(1)
    else if #hands>0 then sweep() end; round() end
   end
  end
 end
 local co=coroutine.create(script)
 local function resume(...)
  local ok,r=coroutine.resume(co,...)
  if not ok then error(r,0) end
  -- CC APIs yield an event filter (often nil), whereas this script's own
  -- waits/choices yield request tables. Forward raw events only to API waits.
  if type(r)=='table' and (r.ask or r.wait) then request=r
  else request={event=true,filter=r} end
 end
 local function choose(i,name)
  if not request or not request.ask then return end
  local opts=request.ask
  if name then for _,o in ipairs(opts) do if o.name==name then return resume(name) end end; return end
  if opts[i] then resume(opts[i].name) end
 end
 local nextCard=0
 local function update(now)
  if request and request.wait and now>=request.wait then resume() end
  if now>=nextCard and not (request and request.event) then
   nextCard=now+1
   if wallet:refresh() and request and request.card then resume('card') end
  end
  sound:tick(now)
 end
 local function draw(now)
  local hide=dealer.hidden
  local p={}
  for h,hand in ipairs(hands) do
   local mark=(#hands>1 and (active==h and '>' or ' ')..h..' ' or 'YOU  ')
   p[#p+1]=mark..describe(hand.cards)..'  '..(results and results[h] and results[h] or totalText(hand.cards))
  end
  local up=dealer.cards and #dealer.cards>0
  view:draw({actors=act:frame(now),credits=balance(),bet=bet(),title=wallet.title,
   dealer=up and ('DEALER  '..describe(dealer.cards,hide)..'  '..(hide and '' or totalText(dealer.cards))) or 'DEALER',
   player=#p>0 and table.concat(p,' | ') or '',message=message,highlight=highlight,
   options=request and request.ask})
 end
 wallet:refresh()
 resume()
 local timer=os.startTimer(0)
 while true do
  local e,a,b,c=os.pullEvent()
  local forwarding=request and request.event
  if forwarding and (not request.filter or request.filter==e) then resume(e,a,b,c) end
  if e=='timer' and a==timer then
   local now=clock(); update(now); draw(now); timer=os.startTimer(.05)
  elseif forwarding then
   -- Transport owns this event; do not turn the same key into a table action.
   if e=='disk' or e=='disk_eject' then nextCard=0 end
  elseif e=='key' then
   if a==keys.q or a==keys.backspace then
    if #hands==0 or (request and request.ask and request.card) then return end
   elseif HOTKEYS[a] then choose(nil,HOTKEYS[a])
   elseif KEYS[a] then choose(KEYS[a]) end
  elseif e=='monitor_touch' or e=='mouse_click' then
   local w,h=t.getSize()
   if c==h then for i,s in ipairs(renderer.slots(w)) do if b>=s.x1 and b<=s.x2 then choose(i) end end end
  elseif e=='disk' or e=='disk_eject' then nextCard=0
  elseif e=='term_resize' or e=='monitor_resize' then draw(clock())
  else
   local btn=button(e,a)
   if btn then choose(({LEFT=1,CENTER=2,RIGHT=3})[btn]) end
  end
 end
end
return M
