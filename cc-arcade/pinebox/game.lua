-- Pine Shut the Box: the grand prize round. Stake a bet, then roll two dice and knock
-- down tiles that add up to each roll. Clear all nine for 13x; a roll no tiles can make
-- ends the turn. The house reserves the grand prize up front and settles once per turn.
-- A match seats 2-4 players: each antes from their own card into a pot, then takes a
-- turn on a fresh board scoring the tiles left standing. Lowest score takes the pot.
local rules=require('pinebox.rules')
local dice=require('pinebox.dice')
local renderer=require('pinebox.render')
local avatars=require('pinebox.avatars')
local sounds=require('casino.sound')
local M={}
M.back=1.6 -- seconds the camera holds on the settled dice
local KEYS={[keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.left]=1,[keys.up]=2,[keys.right]=3,[keys.space]=2,[keys.enter]=2}
local HOTKEYS={[keys.r]='roll',[keys.t]='take',[keys.b]='bet',[keys.c]='cash',[keys.s]='start'}
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
 local seats=2
 local players -- {list=scores, current=i, avatars=mascot indexes} during a match
 local soloAvatar=1
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
 local function avatarName(i) local a=avatars.get(i); return a and a.name or 'MASCOT' end
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
 -- Keep asking until the house acknowledges: op is 'settle' or 'refund'.
 local function settle(r,amount,op)
  local ok
  if op=='refund' then ok=wallet:refund(r) else ok=wallet:settle(r,amount) end
  while not ok do
   say('HOUSE OFFLINE: PAYOUT PENDING')
   if ask({{name='retry',label='RETRY'},{name='retry',label='RETRY'},{name='retry',label='RETRY'}})=='retry' then ok=wallet:retry() end
  end
 end
 -- A player's card name, or PLAYER n when there is none or two seats share it.
 local function who(p)
  local n=players and players.names[p]
  if n then for q,m in pairs(players.names) do if q~=p and m==n then n=nil break end end end
  return n and n:upper() or ('PLAYER '..p)
 end
 -- One turn on a fresh board. Returns the score: the tiles left standing, 0 for a
 -- shut box. Solo turns stake the bet against the grand prize; match turns play for
 -- the pot, so they touch no money. Solo returns nil if the house refused the stake.
 local function round(p)
  local solo=not players
  local stake=bet(); local prize=stake*rules.prize
  local r
  if solo then
   local err; r,err=wallet:begin(stake,prize)
   if not r then say(tostring(err):upper()); wait(1.5); return end
  end
  local tag=solo and '' or who(p)..': '
  resetBoard(); wait(.4)
  while true do
   -- The score tags fill the info row in a match; the chips already show the board.
   info=solo and ('BOARD %s   CHANCE TO CLEAR %.1f%%'):format(boardText(),rules.chance(board)*100) or ('POT %d   CLEAR %.1f%%'):format(players.pot,rules.chance(board)*100)
   say(tag..'ROLL THE DICE',not solo)
   ask({{name='',label=''},{name='roll',label='ROLL'},{name='',label=''}})
   local values=roll()
   local total=values[1]+values[2]
   local moves=rules.moves(board,total)
   info=('ROLLED %d + %d = %d'):format(values[1],values[2],total)..(solo and '   BOARD '..boardText() or '')
   if #moves==0 then
    local left=rules.sum(board)
    say(solo and ('NO WAY TO MAKE %d. ROUND OVER'):format(total) or ('NO %d. %s SCORES %d'):format(total,who(p),left))
    sound:play(clock(),'didgeridoo',1,4); sound:play(clock()+.35,'didgeridoo',1,1)
    if r then settle(r,0) end
    wait(1.8); return left
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
    say(solo and ('GRAND PRIZE! YOU WIN %d CREDITS'):format(prize) or tag..'SHUT THE BOX!',true)
    celebrate=clock()+4
    local tune={12,16,19,24,19,24,28,31,24,28,31,36}
    for i,q in ipairs(tune) do sound:play(clock()+i*.12,'bell',1,math.min(24,q)) ; sound:play(clock()+i*.12,'pling',.6,math.min(24,q-12)) end
    if r then settle(r,prize) end
    wait(3); return 0
   end
  end
 end
 -- Every player antes the bet from their own card: insert it, press ANTE, pass the
 -- slot on. Each account holds one house round reserving the whole pot, so seats
 -- sharing a card share a round. Returns false if the table cancels (antes refunded).
 local function ante(n)
  local stake=bet(); local pot=stake*n
  players={list={},names={},seat={},rounds={},avatars={},current=1,pot=0}
  for i=1,n do players.list[i]=false; players.avatars[i]=(i-1)%#avatars.list+1 end
  while players.current<=n do
   local p=players.current; local s=wallet:session()
   info=('ANTE %d EACH. LOW SCORE TAKES THE POT OF %d'):format(stake,pot)
   local mascot=avatarName(players.avatars[p])
   say(s and ('PLAYER %d [%s]: ANTE %d AS %s?'):format(p,mascot,stake,(s.name or 'PLAYER'):upper()) or ('PLAYER %d [%s]: INSERT YOUR HOUSE CARD'):format(p,mascot),true)
   local a=ask({{name='cancel',label='CANCEL'},s and {name='ante',label='ANTE '..stake} or {name='',label=''},{name='mascot',label=mascot..' >'}},'ante')
   if a=='cancel' then
    for _,r in pairs(players.rounds) do settle(r,0,'refund') end
    players=nil; say('MATCH CANCELLED: ANTES RETURNED'); wait(1.5); return false
   elseif a=='mascot' then
    players.avatars[p]=players.avatars[p]%#avatars.list+1
    sound:play(clock(),'hat',.5,12+players.avatars[p])
   elseif a=='ante' and s then
    local key=s.account or s.name or 'card'
    local r=players.rounds[key]; local ok,err
    if r then ok,err=wallet:increase(r,stake,pot) else r,err=wallet:begin(stake,pot); ok=r~=nil end
    if ok then
     players.rounds[key]=r; players.seat[p]=key; players.names[p]=wallet.mode=='live' and s.name or nil; players.pot=players.pot+stake
     players.current=p+1; sound:play(clock(),'pling',.8,10+p*3)
    else say(tostring(err):upper()); wait(1.5) end
   end
  end
  players.current=1
  return true
 end
 -- Everyone takes a turn, then the lowest score takes the pot; a tie splits it (any odd
 -- credit to the first tied seat). Every account's round settles with its share.
 local function match(n)
  if not ante(n) then return end
  for p=1,n do players.current=p; players.list[p]=round(p) end
  local low=math.huge; for _,sc in ipairs(players.list) do low=math.min(low,sc) end
  local won={}; for p,sc in ipairs(players.list) do if sc==low then won[#won+1]=p end end
  local pot=players.pot; local share=math.floor(pot/#won)
  local paid={}
  for i,p in ipairs(won) do local key=players.seat[p]; paid[key]=(paid[key] or 0)+share+(i==1 and pot-share*#won or 0) end
  players.current=nil; info=('FINAL SCORES: POT %d'):format(pot)
  if #won>1 then
   local names={}; for _,p in ipairs(won) do names[#names+1]=who(p) end
   say(('TIE AT %d: %s SPLIT %d'):format(low,table.concat(names,' & '),pot),true)
  else say(('%s WINS WITH %d: +%d CREDITS'):format(who(won[1]),low,pot),true) end
  for key,r in pairs(players.rounds) do settle(r,paid[key] or 0) end
  celebrate=clock()+3
  for i,q in ipairs({12,16,19,24}) do sound:play(clock()+i*.12,'bell',1,q) end
  wait(4)
  players=nil
 end
 -- Before a match: LEFT/RIGHT set how many play, CENTER starts.
 local function pickSoloMascot()
  while true do
   local mascot=avatarName(soloAvatar)
   say(('YOUR MASCOT: %s'):format(mascot),true)
   info='LEFT/RIGHT PICKS A CHARACTER. CENTER LOCKS IT IN'
   local a=ask({{name='prevMascot',label='< MASCOT'},{name='mascotReady',label=mascot},{name='nextMascot',label='MASCOT >'}})
   if a=='prevMascot' then soloAvatar=(soloAvatar-2)%#avatars.list+1; sound:play(clock(),'hat',.5,14)
   elseif a=='nextMascot' then soloAvatar=soloAvatar%#avatars.list+1; sound:play(clock(),'hat',.5,18)
   elseif a=='mascotReady' then return end
  end
 end
 local function seat()
  while true do
   if seats==1 then
    say(('SOLO: BET %d, CLEAR ALL NINE FOR %d'):format(bet(),bet()*rules.prize))
    info='ONE PLAYER PLAYS FOR THE GRAND PRIZE'
   else
    say(('%d PLAYERS: ANTE %d EACH, POT %d'):format(seats,bet(),bet()*seats))
    info='EVERYONE ANTES FROM THEIR CARD. LOW SCORE TAKES THE POT'
   end
   local a=ask({{name='fewer',label='< FEWER'},{name='start',label=('START %dP'):format(seats)},{name='more',label='MORE >'}})
   if a=='fewer' then seats=(seats-2)%4+1; sound:play(clock(),'hat',.5,14)
   elseif a=='more' then seats=seats%4+1; sound:play(clock(),'hat',.5,18)
   elseif a=='start' then return seats end
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
    local n=seat()
    if n>1 then match(n)
    else
     pickSoloMascot()
     if (balance() or 0)<bet() then say('NOT ENOUGH CREDITS: LOWER THE BET'); wait(1)
     else round(1) end
    end
    resetBoard()
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
  local avatar=players and players.current and players.avatars and players.avatars[players.current] or (not players and soloAvatar or nil)
  local ready=false
  if request and request.ask then for _,o in ipairs(request.ask) do if o.name=='roll' then ready=true break end end end
  view:draw({tiles=view_tiles,players=players,dice=d,camera=camera,credits=balance(),bet=bet(),title=wallet.title,info=info,
   message=message,highlight=highlight or (party and phase%2==0),options=request and request.ask,
   avatar=avatar,avatarReady=ready,avatarPhase=math.floor(now*2),
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
    if request and request.ask and request.card==true then return end
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
