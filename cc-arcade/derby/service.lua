local store=require('derby.store')
local ledger=require('derby.ledger')
local house=require('derby.house')
local inventory=require('derby.inventory')
local currency=require('derby.currency')
local M={}
function M.new(storage,config,wrap)
 local s=storage:get()
 assert(s.version==1 or s.version==2,'Unsupported saved ledger version; restore compatible runtime/state offline')
 -- Reconstruct exact floating-point state instead of trusting JSON-rounded positions.
 if s.race and s.race.sim then
  local sim=require('derby.sim')
  assert(s.race.sim.version==sim.version,'Saved race requires its original simulation version')
  local restored=sim.new(s.race.seed)
  for _=1,s.race.sim.tick do sim.step(restored) end
  s.race.sim=restored
 end
 if s.version==2 then
  assert(config.bank~=config.intake and config.bank~=config.payout and config.intake~=config.payout,'Currency inventories must be distinct')
  currency.validate(s.currency)
  assert(s.bank==currency.value(s.currency,s.stock),'Saved currency stock/value mismatch')
  assert(ledger.available(s)>=0,'Saved currency ledger is unbacked')
 end
 local api={}
 local function stock(name) return inventory.stock(assert(wrap(name),'Inventory unavailable: '..tostring(name)),s.currency) end
 local function same(a,b) return currency.canonical(a)==currency.canonical(b) end
 local function observations()
  return {bank=stock(config.bank),intake=stock(config.intake),payout=stock(config.payout)}
 end
 local function verifiedMovement(p,moved)
  local now=observations(); local expected=store.copy(p.observed)
  local source=p.kind=='deposit' and 'intake' or 'bank'
  local dest=p.kind=='deposit' and 'bank' or 'payout'
  expected[source][p.entryId]=(expected[source][p.entryId] or 0)-moved
  expected[dest][p.entryId]=(expected[dest][p.entryId] or 0)+moved
  assert(same(now,expected),'Classified inventory deltas differ; isolate inventories and reconcile')
 end
 local function commit(nextState)
  storage:save(nextState); s=nextState
 end
 local function denied(message) return {ok=false,error=message} end
 function api:state() return store.copy(s) end
 function api:request(q,role,owner)
  if type(q)~='table' or type(q.op)~='string' then return denied('Invalid request') end
  if q.op=='currency' then return {ok=true,apiVersion=s.version,policy=s.version==2 and store.copy(s.currency) or nil} end
  if q.op=='snapshot' then return house.snapshot(s,q.account) end
  if q.op=='lookup' or q.op=='status' or q.op=='roundStatus' then return ledger.apply(s,q) end
  if role=='display' then return denied('Display is read only') end
  if type(q.id)~='string' or not q.id:match('^'..tostring(owner)..':') then return denied('Wrong transaction owner') end
  if q.op=='create' or q.op=='deposit' or q.op=='withdraw' or q.op=='exchange' then
   if role~='cashier' then return denied('Cashier operation') end
  elseif q.op~='bet' and q.op~='reserve' and q.op~='increase' and q.op~='settle' and q.op~='refund' then return denied('Operation not available remotely') end
  local nextState=store.copy(s)
  local request=store.copy(q); request.owner=tostring(owner)
  -- A repeated transfer must return its receipt without touching inventories again.
  local existed=nextState.transactions[request.id]~=nil
  local observed
  if request.op=='exchange' and not existed then
   if s.version~=2 then return denied('Migrate host currency before using API 2') end
   local ok,value=pcall(observations)
   if not ok then return denied('Cannot classify inventories: '..tostring(value)) end
   observed=value
   if not same(observed.bank,s.stock) then return denied('Classified bank stock differs; reconcile before transfer') end
  end
  local result=request.op=='bet' and house.bet(nextState,request) or ledger.apply(nextState,request)
  if not result.ok then return result end
  if observed and result.pending then
   local p=nextState.pending[q.id]; p.observed=observed
   p.source=q.direction=='deposit' and config.intake or config.bank
   p.destination=q.direction=='deposit' and config.bank or config.payout
  end
  commit(nextState)
  if q.op=='exchange' and not existed then
   local p=s.pending[q.id]
   local ok,moved=pcall(function()
    assert(same(observations(),p.observed),'Inventories changed since durable intent')
    local count=inventory.move(assert(wrap(p.source)),p.destination,p.requestedItems,p.entry)
    verifiedMovement(p,count)
    return count
   end)
   if not ok then return {ok=false,pending=true,error='Transfer uncertain; operator reconciliation required: '..tostring(moved)} end
   nextState=store.copy(s); local receipt=ledger.complete(nextState,q.id,moved); commit(nextState); return receipt
  end
  if (q.op=='deposit' or q.op=='withdraw') and not existed then
   -- Intent is durable before either physical side effect.
   local ok,moved=pcall(function()
    local bank=assert(wrap(config.bank),'Bank unavailable')
    assert(inventory.count(bank)==s.bank,'Bank count differs from ledger; reconcile before transfer')
    if q.op=='deposit' then return inventory.move(assert(wrap(config.intake)),config.bank,q.amount) end
    return inventory.move(bank,config.payout,q.amount)
   end)
   if not ok then return denied('Transfer uncertain; operator reconciliation required: '..tostring(moved)) end
   nextState=store.copy(s)
   local receipt=ledger.complete(nextState,q.id,moved)
   commit(nextState)
   return receipt
  end
  return result
 end
 function api:tick(seed)
  local n=store.copy(s); house.tick(n,seed)
  -- Save every second and every phase boundary. Replayed sub-second steps use the saved RNG.
  local boundary=not s.race or (n.race and n.race.phase~=s.race.phase)
  if boundary or (n.race and n.race.elapsed%10==0) then commit(n) else s=n end
 end
 function api:operator(op,id,amount)
  local n=store.copy(s)
  if op=='currency' then
   if config.bank==config.intake or config.bank==config.payout or config.intake==config.payout then return denied('Currency inventories must be distinct') end
   if not s.paused or next(s.pending) then return denied('Pause host and reconcile pending transfers first') end
   local policy=config.currency or currency.default()
   local ok,value=pcall(function()
    currency.validate(policy)
    local bank=assert(wrap(config.bank))
    if s.version==1 then assert(inventory.count(bank)==s.bank,'Legacy bank count differs; reconcile before migration') end
    return ledger.changeCurrency(s,policy,inventory.stock(bank,policy))
   end)
   if not ok then return denied(tostring(value)) end
   storage:changeCurrency(value); s=value; return {ok=true}
  elseif op=='pause' then n.paused=not n.paused
  elseif op=='cancel' then local r=house.cancel(n); if not r.ok then return r end
  elseif op=='fund' then
   if next(n.pending) then return denied('Reconcile pending transfer first') end
   if s.version==2 then
    local classified=stock(config.bank)
    for key,count in pairs(s.stock) do if (classified[key] or 0)<count then return denied('Bank item shortage; restore missing stock') end end
    n.stock=classified; n.bank=currency.value(s.currency,classified)
    if n.bank>1000000000 then return denied('Bank value exceeds supported credit limit') end
    if ledger.available(n)<0 then return denied('Bank cannot cover liabilities') end
    commit(n); return {ok=true}
   end
   local count=inventory.count(assert(wrap(config.bank)))
   if count<n.bank then return denied('Bank shortage: restore missing diamonds before continuing') end
   local r=ledger.apply(n,{op='fund',id='fund:'..tostring(os.epoch('utc')),amount=count}); if not r.ok then return r end
  elseif op=='reconcile' then
   local p=n.pending[id]; if not p then return denied('No such pending transfer') end
   if s.version==2 then
    if type(amount)~='number' or amount%1~=0 or amount<0 or amount>p.requestedItems then return denied('Invalid moved item count') end
    if p.source~=(p.kind=='deposit' and config.intake or config.bank) or p.destination~=(p.kind=='deposit' and config.bank or config.payout) then return denied('Restore original inventory configuration before reconciliation') end
    local ok,err=pcall(verifiedMovement,p,amount); if not ok then return denied(tostring(err)) end
    ledger.complete(n,id,amount); commit(n); return {ok=true}
   end
   if type(amount)~='number' or amount%1~=0 or amount<0 or amount>p.amount then return denied('Invalid moved amount') end
   local expected=p.beforeBank+(p.kind=='deposit' and amount or -amount)
   if inventory.count(assert(wrap(config.bank)))~=expected then return denied('Count does not match bank; inspect intake/output and restore consistency') end
   ledger.complete(n,id,amount)
  elseif op=='refund' then
   local r=n.rounds[id]
   if not r or r.status~='open' or r.game=='derby' then return denied('No interrupted arcade round with this ID') end
   local result=ledger.apply(n,{op='refund',id='operator-refund:'..id,round=id,account=r.account,owner=r.owner})
   if not result.ok then return result end
  else return denied('Unknown operator action') end
  commit(n); return {ok=true}
 end
 return api
end
return M
