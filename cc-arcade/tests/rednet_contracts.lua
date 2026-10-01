-- Execute with: python3 cc-arcade/tools/test_contracts.py (from repository root).
-- All diamonds/accounts below are fictional, isolated fixtures; no live peripherals.
local Hub=require('tests.support.hub')
local contract=require('tests.contracts.house_v1')
local assertions,scenarios=0,0
local function check(v,msg) assertions=assertions+1; assert(v,msg) end
local function eq(a,b,msg) check(a==b,(msg or '')..': expected '..tostring(b)..', got '..tostring(a)) end
local function test(name,fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then error('FAIL '..name..'\n'..err,0) end
 scenarios=scenarios+1; print('PASS '..name)
end
local function setup(id)
 local h=Hub.new(); return h,h:client(id or 3)
end
local function reserve(round,stake,maximum)
 return {op='reserve',account='house-1',game='fixture',round=round or 'round-1',stake=stake or 5,maximum=maximum or 20}
end
local function response(q,r) check(contract.validateResponse(q,r),'Response violates v1 contract for '..q.op) end
local function balance(h) return h:state().accounts['house-1'].balance end
local function sane(h)
 local s=h:state(); local liability=0
 for _,account in pairs(s.accounts) do check(account.balance>=0 and account.balance%1==0,'Whole nonnegative account balance'); liability=liability+account.balance end
 for _,round in pairs(s.rounds) do if round.status=='open' then liability=liability+round.maximum end end
 for _,pending in pairs(s.pending) do if pending.kind=='withdraw' then liability=liability+pending.amount end end
 check(s.bank-liability>=0,'Independently summed liabilities remain backed')
 eq(h.host.require('derby.ledger').available(s),s.bank-liability,'Production availability matches independent sum')
 eq(s.bank,h.inventories.bank.count,'Virtual inventory matches durable bank')
end

test('canonical v1 fixture corpus',function()
 for _,case in ipairs(contract.validRequests) do check(contract.validateRequest(case.request),case.name) end
 for _,case in ipairs(contract.malformedRequests) do check(not contract.validateRequest(case.request),case.name) end
 for _,case in ipairs(contract.validResponses) do check(contract.validateResponse(case.request,case.response),case.name) end
 for _,case in ipairs(contract.malformedResponses) do check(not contract.validateResponse(case.request,case.response),case.name) end
 for _,group in ipairs({{contract.validEnvelopes,true},{contract.malformedEnvelopes,false}}) do
  for _,case in ipairs(group[1]) do
   local valid
   if case.direction=='request' then valid=contract.validateRequestEnvelope(case.envelope)
   else valid=contract.validateResponseEnvelope(case.envelope,case.request,case.token) end
   eq(valid,group[2],case.name)
  end
 end
end)
test('canonical requests execute across actual client and server',function()
 local function same(actual,expected,path)
  if type(expected)~='table' then eq(actual,expected,path); return end
  check(type(actual)=='table',path..' table')
  for k,v in pairs(expected) do same(actual[k],v,path..'.'..tostring(k)) end
  for k in pairs(actual) do check(expected[k]~=nil,path..' unexpected field '..tostring(k)) end
 end
 local wire,direct=0,0
 for _,cases in ipairs({contract.validRequests,contract.malformedRequests,contract.authorizationCases,contract.stateRejections}) do
  for _,case in ipairs(cases) do
   local h=Hub.new(); local state=contract.fixtureState(case.context)
   h.host.require('derby.store').open('/house-bank/state',{}):save(state)
   h.inventories.bank.count=state.bank; h:restartHost()
   h.roles[tostring(case.owner)]=case.role
   local c=h:client(case.owner)
   local serializable=pcall(c.platform.textutils.serializeJSON,case.request)
   local result
   if serializable then result=h:call(c,'read',case.request); wire=wire+1
   else
    -- NaN/infinity are Lua-level negative cases, not valid JSON wire packets.
    local db=h.host.require('derby.store').open('/house-bank/state',{})
    local host=h.host.require('derby.service').new(db,{},function() error('No transfer expected') end)
    result=host:request(case.request,case.role,case.owner); direct=direct+1
   end
   same(result,case.expected,case.name)
   if case.expected.ok==false then same(h:state(),state,case.name..' rejected request leaves state unchanged') end
   local createdNames={['create named account']='NEW PLAYER',['create default guest']='Guest',
    ['create coerces numeric name']='123',['create false name selects Guest']='Guest',
    ['create long name is truncated']='ABCDEFGHIJKLMNOPQRSTUVWX'}
   if createdNames[case.name] then eq(h:state().accounts[result.account].name,createdNames[case.name],'Persisted name: '..case.name) end
  end
 end
 check(wire>100,'Canonical corpus exercises more than 100 real wire exchanges')
 check(direct>0,'Non-JSON numeric cases also exercised at service boundary')
end)
test('real v1 client to real v1 server reads',function()
 local h,c=setup(); eq(c.require('derby.client').protocol,contract.protocol,'Protocol')
 for _,q in ipairs({{op='snapshot'},{op='lookup',account='house-1'},{op='status',id='missing'},{op='roundStatus',account='house-1',round='missing'}}) do
  local r=h:call(c,'read',q); response(q,r)
 end
 check(not c.client:localState().pending,'Reads do not create pending mutations')
 eq(h.trace[1].message.request.op,'snapshot','Actual envelope'); check(type(h.trace[1].message.token)=='string','String correlation token')
end)
test('request response schema across full round lifecycle',function()
 local h,c=setup()
 local requests={reserve(),{op='increase',account='house-1',round='round-1',stake=5,maximum=30},
  {op='roundStatus',account='house-1',round='round-1'}, {op='settle',account='house-1',round='round-1',amount=25}}
 for _,q in ipairs(requests) do local r=h:call(c,q.op=='roundStatus' and 'read' or 'mutate',q); check(r.ok,q.op); response(q,r) end
 eq(balance(h),115,'Captured stake and return'); sane(h)
end)
test('refund returns the reserved stake once',function()
 local h,c=setup(); check(h:call(c,'mutate',reserve()).ok,'Reserve')
 check(h:call(c,'mutate',{op='refund',account='house-1',round='round-1'}).ok,'Refund')
 local r=h:call(c,'mutate',{op='refund',account='house-1',round='round-1'})
 check(not r.ok,'Second refund denied'); eq(balance(h),100,'No duplicate credit'); sane(h)
end)
for _,kind in ipairs({'sender','protocol','token','body','result'}) do
 test('client ignores wrong '..kind..' before valid reply',function()
  local h,c=setup()
  h.hook=function(p)
   if p.from~=1 then return end
   local bad={from=p.from,to=p.to,protocol=p.protocol,message={token=p.message.token,result={ok=true,balance=999999}}}
   if kind=='sender' then bad.from=99 elseif kind=='protocol' then bad.protocol='pine-house-v2'
   elseif kind=='token' then bad.message.token='stale' elseif kind=='body' then bad.message='garbage'
   else bad.message.result='garbage' end
   return {bad,p}
  end
  eq(h:call(c,'read',{op='lookup',account='house-1'}).balance,100,'Only correlated reply accepted')
 end)
end
for _,kind in ipairs({'protocol','body','token'}) do
 test('server ignores incompatible '..kind..' envelope',function()
  local h,c=setup()
  h.hook=function(p)
   if p.from==1 then return end
   if kind=='protocol' then p.protocol='pine-house-v2' elseif kind=='body' then p.message='garbage' else p.message.token=123 end
   return {p}
  end
  local r=h:call(c,'mutate',reserve()); check(r.offline,'Clean timeout for unsupported envelope'); eq(balance(h),100,'No mutation')
 end)
end
test('unregistered client is denied',function()
 local h,c=setup(99); local r=h:call(c,'mutate',reserve())
 check(not r.ok and r.error:find('not registered',1,true),'Unregistered rejection'); eq(balance(h),100,'Balance unchanged')
end)
test('display is read only and station cannot create account',function()
 local h,c=setup(5); check(h:call(c,'read',{op='snapshot'}).ok,'Display reads')
 check(not h:call(c,'mutate',reserve()).ok,'Display cannot reserve')
 c=h:client(3); check(not h:call(c,'mutate',{op='create',name='Guest'}).ok,'Station cannot issue accounts')
 eq(h:state().nextAccount,1,'No extra account')
end)
test('transaction owner and round owner are independently enforced',function()
 local h,c=setup(); check(not h:call(c,'read',{op='reserve',id='4:1',account='house-1',round='r',game='fixture',stake=5,maximum=20}).ok,'Wrong transaction owner')
 local q=reserve(); q.owner='4'; check(h:call(c,'mutate',q).ok,'Caller owner is replaced')
 eq(h:state().rounds['round-1'].owner,'3','Sender owns round')
 local other=h:client(4); check(not h:call(other,'mutate',{op='settle',account='house-1',round='round-1',amount=20}).ok,'Other sender cannot settle')
 eq(balance(h),95,'No unauthorized payout')
end)
test('lost request persists and retries after client restart',function()
 local h,c=setup(); h.hook=function() return false end
 check(h:call(c,'mutate',reserve()).offline,'Timeout'); eq(balance(h),100,'Request never arrived')
 local id=c.client:localState().pending.id; c=h:restartClient(c); eq(c.client:localState().pending.id,id,'Pending persisted')
 h.hook=nil; check(h:call(c,'retry').ok,'Retry delivered'); eq(balance(h),95,'Exactly one reservation'); sane(h)
end)
test('lost reply and host plus client restart do not double debit',function()
 local h,c=setup(); h.hook=function(p) if p.from==1 then return false end end
 check(h:call(c,'mutate',reserve()).offline,'Reply lost'); eq(balance(h),95,'Host committed')
 h:restartHost(); c=h:restartClient(c); h.hook=nil
 check(h:call(c,'retry').ok,'Durable retry receipt'); eq(balance(h),95,'Still one debit'); check(not c.client:localState().pending,'Pending cleared'); sane(h)
end)
test('pending operation blocks a second mutation',function()
 local h,c=setup(); h.hook=function() return false end; h:call(c,'mutate',reserve())
 local sent=#h.trace; local r=c.client:mutate(reserve('other'))
 check(r.pending,'Must resolve old request'); eq(#h.trace,sent,'No additional wire request'); eq(c.client:localState().counter,1,'No new transaction ID')
end)
test('duplicate packets return same receipt with one mutation',function()
 local h,c=setup(); h.hook=function(p) if p.from~=1 then return {p,p} end end
 check(h:call(c,'mutate',reserve()).ok,'Reserve'); eq(balance(h),95,'Only one debit')
 eq(h:state().rounds['round-1'].stake,5,'One round'); sane(h)
end)
test('changed retry content is rejected by fingerprint',function()
 local h,c=setup(); local q=reserve(); check(h:call(c,'mutate',q).ok,'Reserve'); q.stake=6
 local r=h:call(c,'read',q); check(not r.ok and r.error:find('different request',1,true),'Changed retry denied'); eq(balance(h),95,'No debit')
end)
test('delayed old response is ignored during newer request',function()
 local h,c=setup(); local delayed
 h.hook=function(p) if p.from==1 then delayed=p; return false end end
 check(h:call(c,'mutate',reserve()).offline,'First timeout'); local oldToken=delayed.message.token; delayed.message.result={ok=true,balance=999999}
 h.hook=function(p) if p.from==1 then return {delayed,p} end end
 local result=h:call(c,'retry'); check(result.ok,'New correlated response completes'); eq(result.balance,95,'Stale poisoned receipt ignored'); check(h.trace[#h.trace].message.token~=oldToken,'Fresh retry token'); eq(balance(h),95,'One debit')
end)
test('simultaneous shared-account requests cannot overspend',function()
 local h,a=setup(3); local b=h:client(4)
 h:start(a,'mutate',reserve('a',80,80)); h:start(b,'mutate',reserve('b',80,80)); h:pump()
 check(a.finished and b.finished,'Both clients completed'); check(a.result.ok~=b.result.ok,'Exactly one reservation accepted'); eq(balance(h),20,'Shared balance serialized'); sane(h)
end)
test('reordered requests and replies preserve client correlation',function()
 local h,a=setup(3); local b=h:client(4)
 h:start(a,'mutate',reserve('a',10,20)); h:start(b,'mutate',reserve('b',15,30))
 h.packets[1],h.packets[2]=h.packets[2],h.packets[1]
 h:deliver(table.remove(h.packets,1)); h:deliver(table.remove(h.packets,1))
 -- Both responses are queued now: explicitly reverse them as a separate fault.
 h.packets[1],h.packets[2]=h.packets[2],h.packets[1]; h:pump()
 check(a.result.ok and b.result.ok,'Both valid independent rounds'); eq(a.result.round,'a','Client A receipt'); eq(b.result.round,'b','Client B receipt'); eq(balance(h),75,'Both debits'); sane(h)
end)
test('settlement beyond reserved maximum is rejected',function()
 local h,c=setup(); h:call(c,'mutate',reserve())
 local r=h:call(c,'mutate',{op='settle',account='house-1',round='round-1',amount=21})
 check(not r.ok,'Overpayment denied'); eq(balance(h),95,'No credits appeared'); eq(h:state().rounds['round-1'].status,'open','Round remains reviewable'); sane(h)
end)
test('lost settlement reply recovers without second payout',function()
 local h,c=setup(); h:call(c,'mutate',reserve()); h.hook=function(p) if p.from==1 then return false end end
 check(h:call(c,'mutate',{op='settle',account='house-1',round='round-1',amount=20}).offline,'Lost result')
 eq(balance(h),115,'Paid once'); h:restartHost(); h.hook=nil
 check(h:call(c,'retry').ok,'Receipt replay'); eq(balance(h),115,'Still paid once'); sane(h)
end)
test('cashier deposit lost reply never transfers twice',function()
 local h,c=setup(2); h.hook=function(p) if p.from==1 then return false end end
 check(h:call(c,'mutate',{op='deposit',account='house-1',amount=10}).offline,'Lost deposit receipt')
 eq(h.inventories.intake.moves,1,'One virtual transfer'); h:restartHost(); h.hook=nil; check(h:call(c,'retry').ok,'Retry receipt')
 eq(h.inventories.intake.moves,1,'No duplicate transfer'); eq(balance(h),110,'Deposit counted once'); sane(h)
end)
test('uncertain transfer remains pending and is not replayed',function()
 local h,c=setup(2); h.inventories.intake.failAfterMove=true
 local r=h:call(c,'mutate',{op='deposit',account='house-1',amount=10})
 check(not r.ok,'Uncertain transfer fails safely'); check(next(h:state().pending),'Durable reconciliation marker')
 local id=c.client:localState().last.request.id
 h:restartHost(); h.inventories.intake.failAfterMove=false
 local replay=h:call(c,'read',{op='deposit',id=id,account='house-1',amount=10})
 check(replay.pending,'Receipt requires reconciliation'); eq(h.inventories.intake.moves,1,'No second physical attempt')
 check(not h:call(h:client(3),'mutate',reserve()).ok,'Other rounds blocked until reconciliation')
end)
test('partial deposit credits actual moved items only',function()
 local h,c=setup(2); h.inventories.bank.capacity=3
 local r=h:call(c,'mutate',{op='deposit',account='house-1',amount=10})
 check(r.ok,'Partial deposit completes'); eq(r.moved,3,'Actual item receipt'); eq(balance(h),103,'Only actual items credited'); sane(h)
end)
test('full redemption output restores all unmoved credits',function()
 local h,c=setup(2); h.inventories.output.capacity=0
 local r=h:call(c,'mutate',{op='withdraw',account='house-1',amount=10})
 check(r.ok,'Zero-movement receipt completes'); eq(r.moved,0,'No items moved'); eq(balance(h),100,'Held debit fully restored'); sane(h)
end)
test('lost withdrawal reply cannot dispense twice',function()
 local h,c=setup(2); h.hook=function(p) if p.from==1 then return false end end
 check(h:call(c,'mutate',{op='withdraw',account='house-1',amount=10}).offline,'Withdrawal reply lost')
 eq(h.inventories.output.count,10,'One dispensation'); h:restartHost(); h.hook=nil
 check(h:call(c,'retry').ok,'Withdrawal receipt recovered'); eq(h.inventories.output.count,10,'No duplicate dispensation'); eq(balance(h),90,'One debit'); sane(h)
end)
test('uncertain withdrawal reconciles verified movement once',function()
 local h,c=setup(2); h.inventories.bank.failAfterMove=true
 local r=h:call(c,'mutate',{op='withdraw',account='house-1',amount=10})
 check(not r.ok,'Uncertain withdrawal requires operator'); local id=c.client:localState().last.request.id
 eq(h.inventories.output.count,10,'Movement occurred before error'); check(h:state().pending[id],'Intent durable')
 h:restartHost(); h.inventories.bank.failAfterMove=false
 local db=h.host.require('derby.store').open('/house-bank/state',{})
 local service=h.host.require('derby.service').new(db,{bank='bank'},function(name) return h.inventories[name] end)
 check(service:operator('reconcile',id,10).ok,'Operator verified actual count'); h:restartHost()
 eq(balance(h),90,'Verified debit retained'); check(not h:state().pending[id],'Reconciled once'); sane(h)
 local receipt=h:call(c,'read',{op='status',id=id}); eq(receipt.moved,10,'Durable final movement receipt')
end)
test('current v1 ignores non-diamond deposits',function()
 local h,c=setup(2)
 h.inventories.intake.list=function() return {[1]={name='minecraft:gold_ingot',count=10},[2]={name='minecraft:ender_eye',count=10}} end
 h.inventories.intake.getItemDetail=function(slot) return h.inventories.intake.list()[slot] end
 h.inventories.intake.pushItems=function() error('Current v1 must not move unsupported items') end
 local r=h:call(c,'mutate',{op='deposit',account='house-1',amount=10})
 check(r.ok,'Current fixed-currency behavior recorded'); eq(r.moved,0,'No unsupported items accepted'); eq(balance(h),100,'No fabricated credits'); sane(h)
end)
test('single damaged save generation falls back; two fail closed',function()
 local h,c=setup(); h:call(c,'mutate',reserve())
 local files=h.host.files
 -- Two commits: initial seq 1, reserve seq 2. Damage latest and recover seq 1.
 files['/house-bank/state.0']='broken JSON'; h:restartHost(); eq(balance(h),100,'Previous committed generation recovered')
 h.host.files['/house-bank/state.1']='also broken'
 local ok,err=pcall(function() h:restartHost() end)
 check(not ok and tostring(err):find('Both saved state slots are invalid',1,true),'No fresh bank after total corruption')
end)
test('malformed inner request is rejected without stopping host',function()
 local h,c=setup()
 for _,q in ipairs({false,'garbage',{}, {op=12}, {op='no-such-operation',id='3:1'}}) do
  local r=h:call(c,'read',q); check(not r.ok and type(r.error)=='string','Malformed request rejected')
 end
 check(h:call(c,'read',{op='lookup',account='house-1'}).ok,'Host still serves clients')
end)
test('malformed race bet account cannot crash host or mutate ledger',function()
 local h,c=setup(); h:timeout(h.host) -- real timer creates OPEN race
 local accounts={false,12,{},'missing'}
 for i=0,#accounts do
  local q={op='bet',race='race-1',horse=1,stake=5}; if i>0 then q.account=accounts[i] end
  local r=h:call(c,'mutate',q); check(not r.ok and r.error=='Unknown account','Invalid account rejected')
  eq(balance(h),100,'No debit'); check(not next(h:state().rounds),'No round created')
 end
 check(h:call(c,'read',{op='snapshot'}).ok,'Host still running'); sane(h)
end)
test('repeated deterministic packet loss and duplication preserve credits',function()
 local h,c=setup(); local packets=0
 h.hook=function(p)
  packets=packets+1
  if packets%5==0 then return false end
  if packets%7==0 then return {p,p} end
 end
 local function deliver(q)
  local r=h:call(c,'mutate',q)
  local tries=0
  while r.offline do tries=tries+1; check(tries<=10,'Fault schedule permits recovery'); r=h:call(c,'retry') end
  check(r.ok,'Mutation recovered')
 end
 for n=1,20 do
  local id='chaos-'..n; deliver(reserve(id,5,5)); deliver({op='settle',account='house-1',round=id,amount=3})
  eq(balance(h),100-2*n,'Conservation after round '..n); sane(h)
 end
end)
test('proposed play-mode accounting acceptance fixtures',function() require('tests.contracts.play_modes').test(check,eq) end)
test('proposed configurable-currency acceptance fixtures',function() require('tests.contracts.currency_policy').test(check,eq) end)
test('pay-to-play round charges once and returns no prize',function()
 local h,c=setup(); check(h:call(c,'mutate',reserve('admission',5,5)).ok,'Admission reserved')
 h.hook=function(p) if p.from==1 then return false end end
 check(h:call(c,'mutate',{op='settle',account='house-1',round='admission',amount=0}).offline,'Receipt lost')
 h.hook=nil; check(h:call(c,'retry').ok,'Admission receipt recovered'); eq(balance(h),95,'One entry fee, no prize'); sane(h)
end)
test('actual credits API crosses wire and preserves captured card account',function()
 local h,c=setup()
 local state=h:state(); state.accounts['house-2']={name='Other Guest',balance=40}
 h.host.require('derby.store').open('/house-bank/state',{}):save(state); h:restartHost()
 local function write(path,value)
  c.platform.fs.makeDir(c.platform.fs.getDir(path)); local f=c.platform.fs.open(path,'w')
  f.write(c.platform.textutils.serializeJSON(value)); f.close()
 end
 write('/house-config.json',{modem='wired',host=1})
 write('/disk/house-card.json',{account='house-1'})
 local credits=c.require('credits')
 h:task(c,function()
  local round,err=credits.beginRound('fixture',5,20,'/disk'); check(round,err or 'Round acknowledged')
  write('/disk/house-card.json',{account='house-2'})
  check(credits.increaseRound(round,5,30),'Increase acknowledged')
  return credits.settleRound(round,25)
 end)
 h:pump(); check(c.finished,'Whole credits workflow completed'); eq(c.result,115,'Captured player balance')
 eq(balance(h),115,'Correct player credited'); eq(h:state().accounts['house-2'].balance,40,'Swapped card untouched')
 sane(h)
end)
test('attraction consumer wallet contracts',function() require('tests.consumer_contracts')(check,eq) end)
print(('PASS Pine Rednet contracts: %d scenarios, %d assertions'):format(scenarios,assertions))
return {scenarios=scenarios,assertions=assertions}
