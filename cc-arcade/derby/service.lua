local store=require('derby.store')
local ledger=require('derby.ledger')
local house=require('derby.house')
local inventory=require('derby.inventory')
local M={}
function M.new(storage,config,wrap)
 local s=storage:get()
 -- Reconstruct exact floating-point state instead of trusting JSON-rounded positions.
 if s.race and s.race.sim then
  local sim=require('derby.sim')
  assert(s.race.sim.version==sim.version,'Saved race requires its original simulation version')
  local restored=sim.new(s.race.seed)
  for _=1,s.race.sim.tick do sim.step(restored) end
  s.race.sim=restored
 end
 local api={}
 local function commit(nextState)
  storage:save(nextState); s=nextState
 end
 local function denied(message) return {ok=false,error=message} end
 function api:state() return store.copy(s) end
 function api:request(q,role,owner)
  if type(q)~='table' or type(q.op)~='string' then return denied('Invalid request') end
  if q.op=='snapshot' then return house.snapshot(s,q.account) end
  if q.op=='lookup' or q.op=='status' or q.op=='roundStatus' then return ledger.apply(s,q) end
  if role=='display' then return denied('Display is read only') end
  if type(q.id)~='string' or not q.id:match('^'..tostring(owner)..':') then return denied('Wrong transaction owner') end
  if q.op=='create' or q.op=='deposit' or q.op=='withdraw' then
   if role~='cashier' then return denied('Cashier operation') end
  elseif q.op~='bet' and q.op~='reserve' and q.op~='increase' and q.op~='settle' and q.op~='refund' then return denied('Operation not available remotely') end
  local nextState=store.copy(s)
  local request=store.copy(q); request.owner=tostring(owner)
  -- A repeated transfer must return its receipt without touching inventories again.
  local existed=nextState.transactions[request.id]~=nil
  local result=request.op=='bet' and house.bet(nextState,request) or ledger.apply(nextState,request)
  if not result.ok then return result end
  commit(nextState)
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
  if op=='pause' then n.paused=not n.paused
  elseif op=='cancel' then local r=house.cancel(n); if not r.ok then return r end
  elseif op=='fund' then
   if next(n.pending) then return denied('Reconcile pending transfer first') end
   local count=inventory.count(assert(wrap(config.bank)))
   if count<n.bank then return denied('Bank shortage: restore missing diamonds before continuing') end
   local r=ledger.apply(n,{op='fund',id='fund:'..tostring(os.epoch('utc')),amount=count}); if not r.ok then return r end
  elseif op=='reconcile' then
   local p=n.pending[id]; if not p then return denied('No such pending transfer') end
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
