-- The table computer: lobby, seat liveness, game flow and money. Pure logic is in
-- M.new (driven by receive/tick with an injectable clock and sender); M.run wires
-- it to rednet, timers and the table's own display.
local view=require('tables.view')
local M={COUNTDOWN=10,IDLE=30,RESULT=5}
-- o: seats (computer IDs in seat order), game, bank, send(id,msg), now() in seconds,
--    rng(n) -> 1..n, exhibition (guests may join without a card)
function M.new(o)
 local h={phase='LOBBY',seats={},log={},table=o.id,bank=o.bank}
 local index={}
 for i,id in ipairs(o.seats) do h.seats[i]={id=id,online=false,last=-math.huge,seq=0,sent=nil}; index[id]=i end
 local game=o.game
 local function log(s) h.log[#h.log+1]=s end
 local function online(seat) return o.now()-seat.last<=require('tables.net').TIMEOUT end
 local function shortName(account) return tostring(account):gsub('^guest:.*','GUEST'):sub(1,10) end
 -- Lobby identity follows the card in the drive; a game keeps the account it started with.
 local function present(seat,card)
  local account=card and (card.account or (o.exhibition and card.diskID and 'disk:'..card.diskID))
  if seat.guest then account=seat.account end
  if account~=seat.account then seat.account=account; seat.ready=false end
 end
 local function start()
  local players={}; h.round={players={},total=0}
  for i,seat in ipairs(h.seats) do
   if seat.ready and seat.account and online(seat) then
    local ok,err=o.bank:stake(seat.account,game.ante)
    if ok then players[#players+1]={seat=i,name=shortName(seat.account)}; h.round.players[i]=seat.account; h.round.total=h.round.total+game.ante
    else seat.ready=false; seat.notice=err end
   end
  end
  if #players==0 then return end
  h.state=game.new(players,o.rng); h.phase='PLAYING'; h.lastAction=o.now(); h.countdown=nil
  local list={}; for _,p in ipairs(players) do list[#list+1]=p.seat end
  log('start '..table.concat(list,','))
 end
 local function finish(payouts)
  local paid=0; for _,amount in pairs(payouts) do paid=paid+amount end
  -- Money check before anything is credited: solo games may pay up to the game's
  -- stated maximum; player-vs-player games can only redistribute the stakes.
  local limit=game.maximum and game.maximum(h.state) or h.round.total
  if paid>limit then error('Table payout '..paid..' exceeds limit '..limit,0) end
  h.round.payouts=payouts
  for seat,amount in pairs(payouts) do
   o.bank:pay(h.round.players[seat],amount); log('payout '..seat..' '..amount)
  end
  h.phase='RESULT'; h.resultUntil=o.now()+M.RESULT
 end
 function h:seatView(i)
  local seat=h.seats[i]
  local v={title=game.title..' | SEAT '..i,footer='Seat '..i..' | table #'..tostring(o.id),lines={},buttons={}}
  local playing=h.round and h.round.players[i] and h.phase~='LOBBY'
  if playing then
   local g=game.view(h.state,i); v.lines=g.lines; v.buttons=g.buttons or {}
   if h.phase=='RESULT' then
    local won=h.round.payouts[i] or 0
    v.status=won>game.ante and 'YOU WIN '..won or won==game.ante and 'PUSH: stake returned' or 'No win this hand'
    if #v.lines>0 then v.lines[#v.lines+1]='' end
    v.lines[#v.lines+1]={'Balance: '..o.bank:balance(h.round.players[i]),colors.yellow}
   else v.status=game.pending(h.state,i) and 'Your move' or 'Waiting for other players' end
  elseif h.phase~='LOBBY' then
   v.status='Game in progress. Next hand soon.'
   for _,l in ipairs(game.view(h.state,nil).lines) do v.lines[#v.lines+1]=l end
  elseif not seat.account then
   v.status='Insert your house card'
   v.lines={'Ante '..game.ante..' credits per hand.','Play alone against the house,','or against everyone seated.'}
   if o.exhibition then v.buttons={{id='guest',label='JOIN AS GUEST'}} end
  else
   v.status=seat.ready and (h.countdown and 'Starting in '..math.max(0,math.ceil(h.countdown-o.now()))..'s' or 'Ready') or 'Press READY to play'
   v.lines={{'Player: '..shortName(seat.account),colors.white},{'Balance: '..o.bank:balance(seat.account)..' credits',colors.yellow},'Ante: '..game.ante}
   v.buttons={seat.ready and {id='unready',label='NOT READY',color=colors.orange} or {id='ready',label='READY'}}
   if seat.guest then v.buttons[#v.buttons+1]={id='leave',label='LEAVE',color=colors.lightGray} end
  end
  if seat.notice then v.lines[#v.lines+1]={seat.notice,colors.red} end
  return v
 end
 function h:publicView()
  local v={title=game.title..' | TABLE #'..tostring(o.id),lines={},buttons={},footer='Q: stop table'}
  if h.phase=='LOBBY' then
   v.status=h.countdown and 'Starting in '..math.max(0,math.ceil(h.countdown-o.now()))..'s' or 'Insert cards at the seats'
   for i,seat in ipairs(h.seats) do
    local state=not online(seat) and 'offline' or not seat.account and 'empty' or seat.ready and 'READY' or 'seated'
    v.lines[#v.lines+1]={'Seat '..i..' (#'..seat.id..'): '..state..(seat.account and ' '..shortName(seat.account) or ''),seat.ready and colors.lime or colors.lightGray}
   end
  else
   v.status=h.phase=='RESULT' and 'Hand over' or 'Playing'
   v.lines=game.view(h.state,nil).lines
  end
  return v
 end
 local function push(i,force)
  local seat=h.seats[i]
  local v=h:seatView(i); local key=textutils.serialize(v,{compact=true})
  if key~=seat.sent then seat.seq=seat.seq+1; seat.sent=key; force=true end
  if force then o.send(seat.id,{t='view',seq=seat.seq,view=v}) end
 end
 function h:receive(from,msg)
  local i=index[from]; if not i then return end -- not a seat at this table
  local seat=h.seats[i]
  if msg.t=='hello' then
   seat.last=o.now(); present(seat,type(msg.card)=='table' and msg.card or nil)
   if h.phase=='LOBBY' then h:tick() end
   push(i,true)
  elseif msg.t=='press' then
   seat.last=o.now()
   -- Act only on a button this seat is offered right now. Other players acting
   -- does not cancel a press, but a double tap or a delayed packet for a button
   -- that has since gone away is ignored.
   local offered=false
   for _,b in ipairs(h:seatView(i).buttons) do if b.id==msg.button then offered=true end end
   if offered then h:press(i,msg.button) else log('ignored '..i..' '..tostring(msg.button)) end
   push(i,true)
  end
 end
 function h:press(i,button)
  local seat=h.seats[i]; seat.notice=nil
  if h.phase=='LOBBY' then
   if button=='guest' and o.exhibition and not seat.account then seat.guest=true; seat.account='guest:'..seat.id
   elseif button=='leave' and seat.guest then seat.guest=nil; seat.account=nil; seat.ready=false
   elseif button=='ready' and seat.account then seat.ready=true
   elseif button=='unready' then seat.ready=false end
   h:tick()
  elseif h.phase=='PLAYING' and h.round.players[i] then
   if game.press(h.state,i,button) then h.lastAction=o.now(); log('press '..i..' '..button); h:tick() end
  end
 end
 function h:tick()
  local now=o.now()
  if h.phase=='LOBBY' then
   local ready,seated=0,0
   for _,seat in ipairs(h.seats) do
    if seat.account and online(seat) then seated=seated+1; if seat.ready then ready=ready+1 end end
   end
   if ready==0 then h.countdown=nil
   elseif ready==seated or (h.countdown and now>=h.countdown) then start()
   elseif not h.countdown then h.countdown=now+M.COUNTDOWN end
  elseif h.phase=='PLAYING' then
   for i in pairs(h.round.players) do
    if game.pending(h.state,i) and (not online(h.seats[i]) or now-h.lastAction>M.IDLE) then
     game.auto(h.state,i); h.lastAction=now; log('auto '..i)
    end
   end
   local payouts=game.payouts(h.state)
   if payouts then finish(payouts) end
  elseif h.phase=='RESULT' and now>=h.resultUntil then
   h.phase='LOBBY'; h.state=nil; h.round=nil
   for _,seat in ipairs(h.seats) do seat.ready=false end
   log('lobby')
  end
  for i,seat in ipairs(h.seats) do if online(seat) then push(i,false) end end
 end
 return h
end
-- script (optional) runs alongside the table with the host object; used by tests.
function M.run(c,script)
 local net=require('tables.net')
 local link=net.open(c)
 local monitor=peripheral.find('monitor')
 local t=monitor or term.current()
 if monitor then monitor.setTextScale(1) end
 local h=M.new({id=os.getComputerID(),seats=c.seats,game=require('tables.games.'..(c.game or 'highcard')),
  bank=require('tables.bank').exhibition(),send=link.send,now=function() return os.epoch('utc')/1000 end,
  rng=math.random,exhibition=c.exhibition~=false})
 math.randomseed(os.epoch('utc'))
 local function loop()
  local timer=os.startTimer(.25)
  while true do
   local e,a,b,p=os.pullEvent()
   local from,msg=link.parse(e,a,b,p)
   if from then h:receive(from,msg)
   elseif e=='timer' and a==timer then h:tick(); timer=os.startTimer(.25)
   elseif e=='key' and a==keys.q and not script then return end
   if t.isColor() then view.draw(t,h:publicView()) end
  end
 end
 if script then parallel.waitForAny(loop,function() script(h) end) else loop() end
 return h
end
return M
