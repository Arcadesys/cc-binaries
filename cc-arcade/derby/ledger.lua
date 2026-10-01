-- All money is integer credits, backed one-for-one by diamonds in the bank.
local M={}
local function canonical(v)
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 local keys={}; for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={}; for _,k in ipairs(keys) do out[#out+1]=canonical(k)..'='..canonical(v[k]) end
 return '{'..table.concat(out,';')..'}'
end
function M.new() return {version=1,bank=0,accounts={},rounds={},transactions={},nextAccount=0,pending={}} end
local function integer(n) return type(n)=='number' and n==n and n>=0 and n%1==0 and n<=1000000000 end
function M.liability(s)
 local n=0
 for _,a in pairs(s.accounts) do n=n+a.balance end
 for _,r in pairs(s.rounds) do if r.status=='open' then n=n+r.maximum end end
 for _,p in pairs(s.pending) do if p.kind=='withdraw' then n=n+p.amount end end
 return n
end
function M.available(s) return s.bank-M.liability(s) end
function M.apply(s,q)
 local function fail(message) return {ok=false,error=message} end
 if type(q)~='table' or type(q.op)~='string' then return fail('Invalid request') end
 if q.op=='lookup' then
  local a=s.accounts[q.account]
  if not a then return fail('Insert a new house account card') end
  return {ok=true,balance=a.balance,name=a.name,account=q.account}
 elseif q.op=='roundStatus' then
  local r=s.rounds[q.round]; if not r or r.account~=q.account then return fail('Unknown round') end
  -- Additive v1 fields let interrupted clients recover the actual reserved terms.
  return {ok=true,status=r.status,paid=r.paid,stake=r.stake,maximum=r.maximum}
 elseif q.op=='status' then return s.transactions[q.id] and s.transactions[q.id].result or fail('Unknown transaction') end
 if type(q.id)~='string' or #q.id>160 then return fail('Transaction ID required') end
 -- The transport serialises a stable request and rejects reuse with different content.
 local fingerprint=canonical(q)
 if s.transactions[q.id] then
  if s.transactions[q.id].fingerprint~=fingerprint then return fail('Transaction ID reused with different request') end
  return s.transactions[q.id].result
 end
 local result
 local a=q.account and s.accounts[q.account]
 if q.op=='create' then
  s.nextAccount=s.nextAccount+1
  local id='house-'..s.nextAccount
  s.accounts[id]={name=tostring(q.name or 'Guest'):sub(1,24),balance=0}
  result={ok=true,account=id,balance=0}
 elseif q.op=='fund' then
  if not integer(q.amount) or q.amount<M.liability(s) then return fail('Bank cannot cover outstanding balances and reservations') end
  s.bank=q.amount; result={ok=true,bank=s.bank}
 elseif not a then return fail('Unknown account')
 elseif next(s.pending) then return fail('Cashier transfer requires reconciliation')
 elseif q.op=='reserve' then
  if not integer(q.stake) or not integer(q.maximum) or q.maximum<q.stake then return fail('Invalid stake or maximum return') end
  if a.balance<q.stake then return fail('Not enough credits') end
  if M.available(s)+q.stake<q.maximum then return fail('House reserve cannot cover this round') end
  if s.rounds[q.round] then return fail('Round already exists') end
  if type(q.round)~='string' or type(q.game)~='string' then return fail('Round and game required') end
  a.balance=a.balance-q.stake
  s.rounds[q.round]={account=q.account,stake=q.stake,maximum=q.maximum,status='open',game=q.game,owner=q.owner}
  result={ok=true,round=q.round,balance=a.balance}
 elseif q.op=='increase' then
  local r=s.rounds[q.round]
  if not r or r.status~='open' or r.account~=q.account or r.owner~=q.owner then return fail('Round unavailable') end
  if not integer(q.stake) or not integer(q.maximum) or q.maximum<r.maximum or q.maximum<r.stake+q.stake then return fail('Invalid increase') end
  if a.balance<q.stake or M.available(s)+r.maximum+q.stake<q.maximum then return fail('Insufficient credits or house reserve') end
  a.balance=a.balance-q.stake; r.stake=r.stake+q.stake; r.maximum=q.maximum
  result={ok=true,balance=a.balance}
 elseif q.op=='settle' or q.op=='refund' then
  local r=s.rounds[q.round]
  if not r or r.account~=q.account or r.owner~=q.owner then return fail('Round unavailable') end
  local amount=q.op=='refund' and r.stake or q.amount
  if not integer(amount) or amount>r.maximum then return fail('Return exceeds reservation') end
  if r.status~='open' then return fail('Round already settled') end
  r.status=q.op=='refund' and 'refunded' or 'settled'; r.paid=amount; a.balance=a.balance+amount
  result={ok=true,balance=a.balance,paid=amount}
 elseif q.op=='deposit' or q.op=='withdraw' then
  if not integer(q.amount) or q.amount<1 then return fail('Positive whole diamond amount required') end
  if q.op=='withdraw' and a.balance<q.amount then return fail('Not enough credits') end
  if q.op=='withdraw' then a.balance=a.balance-q.amount end
  s.pending[q.id]={kind=q.op,account=q.account,amount=q.amount,beforeBank=s.bank}
  result={ok=true,pending=true,id=q.id}
 else return fail('Unknown operation') end
 s.transactions[q.id]={fingerprint=fingerprint,result=result}
 return result
end
function M.complete(s,id,moved)
 local p=s.pending[id]
 assert(p,'No pending transfer')
 assert(integer(moved) and moved<=p.amount,'Invalid transferred count')
 local a=s.accounts[p.account]
 if p.kind=='deposit' then s.bank=s.bank+moved; a.balance=a.balance+moved
 else s.bank=s.bank-moved; a.balance=a.balance+p.amount-moved end
 local result={ok=true,moved=moved,balance=a.balance,id=id}
 s.transactions[id].result=result; s.pending[id]=nil
 assert(M.available(s)>=0,'Unbacked ledger')
 return result
end
return M
