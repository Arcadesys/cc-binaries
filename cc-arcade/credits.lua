-- Compatibility reads plus explicit, acknowledged house round transactions.
-- Disk files are identities only. No local balance is ever imported or written.
local config=require('derby.config')
local ui=require('derby.ui')
local M={}
local client
local bindings={}
-- Captured handles are updated from authoritative terms after a recovered raise.
local handles={}
local function remember(round)
 local refs=handles[round.round] or {}; handles[round.round]=refs; refs[round]=true
end
local function blocked(cli)
 local recovery=cli:localState().recovery
 if recovery then return {ok=false,pending=true,error='Round recovery must finish before another action',request=recovery.request} end
end
local function mutation(cli,q)
 local r=blocked(cli) or cli:mutate(q)
 return r,{pending=r.offline==true or r.pending==true,request=q}
end
local function demo()
 return not config.read() and (_G.ARCADE_DEV_MODE or (arcadeos and arcadeos.freeplay()))
end
local function network()
 if not client then client=require('derby.client').new() end
 return client
end
local function cardAt(path)
 if not path then return ui.card() end
 if path=='freeplay' and demo() then return {account='exhibition',path=path} end
 if not fs.exists(path..'/house-card.json') then return nil end
 local f=fs.open(path..'/house-card.json','r'); local ok,c=pcall(textutils.unserializeJSON,f.readAll()); f.close()
 if ok and type(c)=='table' then return {account=c.account,path=path} end
end
local function account(path)
 local bound=bindings[path or 'default']
 if bound then return bound end
 local c=cardAt(path); return c and c.account
end
local function checked(r)
 if not r.ok then error('HOUSE: '..tostring(r.error)..'. Funds remain at the host; use house station R to retry an unacknowledged request.',0) end
 return r
end
function M.findCards()
 if demo() then return {{path='freeplay',side='freeplay',name='EXHIBITION',credits=999}} end
 local cards={}
 for _,name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name)=='drive' then
   local path=disk.getMountPath(name); local c=path and cardAt(path)
   if c and c.account then
    local r=checked(network():read({op='lookup',account=c.account}))
    cards[#cards+1]={path=path,side=name,name=r.name,credits=r.balance,account=c.account}
   end
  end
 end
 return cards
end
function M.get(path)
 if demo() then return 999 end
 local id=account(path); if not id then return 0 end
 return checked(network():read({op='lookup',account=id})).balance
end
function M.getName(path)
 if demo() then return 'EXHIBITION' end
 local id=account(path); if not id then return nil end
 return checked(network():read({op='lookup',account=id})).name
end
function M.lock(path)
 local c=cardAt(path); assert(c and c.account,'Insert a house account card')
 bindings[path or 'default']=c.account; return true
end
function M.unlock(path) bindings[path or 'default']=nil end
function M.beginRound(game,stake,maximum,path)
 if demo() then return {demo=true,game=game,stake=stake,maximum=maximum,account='exhibition'} end
 local c=cardAt(path); if not c or not c.account then return nil,'Insert a house account card' end
 local cli=network(); local localState=cli:localState()
 local old=localState.rounds[c.account]
 -- A lost reservation reply may have been recovered from another house screen.
 if not old and localState.last and localState.last.result.ok then
  local q=localState.last.request
  if q.op=='reserve' and q.account==c.account then old={round=q.round} end
 end
 if old then
  local status=cli:read({op='roundStatus',round=old.round,account=c.account})
  if not status.ok or status.status=='open' then return nil,'Interrupted round '..old.round..': cashier must review/refund it' end
 end
 local id='arcade:'..os.getComputerID()..':'..(localState.counter+1)
 local q={op='reserve',account=c.account,game=game,stake=stake,maximum=maximum,round=id}
 local r,context=mutation(cli,q)
 if not r.ok then return nil,r.error,context end
 local round={account=c.account,round=id,game=game,stake=stake,maximum=maximum}
 localState=cli:localState(); localState.rounds[c.account]=round; cli:saveLocal(localState)
 bindings[path or 'default']=c.account; remember(round)
 return round
end
function M.increaseRound(round,stake,maximum)
 if round.demo then round.stake=round.stake+stake; round.maximum=maximum; return true end
 remember(round)
 local r,context=mutation(network(),{op='increase',round=round.round,account=round.account,stake=stake,maximum=maximum})
 if not r.ok then return false,r.error,context end
 round.stake=round.stake+stake; round.maximum=maximum
 local s=network():localState(); s.rounds[round.account]=round; network():saveLocal(s)
 return true
end
function M.settleRound(round,amount)
 if round.demo then return 999 end
 local r=checked((mutation(network(),{op='settle',round=round.round,account=round.account,amount=amount})))
 local s=network():localState(); s.rounds[round.account]=nil; network():saveLocal(s); handles[round.round]=nil
 return r.balance
end
function M.refundRound(round)
 if round.demo then return true end
 checked((mutation(network(),{op='refund',round=round.round,account=round.account})))
 local s=network():localState(); s.rounds[round.account]=nil; network():saveLocal(s); handles[round.round]=nil; return true
end
-- Return the original receipt identity as well as its result. Reconciliation is
-- persisted before its read can yield, so a missing status reply keeps all new
-- mutations blocked until retry completes, including after client recreation.
function M.retry()
 if demo() then return true,{ok=true} end
 local cli=network(); local s=cli:localState(); local r,q
 if s.recovery then r,q=s.recovery.result,s.recovery.request
 else
  r=cli:retry(); s=cli:localState(); q=s.pending or (s.last and s.last.request)
 end
 local context={request=q,pending=r.offline==true or r.pending==true}
 if not r.ok then return false,r.error,q and q.account,context end
 if q and (q.op=='reserve' or q.op=='increase') then
  s.recovery={request=q,result=r}; cli:saveLocal(s)
  local status=cli:read({op='roundStatus',round=q.round,account=q.account})
  local function integer(n) return type(n)=='number' and n>=0 and n%1==0 and n<=1000000000 end
  if not status.ok or not integer(status.stake) or not integer(status.maximum) or status.maximum<status.stake then
   context.pending=true
   return false,status.error or 'House did not return authoritative round terms',q.account,context
  end
  context.status=status.status
  local saved=s.rounds[q.account]
  if saved and saved.round~=q.round then
   context.pending=true; return false,'A different account round requires cashier review',q.account,context
  end
  local game=(saved and saved.game) or q.game
  local round={account=q.account,round=q.round,game=game,stake=status.stake,maximum=status.maximum}
  for handle in pairs(handles[q.round] or {}) do
   if handle.account==q.account then handle.stake=status.stake; handle.maximum=status.maximum end
  end
  context.round=round
  if status.status=='open' then s.rounds[q.account]=round
  elseif status.status=='settled' or status.status=='refunded' then
   -- The increase receipt predates an operator refund/settlement. Read this
   -- explicit account, never the card path or that stale receipt balance.
   local balance=cli:read({op='lookup',account=q.account})
   local amount=balance.balance
   local validBalance=type(amount)=='number' and amount>=0 and amount<math.huge and amount%1==0
   if not balance.ok or not validBalance then
    context.pending=true; return false,balance.error or 'House balance unavailable',q.account,context
   end
   context.balance=balance.balance; s.rounds[q.account]=nil; handles[q.round]=nil
  else context.pending=true; return false,'Unknown host round status',q.account,context end
  s.recovery=nil; cli:saveLocal(s)
  if status.status~='open' then return false,'Round '..status.status..'; the interrupted hand cannot continue',q.account,context end
 elseif q and (q.op=='settle' or q.op=='refund') then
  if s.rounds[q.account] and s.rounds[q.account].round==q.round then s.rounds[q.account]=nil; cli:saveLocal(s) end
  handles[q.round]=nil
 end
 return true,r,q and q.account,context
end
-- Unchecked edits must fail loudly if a forgotten consumer tries the old API.
function M.set() error('HOUSE: local balance editing is retired',0) end
function M.add() error('HOUSE: use settleRound with an acknowledged reservation',0) end
function M.remove() error('HOUSE: use beginRound with a maximum return',0) end
function M.setName() error('HOUSE: account names belong to the host',0) end
return M
