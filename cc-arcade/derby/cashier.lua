local ui=require('derby.ui')
local currency=require('derby.currency')
local M={}
local slots=require('derby.cage').slots
function M.run(client,t)
 local amounts={5,10,20,64}; local index=1; local status=''; local review
 local card,balance,anim
 local cage
 local policy,entries,selected=nil,{},1
 local apiVersion
 local reviewItem,reviewUnits,reviewBalance
 local function refresh()
  local info=client:read({op='currency'})
  apiVersion=info.ok and info.apiVersion or nil
  policy=info.ok and info.apiVersion==2 and info.policy or nil
  entries={}
  if policy then for id,e in pairs(policy.entries) do if e.depositEnabled or e.redeemEnabled then entries[#entries+1]=id end end; table.sort(entries) end
  if selected>#entries then selected=1 end
  card=ui.card(); balance=nil
  if card and card.account then local r=client:read({op='lookup',account=card.account}); balance=r.ok and r.balance or nil; if not r.ok then status=r.error end end
 end
 local function draw()
  if not ui.usable(t) then return end
  cage=cage or require('derby.cage').new(t)
  local now=os.epoch('utc')/1000
  local dx,hide=0,false
  if anim then
   local u=(now-anim.t0)/anim.dur
   if u>=1 then anim=nil
   else dx=(anim.op=='deposit' and u or 1-u)*7.5; hide=anim.op=='deposit' and u>.85 end
  end
  local entry=policy and policy.entries[entries[selected]]
  local v={balance=balance,count=review and (review.amount or review.requestedItems) or amounts[index],dx=dx,hidePile=hide,status=status,
   info=(card and (card.account or 'New card: issue an account') or 'Insert a floppy disk')..'  |  Balance: '..tostring(balance or 'UNAVAILABLE')}
  if review then
   if review.op=='exchange' then
    v.prompt=review.direction:upper()..' '..review.requestedItems..' '..reviewItem..'?'
    v.hint=reviewUnits..' credits; balance '..reviewBalance..'  Enter: confirm  Backspace: cancel'
   else v.prompt=review.op:upper()..' '..review.amount..' DIAMONDS?'; v.hint='Enter: confirm  Backspace: cancel' end
   v.options={'CONFIRM','','CANCEL'}
  else
   v.prompt=(entry and (entry.itemId..' = '..entry.unitsPerItem..' credits [Up/Down]  ') or '')..'Amount: '..amounts[index]..'  [Left/Right]'
   v.hint='[N] New card  [R] Retry  [Q] Exit'
   v.options={'DEPOSIT',tostring(amounts[index]),'WITHDRAW'}
  end
  cage:draw(v)
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
  if apiVersion~=1 and apiVersion~=2 then status='Currency policy unavailable; retry when connected'; return end
  if not (card and card.account and balance) then status='Insert an issued card and connect to house'; return end
  if policy then
   local id=entries[selected]; local e=id and policy.entries[id]
   local direction=op=='deposit' and 'deposit' or 'redeem'
   if not e or not e[direction=='deposit' and 'depositEnabled' or 'redeemEnabled'] then status='This item is disabled for '..direction; return end
   local ok,units=pcall(currency.quote,e,amounts[index],policy)
   if not ok then status='Choose fewer items; configured transfer limit exceeded'; return end
   reviewItem=e.itemId; reviewUnits=units; reviewBalance=balance+(direction=='deposit' and reviewUnits or -reviewUnits)
   review={op='exchange',apiVersion=2,account=card.account,direction=direction,entryId=id,
    requestedItems=amounts[index],policyId=policy.policyId,policyRevision=policy.revision}
  else review={op=op,account=card.account,amount=amounts[index]} end
 end
 local function confirm()
  if not ui.usable(t) then return end
  if not review then return end
  local current=ui.card()
  if not current or current.account~=review.account then status='Card changed. Transfer not sent.'; review=nil; return end
  local r=client:mutate(review)
  status=r.ok and ('Transferred '..tostring(r.confirmedItems or r.moved or 0)..' items; balance '..tostring(r.balance)) or r.error
  if r.ok and (r.confirmedItems or r.moved or 1)>0 then anim={op=(review.op=='exchange' and review.direction=='redeem') and 'withdraw' or (review.op=='exchange' and 'deposit' or review.op),t0=os.epoch('utc')/1000,dur=.9} end
  review=nil; refresh()
 end
 refresh(); draw(); local timer=os.startTimer(.1); local ticks=0
 while true do
  local e,a,b,c=os.pullEvent()
  if e=='timer' and a==timer then ticks=ticks+1; if ticks%10==0 then refresh() end; timer=os.startTimer(.1)
  elseif e=='key' then
   if a==keys.q then return elseif a==keys.backspace then review=nil
   elseif a==keys.enter then confirm()
   elseif a==keys.r then local r=client:retry(); status=r.ok and 'Request acknowledged; check balance' or r.error; refresh()
   elseif not review then
    if policy and #entries>0 and a==keys.up then selected=(selected-2)%#entries+1 elseif policy and #entries>0 and a==keys.down then selected=selected%#entries+1 elseif a==keys.left then index=(index-2)%#amounts+1 elseif a==keys.right then index=index%#amounts+1
    elseif a==keys.n then create() elseif a==keys.d then choose('deposit') elseif a==keys.w then choose('withdraw') end
   end
  elseif e=='monitor_touch' or e=='mouse_click' then
   local w,h=t.getSize()
   if c>=h-1 then
    local slot; for i,s in ipairs(slots(w)) do if b>=s.x1 and b<=s.x2 then slot=i end end
    if review then if slot==1 then confirm() elseif slot==3 then review=nil end
    elseif slot==1 then choose('deposit') elseif slot==2 then index=index%#amounts+1 elseif slot==3 then choose('withdraw') end
   end
  end
  draw()
 end
end
return M
