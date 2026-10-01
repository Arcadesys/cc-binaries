local ui=require('derby.ui')
local sim=require('derby.sim')
local M={}
function M.run(client,t)
 local horse,stakeIndex,focus=1,1,1
 local stakes={5,10,20}; local status=''; local review
 local snapshot={}; local account,balance,card
 local timer=os.startTimer(0)
 local function refresh()
  card=ui.card(); account=card and card.account
  local r=client:read({op='snapshot',account=account})
  snapshot=r
  if account then local a=client:read({op='lookup',account=account}); balance=a.ok and a.balance or nil; if not a.ok then status=a.error end else balance=nil end
 end
 local function draw()
  if not ui.usable(t) then return end
  ui.clear(t,'DERBY BETTING')
  ui.line(t,2,account and (' Balance: '..tostring(balance or 'UNAVAILABLE')..' credits') or ' Insert a house account card',colors.yellow)
  if review then
   ui.line(t,4,' CONFIRM YOUR TICKET',colors.yellow)
   ui.line(t,6,' '..review.horse..' '..sim.horses[review.horse].name)
   ui.line(t,8,' Stake: '..review.stake..' credits')
   ui.line(t,10,' Total return if winner: '..review.returns)
   ui.line(t,11,' Includes your stake | 1 credit = 1 diamond')
   ui.button(t,13,'ENTER: PLACE BET',true,false)
   ui.line(t,17,' Backspace: back | Q: exit')
  else
   ui.line(t,3,snapshot.ok and (' '..tostring(snapshot.phase)..' | '..tostring(snapshot.seconds or 0)..'s'..(snapshot.paused and ' | PAUSED' or '')) or ' HOUSE OFFLINE - BETTING UNAVAILABLE',colors.yellow)
   for i,h in ipairs(sim.horses) do
    local returns=snapshot.payouts and snapshot.payouts[i][tostring(stakes[stakeIndex])]
    ui.button(t,4+(i-1)*3,i..' '..h.name..' | return '..tostring(returns or '--'),focus==i,horse==i)
   end
   ui.line(t,14,(focus==4 and '> ' or '  ')..'Stake: '..stakes[stakeIndex]..'  [Left/Right]',colors.white,focus==4 and colors.blue or colors.black)
   ui.button(t,15,snapshot.ticket and 'TICKET ACCEPTED' or 'REVIEW BET',focus==5,false)
   ui.line(t,18,' Tab/Arrows | Enter | R: retry | Q: exit')
  end
  local w,h=t.getSize(); ui.line(t,h,' '..status,colors.yellow)
 end
 local function activate()
  if not ui.usable(t) then return end
  if review then
   local now=ui.card()
   if not now or now.account~=review.account then status='Card changed. Bet not sent.'; review=nil; return end
   local r=client:mutate({op='bet',account=review.account,race=review.race,horse=review.horse,stake=review.stake})
   status=r.ok and 'Ticket accepted. Winnings reach your account.' or r.error; review=nil; refresh()
  elseif focus<=3 then horse=focus
  elseif focus==4 then stakeIndex=stakeIndex%3+1
  elseif snapshot.ok and snapshot.phase=='OPEN' and not snapshot.paused and account and balance and not snapshot.ticket then
   review={account=account,race=snapshot.id,horse=horse,stake=stakes[stakeIndex],returns=snapshot.payouts[horse][tostring(stakes[stakeIndex])]}
  else status='Bet unavailable: check card, host and race status.' end
 end
 draw()
 while true do
  local e,a,b,c=os.pullEvent()
  if e=='timer' and a==timer then refresh(); timer=os.startTimer(1)
  elseif e=='key' then
   if a==keys.q then return
   elseif a==keys.r then local r=client:retry(); status=r.ok and 'Request acknowledged' or r.error; refresh()
   elseif a==keys.backspace then review=nil
   elseif a==keys.enter then activate()
   elseif not review then
    if a==keys.tab or a==keys.down then focus=focus%5+1 elseif a==keys.up then focus=(focus-2)%5+1
    elseif a==keys.left then stakeIndex=(stakeIndex-2)%3+1 elseif a==keys.right then stakeIndex=stakeIndex%3+1 end
   end
  elseif e=='monitor_touch' or e=='mouse_click' then
   local y=c
   if review and y>=13 and y<=15 then activate()
   elseif not review then
    if y>=4 and y<=12 then focus=math.floor((y-4)/3)+1; activate()
    elseif y==14 then focus=4; activate()
    elseif y>=15 and y<=17 then focus=5; activate() end
   end
  end
  draw()
 end
end
return M
