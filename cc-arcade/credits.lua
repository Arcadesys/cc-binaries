-- Compatibility reads plus explicit, acknowledged house round transactions.
-- Disk files are identities only. No local balance is ever imported or written.
local config=require('derby.config')
local ui=require('derby.ui')
local M={}
local client
local bindings={}
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
 local r=cli:mutate({op='reserve',account=c.account,game=game,stake=stake,maximum=maximum,round=id})
 if not r.ok then return nil,r.error end
 local round={account=c.account,round=id,game=game,stake=stake,maximum=maximum}
 localState=cli:localState(); localState.rounds[c.account]=round; cli:saveLocal(localState)
 bindings[path or 'default']=c.account
 return round
end
function M.increaseRound(round,stake,maximum)
 if round.demo then round.stake=round.stake+stake; round.maximum=maximum; return true end
 local r=network():mutate({op='increase',round=round.round,account=round.account,stake=stake,maximum=maximum})
 if not r.ok then return false,r.error end
 round.stake=round.stake+stake; round.maximum=maximum
 local s=network():localState(); s.rounds[round.account]=round; network():saveLocal(s)
 return true
end
function M.settleRound(round,amount)
 if round.demo then return 999 end
 local r=checked(network():mutate({op='settle',round=round.round,account=round.account,amount=amount}))
 local s=network():localState(); s.rounds[round.account]=nil; network():saveLocal(s)
 return r.balance
end
function M.refundRound(round)
 if round.demo then return true end
 checked(network():mutate({op='refund',round=round.round,account=round.account}))
 local s=network():localState(); s.rounds[round.account]=nil; network():saveLocal(s); return true
end
-- Unchecked edits must fail loudly if a forgotten consumer tries the old API.
function M.set() error('HOUSE: local balance editing is retired',0) end
function M.add() error('HOUSE: use settleRound with an acknowledged reservation',0) end
function M.remove() error('HOUSE: use beginRound with a maximum return',0) end
function M.setName() error('HOUSE: account names belong to the host',0) end
return M
