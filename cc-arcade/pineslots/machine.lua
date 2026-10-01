-- The slot machine itself: one event loop driving the reels, lamps, credit meter and sound.
-- The outcome is drawn and settled with the house the moment the arm is pulled; the reel
-- animation only reveals it, so a pulled card or a crash mid-spin cannot change a payout.
local reels=require('pineslots.reels')
local controls=require('pineslots.controls')
local renderer=require('pineslots.render')
local M={}
M.speed=14 -- stops per second while spinning
M.stopAt={1.1,1.55,2.0}
M.brake=.35
M.bounce=.25
-- Reel motion: constant speed, an ease-out brake landing exactly on the target stop
-- (positions decrease so symbols travel downward), then a small bounce.
function M.plan(from,target,stopAt)
 local raw=from-M.speed*(stopAt-M.brake/2)
 local final=target+reels.size*math.floor((raw-target)/reels.size)
 return {from=from,final=final,speed=(from-final)/(stopAt-M.brake/2),stopAt=stopAt}
end
function M.position(p,t)
 local cruise=p.stopAt-M.brake
 if t<=cruise then return p.from-p.speed*t end
 if t<=p.stopAt then local u=t-cruise; return p.from-p.speed*cruise-p.speed*(u-u*u/(2*M.brake)) end
 if t<p.stopAt+M.bounce then return p.final-.18*math.sin(math.pi*(t-p.stopAt)/M.bounce) end
 return p.final
end
local sounds=require('casino.sound')
-- opts: target, wallet, controls (from controls.new), clock(), random(lo,hi), exitKeys
function M.run(opts)
 local t=opts.target
 local wallet=opts.wallet
 local input=opts.controls or controls.new(controls.load())
 local clock=opts.clock or function() return os.epoch('utc')/1000 end
 local random=opts.random or math.random
 local view=renderer.new(t)
 local sound=opts.sound or sounds()
 local bet,positions=1,{0,0,0}
 local spin,result,hold
 local message,highlight='',false
 local pressed={}
 local shown -- credit meter value while a win rolls up
 local idleSince=clock(); local nextCard=0
 local function say(text,hi) message=text; highlight=hi or false end
 local function balance() local s=wallet:session(); return s and s.balance end
 local function welcome()
  local s=wallet:session()
  if s then say(('%s: PULL THE ARM TO SPIN'):format(s.name:upper()))
  elseif wallet.problem then say(wallet.problem:upper())
  else say('INSERT YOUR HOUSE CARD TO PLAY') end
 end
 local function start(stops,round,demo)
  local now=clock(); local total,wins=reels.evaluate(stops,bet)
  spin={start=now,plans={},stops=stops,total=total,wins=wins,demo=demo,round=round,stopped=0}
  for i=1,3 do spin.plans[i]=M.plan(positions[i],stops[i],M.stopAt[i]) end
  shown=balance(); result=nil
  say(demo and 'INSERT YOUR HOUSE CARD TO PLAY' or 'GOOD LUCK!')
  for n=0,math.floor(M.stopAt[3]*10) do sound:play(now+n/10,'hat',.6,18+n%3) end
 end
 local function pull()
  if spin and spin.demo then for i=1,3 do positions[i]=positions[i]%reels.size end; spin=nil end
  if spin then return end
  if hold then
   local ok,err=wallet:retry()
   if ok then hold=nil; say('PAYOUT CONFIRMED',true) else say('HOUSE OFFLINE: PULL TO RETRY ('..tostring(err)..')') end
   return
  end
  local s=wallet:session()
  if not s then say(wallet.problem and wallet.problem:upper() or 'INSERT YOUR HOUSE CARD TO PLAY'); return end
  if s.balance<bet then say(s.balance>0 and 'NOT ENOUGH CREDITS: PRESS BET ONE TO LOWER' or 'NO CREDITS: VISIT THE CASHIER'); return end
  local round,err=wallet:begin(bet,reels.maxReturn(bet))
  if not round then say(tostring(err):upper()); return end
  local stops=reels.spin(random)
  local total=reels.evaluate(stops,bet)
  local ok,settleErr=wallet:settle(round,total)
  if not ok then hold={round=round,total=total,error=settleErr} end
  start(stops,round,false)
 end
 local function act(name)
  if not name then return end
  local now=clock(); pressed[name]=now+.25; idleSince=now
  if name=='arm' then return pull() end
  if spin and not spin.demo then return end
  if spin and spin.demo then spin=nil end
  if name=='bet' then bet=bet%reels.maxBet+1; say(('BET %d: %d LINE%s'):format(bet,bet,bet>1 and 'S' or '')); sound:play(now,'pling',.6,8+bet*2)
  elseif name=='max' then bet=reels.maxBet; say('MAX BET: ALL 5 LINES'); sound:play(now,'pling',.6,20)
  elseif name=='cash' then
   if hold then say('PAYOUT PENDING: PULL THE ARM TO RETRY'); return end
   if wallet.mode=='exhibition' then
    wallet:cashout(); say('PRACTICE METER RESET TO 100')
   else
    local had=wallet:cashout()
    if had then say(('CARD RETURNED: %d CREDITS ON YOUR ACCOUNT'):format(had),true); for n=0,4 do sound:play(now+n*.08,'chime',.8,12+n*2) end
    else say('NO CARD TO RETURN') end
   end
  end
 end
 local function finish(now)
  local s=spin; spin=nil
  for i=1,3 do positions[i]=s.stops[i] end
  if s.demo then welcome(); return end
  result={wins=s.wins,total=s.total,at=now}
  if hold then say('HOUSE OFFLINE: PULL THE ARM TO RETRY PAYOUT')
  elseif s.total>0 then
   say(('WINNER! %d CREDITS'):format(s.total),true)
   local notes=s.total>=80 and {12,16,19,24,19,24,28,31} or s.total>=15 and {12,16,19,24} or {14,18}
   for n,p in ipairs(notes) do sound:play(now+n*.11,'bell',1,p) end
  else shown=nil; say('NO WIN. PULL AGAIN!') end
 end
 local function update(now)
  for _,n in ipairs(input:poll()) do act(n) end
  if now>=nextCard then
   nextCard=now+1
   if wallet:refresh() then welcome() end
  end
  if spin then
   local t=now-spin.start
   for i=1,3 do
    positions[i]=M.position(spin.plans[i],t)
    if spin.stopped<i and t>=M.stopAt[i] then spin.stopped=i; sound:play(now,'snare',1,4+i) end
   end
   if t>=M.stopAt[3]+M.bounce then finish(now) end
  elseif result and result.total>0 and shown then
   -- Credit meter rolls up the win, a few credits per frame.
   local target=balance() or shown
   shown=math.min(target,shown+math.max(1,math.ceil(result.total/20)))
   if shown>=target then shown=nil end
  end
  if result and result.total>0 and not spin and #result.wins>1 then
   local w=result.wins[math.floor((now-result.at)/1.4)%#result.wins+1]
   if now-result.at>1.4 then
    say(('LINE %d %s: %s %s %s PAYS %d'):format(w.line,reels.lineNames[w.line],reels.names[w.symbols[1]],reels.names[w.symbols[2]],reels.names[w.symbols[3]],w.pay),true)
   end
  end
  -- Attract: with no card in a live cabinet, run a free demo spin every few seconds.
  if wallet.mode=='live' and not wallet:session() and not spin and now-idleSince>6 then
   idleSince=now; start(reels.spin(random),nil,true)
  end
  sound:tick(now)
 end
 local function lamps(now)
  if result and result.total>0 and not spin and now-result.at<4 then
   local on=math.floor(now*6)%2==0; return function() return on end
  end
  local phase=math.floor(now*(spin and 16 or 5))
  return function(i) return (i+phase)%4==0 end
 end
 local function lines(now)
  local lit={}
  if result and not spin and result.total>0 then
   local on=math.floor(now*4)%2==0
   for _,w in ipairs(result.wins) do lit[w.line]=on end
   return lit
  end
  for n=1,bet do lit[n]=true end
  return lit
 end
 local function draw(now)
  local p={}; for k,v in pairs(pressed) do if v>now then p[k]=true end end
  view:draw({positions=positions,bet=bet,credits=shown or balance(),title=wallet.title,
   lamps=lamps(now),lines=lines(now),pressed=p,message=message,highlight=highlight})
 end
 wallet:refresh(); welcome()
 local timer=os.startTimer(0)
 while true do
  local e,a,b,c=os.pullEvent()
  if e=='timer' and a==timer then
   local now=clock(); update(now); draw(now); timer=os.startTimer(.05)
  elseif e=='redstone' then for _,n in ipairs(input:poll()) do act(n) end
  elseif e=='key' then
   if a==keys.q or a==keys.backspace then if not spin or spin.demo then return end end
   act(input:key(a))
  elseif e=='monitor_touch' or e=='mouse_click' then
   local w,h=t.getSize()
   if c==h then for _,btn in ipairs(renderer.buttons(w)) do if b>=btn.x1 and b<=btn.x2 then act(btn.name) end end
   elseif c>1 and c<h-1 then act('arm') end
  elseif e=='disk' or e=='disk_eject' then nextCard=0
  elseif e=='term_resize' or e=='monitor_resize' then draw(clock()) end
 end
end
return M
