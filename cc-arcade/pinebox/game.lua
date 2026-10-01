-- Pine Shut the Box: the grand prize round. Stake a bet, then roll two dice and knock
-- down tiles that add up to each roll. Clear all nine for 13x; a roll no tiles can make
-- ends the round. The house reserves the grand prize up front and settles once.
local rules=require('pinebox.rules')
local dice=require('pinebox.dice')
local renderer=require('pinebox.render')
local sounds=require('casino.sound')
local M={}
M.back=1.6 -- seconds the camera holds on the settled dice
local KEYS={[keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.left]=1,[keys.up]=2,[keys.right]=3,[keys.space]=2,[keys.enter]=2}
local HOTKEYS={[keys.r]='roll',[keys.t]='take',[keys.b]='bet',[keys.c]='cash'}
-- opts: target, wallet, clock(), random(lo,hi), button(event,p1), sound
function M.run(opts)
 local t=opts.target
 local wallet=opts.wallet
 local clock=opts.clock or function() return os.epoch('utc')/1000 end
 local random=opts.random or math.random
 local button=opts.button or function(e,p) if e=='redstone' then return require('input').getButton(e,p) end end
 local sound=opts.sound or sounds()
 local view=renderer.new(t)
 local betIndex=1
 local board=rules.full
 local tiles={}; for n=1,9 do tiles[n]={from=0,to=0,t0=0} end
 local selection=0
 local throw,thrownAt,lastBump
 local message,highlight='',false
 local info=''
 local request
 local celebrate=0
 local function say(text,hi) message=text; highlight=hi or false end
 local function bet() return rules.bets[betIndex] end
 local function balance() local s=wallet:session(); return s and s.balance end
 local function wait(s) coroutine.yield({wait=clock()+s}) end
 local function ask(options,card) return coroutine.yield({ask=options,card=card}) end
 local function boardText()
  local out={}; for n=1,9 do out[n]=rules.has(board,n) and tostring(n) or '.' end
  return table.concat(out,' ')
 end
 local function fall(n,down) local now=clock(); tiles[n].from=tiles[n].to; tiles[n].to=down and 1 or 0; tiles[n].t0=now end
 local function resetBoard()
  board=rules.full; selection=0
  for n=1,9 do if tiles[n].to>0 then fall(n,false) end end
 end
 local function roll()
  local values={random(1,6),random(1,6)}
  local function rng() return random(0,1048575)/1048576 end
  throw=dice.throw(rng,values); thrownAt=clock(); lastBump=0
  sound:play(thrownAt,'hat',.6,6)
  -- Hold for the snap zoom on the result, then the camera eases back to the board.
  wait(throw.duration+M.back)
  return values
 end
 local function settle(r,amount)
  local ok=wallet:settle(r,amount)
  while not ok do
   say('HOUSE OFFLINE: PAYOUT PENDING')
   if ask({{name='retry',label='RETRY'},{name='retry',label='RETRY'},{name='retry',label='RETRY'}})=='retry' then ok=wallet:retry() end
  end
 end
 local function round()
  local stake=bet(); local prize=stake*rules.prize
  local r,err=wallet:begin(stake,prize)
  if not r then say(tostring(err):upper()); return end
  resetBoard(); wait(.4)
  while true do
   info=('BOARD %s   CHANCE TO CLEAR %.1f%%'):format(boardText(),rules.chance(board)*100)
   say('ROLL THE DICE')
   ask({{name='',label=''},{name='roll',label='ROLL'},{name='',label=''}})
   local values=roll()
   local total=values[1]+values[2]
   local moves=rules.moves(board,total)
   info=('ROLLED %d + %d = %d   BOARD %s'):format(values[1],values[2],total,boardText())
   if #moves==0 then
    say(('NO WAY TO MAKE %d. ROUND OVER'):format(total))
    sound:play(clock(),'didgeridoo',1,4); sound:play(clock()+.35,'didgeridoo',1,1)
    settle(r,0); wait(1.8); return
   end
   -- Start on the best play; LEFT/RIGHT step through the others.
   local best=rules.best(board,total); local pick=1
   for i,m in ipairs(moves) do if m==best then pick=i end end
   while true do
    selection=moves[pick]
    local names={}; for _,n in ipairs(rules.tiles(selection)) do names[#names+1]=tostring(n) end
    say(('TAKE %s?%s'):format(table.concat(names,' + '),selection==best and ' (BEST)' or ''),selection==best)
    local many=#moves>1
    local a=ask({many and {name='prev',label='< OTHER'} or {name='',label=''},{name='take',label='TAKE'},many and {name='next',label='OTHER >'} or {name='',label=''}})
    if a=='prev' then pick=(pick-2)%#moves+1; sound:play(clock(),'hat',.5,16)
    elseif a=='next' then pick=pick%#moves+1; sound:play(clock(),'hat',.5,18)
    elseif a=='take' then break end
   end
   local now=clock()
   for i,n in ipairs(rules.tiles(selection)) do fall(n,true); tiles[n].t0=now+(i-1)*.15; sound:play(now+(i-1)*.15+.3,'basedrum',1,8) end
   board=bit32.band(board,bit32.bnot(selection)); selection=0
   wait(.6)
   if board==0 then
    info='BOARD CLEARED!'
    say(('GRAND PRIZE! YOU WIN %d CREDITS'):format(prize),true)
    celebrate=clock()+4
    local tune={12,16,19,24,19,24,28,31,24,28,31,36}
    for i,p in ipairs(tune) do sound:play(clock()+i*.12,'bell',1,math.min(24,p)) ; sound:play(clock()+i*.12,'pling',.6,math.min(24,p-12)) end
    settle(r,prize); wait(3); return
   end
  end
 end
 local function script()
  while true do
   local s=wallet:session()
   local options={}
   if s then
    options={{name='bet',label='BET '..bet()},{name='play',label='PLAY'},{name='cash',label=wallet.mode=='live' and 'CASH OUT' or 'RESET'}}
    say(('CLEAR ALL NINE TO WIN %dx: BET %d WINS %d'):format(rules.prize,bet(),bet()*rules.prize))
    info=('BOARD %s   BEST-PLAY CHANCE %.1f%%'):format(boardText(),rules.chance(rules.full)*100)
   else say(wallet.problem and wallet.problem:upper() or 'INSERT YOUR HOUSE CARD TO PLAY') end
   local a=ask(options,true)
   if a=='bet' then betIndex=betIndex%#rules.bets+1; sound:play(clock(),'pling',.6,6+betIndex*3)
   elseif a=='cash' then
    if wallet.mode=='live' then
     local had=wallet:cashout()
     if had then say(('CARD RETURNED: %d CREDITS ON YOUR ACCOUNT'):format(had),true) end
    else wallet:cashout(); say('PRACTICE METER RESET TO 100') end
    wait(1.5)
   elseif a=='play' then
    if (balance() or 0)<bet() then say('NOT ENOUGH CREDITS: LOWER THE BET'); wait(1)
    else round(); resetBoard() end
   end
  end
 end
 local co=coroutine.create(script)
 local function resume(...)
  local ok,r=coroutine.resume(co,...)
  if not ok then error(r,0) end
  request=r
 end
 local function choose(i,name)
  if not request or not request.ask then return end
  local opts=request.ask
  if name then for _,o in ipairs(opts) do if o.name==name then return resume(name) end end; return end
  if opts[i] and opts[i].name~='' then resume(opts[i].name) end
 end
 local nextCard=0
 local function update(now)
  if request and request.wait and now>=request.wait then resume() end
  if now>=nextCard then
   nextCard=now+1
   if wallet:refresh() and request and request.card then resume('card') end
  end
  -- Clack on every impact, louder for harder hits.
  if throw then
   local tt=now-thrownAt
   if tt<=throw.duration+.1 then
    local b=dice.bumps(throw,lastBump,tt); lastBump=tt
    if b>0 then sound:play(now,b>12 and 'snare' or 'hat',math.min(1,.3+b/20),10+random(0,8)) end
   end
  end
  sound:tick(now)
 end
 local function draw(now)
  local view_tiles={}
  for n=1,9 do
   local s=tiles[n]; local u=math.max(0,math.min(1,(now-s.t0)/.45))
   local down=s.from+(s.to-s.from)*(u*u)
   if s.to>s.from and u>=1 then down=1+.08*math.sin(math.min(1,(now-s.t0-.45)/.2)*math.pi) end
   local lit=bit32.btest(selection,2^(n-1))
   view_tiles[n]={down=math.min(1.08,down),lit=lit,lift=lit and .25 or 0}
  end
  local d,camera
  if throw then
   d={}
   local tt=now-thrownAt
   for i=1,2 do local pos,m=dice.pose(throw,i,tt); d[i]={pos=pos,matrix=m} end
   if tt<throw.duration+M.back then camera=renderer.follow({d[1].pos,d[2].pos},tt,throw.duration,M.back) end
  end
  local party=now<celebrate
  local phase=math.floor(now*(party and 12 or 4))
  view:draw({tiles=view_tiles,dice=d,camera=camera,credits=balance(),bet=bet(),title=wallet.title,info=info,
   message=message,highlight=highlight or (party and phase%2==0),options=request and request.ask,
   lamps=function(i) if party then return (i+phase)%2==0 end return (i+phase)%4==0 end})
 end
 wallet:refresh()
 resume()
 local timer=os.startTimer(0)
 while true do
  local e,a,b,c=os.pullEvent()
  if e=='timer' and a==timer then
   local now=clock(); update(now); draw(now); timer=os.startTimer(.05)
  elseif e=='key' then
   if a==keys.q or a==keys.backspace then
    if request and request.ask and request.card then return end
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
