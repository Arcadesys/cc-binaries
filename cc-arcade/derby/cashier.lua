local ui=require('derby.ui')
local M={}
function M.run(client,t)
 local amounts={5,10,20,64}; local index=1; local status=''; local review
 local card,balance
 local function refresh()
  card=ui.card(); balance=nil
  if card and card.account then local r=client:read({op='lookup',account=card.account}); balance=r.ok and r.balance or nil; if not r.ok then status=r.error end end
 end
 local function draw()
  if not ui.usable(t) then return end
  ui.clear(t,'DIAMOND CASHIER')
  ui.line(t,3,' 1 diamond = 1 credit',colors.yellow)
  ui.line(t,5,' '..(card and (card.account or 'New card - issue an account') or 'Insert a floppy disk'))
  ui.line(t,6,' Balance: '..tostring(balance or 'UNAVAILABLE'))
  if review then
   ui.line(t,8,' '..review.op:upper()..' '..review.amount..' DIAMONDS',colors.yellow)
   ui.button(t,10,'ENTER: CONFIRM',true,false)
   ui.line(t,14,' Backspace: cancel')
  else
   ui.line(t,8,' Amount: '..amounts[index]..'  [Left/Right]',colors.yellow)
   ui.button(t,9,'[D] DEPOSIT from intake chest',false,false)
   ui.button(t,12,'[W] WITHDRAW to output chest',false,false)
   ui.line(t,16,' [N] Issue new card | [R] Retry request')
  end
  ui.line(t,18,' [Q] Exit | Empty output after withdrawal')
  local _,h=t.getSize(); ui.line(t,h,' '..status,colors.yellow)
 end
 local function create()
  if not ui.usable(t) then return end
  refresh()
  if not card or card.account then status='Insert a disk without a house account'; return end
  local original=card
  local r=client:mutate({op='create',name='Guest'})
  if r.ok then
   local current=ui.card()
   if current and current.diskID==original.diskID and current.path==original.path then
    local f=assert(fs.open(current.path..'/house-card.json','w')); f.write(textutils.serializeJSON({account=r.account})); f.close()
    status='New account issued at zero. Old files preserved.'
   else status='Card removed. New account is empty; issue again.' end
  else status=r.error end
  refresh()
 end
 local function choose(op)
  if not ui.usable(t) then return end
  refresh()
  if card and card.account and balance then review={op=op,account=card.account,amount=amounts[index]} else status='Insert an issued card and connect to house' end
 end
 local function confirm()
  if not ui.usable(t) then return end
  if not review then return end
  local current=ui.card()
  if not current or current.account~=review.account then status='Card changed. Transfer not sent.'; review=nil; return end
  local r=client:mutate(review)
  status=r.ok and ('Transferred '..tostring(r.moved or 0)..' diamonds') or r.error
  review=nil; refresh()
 end
 refresh(); draw(); local timer=os.startTimer(1)
 while true do
  local e,a,b,c=os.pullEvent()
  if e=='timer' and a==timer then refresh(); timer=os.startTimer(1)
  elseif e=='key' then
   if a==keys.q then return elseif a==keys.backspace then review=nil
   elseif a==keys.enter then confirm()
   elseif a==keys.r then local r=client:retry(); status=r.ok and 'Request acknowledged; check balance' or r.error; refresh()
   elseif not review then
    if a==keys.left then index=(index-2)%#amounts+1 elseif a==keys.right then index=index%#amounts+1
    elseif a==keys.n then create() elseif a==keys.d then choose('deposit') elseif a==keys.w then choose('withdraw') end
   end
  elseif e=='monitor_touch' or e=='mouse_click' then
   if review and c>=10 and c<=12 then confirm()
   elseif not review then
    if c==8 then index=index%#amounts+1 elseif c>=9 and c<=11 then choose('deposit') elseif c>=12 and c<=14 then choose('withdraw') end
   end
  end
  draw()
 end
end
return M
