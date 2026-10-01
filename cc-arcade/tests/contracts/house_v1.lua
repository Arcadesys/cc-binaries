-- Independent examples and shape checks for the DEPLOYED pine-derby-house-v1.
-- Sources: derby/{client,server,service,ledger,house,odds}.lua and credits.lua.
-- No production module is imported: this file must remain an independent oracle.
--
-- API:
--   protocol, maxCredits, operations
--   validateRequest(q [, {role=..., owner=...}]) -> boolean, reason
--   validateResponse(q, r [, originalRequestForStatus]) -> boolean, reason
--   validateRequestEnvelope(envelope [, auth]) -> boolean, reason
--   validateResponseEnvelope(envelope, q [, expectedToken, originalRequest])
--   copy(value), fixtureState(context) -> fresh table
--   validRequests/malformedRequests: {name,request,role,owner,context,expected}
--   validResponses/malformedResponses: {name,request,response}
--   validEnvelopes/malformedEnvelopes: {name,direction,envelope,request?,token?}
--   authorizationCases/stateRejections: valid-shaped requests rejected by host
--   contractGaps: observed permissiveness/crashes, NOT passing rejection tests
--
-- "Valid" describes the current producer/consumer data contract, not whether a
-- particular bank/account/round can authorize a request. Unknown extra fields are
-- allowed and participate in ledger idempotency. Names are currently coerced with
-- tostring; owner is supplied by service, not trusted from the request. Empty
-- round/game strings and zero-credit rounds are accepted by the deployed ledger.
-- Successful roundStatus includes additive stake/maximum totals from the host.
-- Existing v1 status/paid meanings are unchanged; the recovery contract requires
-- the new terms rather than assuming an interrupted client's local stake is current.
-- Fixtures containing NaN/infinity are local adversarial inputs, not JSON files.
local M={protocol='pine-derby-house-v1',maxCredits=1000000000}
local reads={snapshot=true,lookup=true,status=true,roundStatus=true}
local mutations={create=true,reserve=true,increase=true,settle=true,refund=true,deposit=true,withdraw=true,bet=true}
M.operations={'snapshot','lookup','status','roundStatus','create','reserve','increase','settle','refund','deposit','withdraw','bet'}

local function fail(reason) return false,reason end
local function whole(n) return type(n)=='number' and n==n and n>=0 and n<math.huge and n%1==0 end
local function credits(n) return whole(n) and n<=M.maxCredits end
local function isString(v) return type(v)=='string' end
local function horse(n) return n==1 or n==2 or n==3 end
local function stake(n) return n==5 or n==10 or n==20 end
function M.copy(value)
 if type(value)~='table' then return value end
 local result={}; for k,v in pairs(value) do result[M.copy(k)]=M.copy(v) end; return result
end

function M.validateRequest(q,auth)
 if type(q)~='table' or not isString(q.op) then return fail('request.op must be a string') end
 local op=q.op
 if not reads[op] and not mutations[op] then return fail('unknown remote operation') end
 if mutations[op] then
  if not isString(q.id) or #q.id>160 then return fail('mutation id must be a string of at most 160 bytes') end
  if auth and auth.role=='display' then return fail('display is read only') end
  if auth and auth.owner~=nil then
   local prefix=tostring(auth.owner)..':'
   if q.id:sub(1,#prefix)~=prefix then return fail('transaction id does not belong to sender') end
  end
  if (op=='create' or op=='deposit' or op=='withdraw') and auth and auth.role and auth.role~='cashier' then
   return fail('cashier operation')
  end
 end
 if op=='snapshot' then
  if q.account~=nil and not isString(q.account) then return fail('optional snapshot account must be a string') end
 elseif op=='status' then
  if not isString(q.id) then return fail('status id must be a string') end
 elseif op~='create' then
  if not isString(q.account) then return fail('account must be a string') end
 end
 if op=='roundStatus' or op=='reserve' or op=='increase' or op=='settle' or op=='refund' then
  if not isString(q.round) then return fail('round must be a string') end
 end
 if op=='reserve' or op=='increase' then
  if not credits(q.stake) or not credits(q.maximum) or q.maximum<q.stake then return fail('invalid stake or maximum') end
  if op=='reserve' and not isString(q.game) then return fail('game must be a string') end
 elseif op=='settle' then
  if not credits(q.amount) then return fail('settlement amount must be integer credits') end
 elseif op=='deposit' or op=='withdraw' then
  if not credits(q.amount) or q.amount<1 then return fail('transfer amount must be positive integer diamonds') end
 elseif op=='bet' then
  if not isString(q.race) then return fail('race must be a string') end
  if not horse(q.horse) or not stake(q.stake) then return fail('invalid horse or derby stake') end
 end
 return true
end

local function denseArray(value,minimum,maximum,check)
 if type(value)~='table' then return false end
 local count=0
 for k,v in pairs(value) do
  if not whole(k) or k<1 or k>maximum or not check(v) then return false end
  count=count+1
 end
 if count<minimum or count>maximum then return false end
 for i=1,count do if value[i]==nil then return false end end
 return true
end
local function ticket(t)
 return type(t)=='table' and horse(t.horse) and stake(t.stake) and credits(t.returns)
  and isString(t.round) and isString(t.transaction) and (t.paid==nil or credits(t.paid))
end
local function snapshot(r)
 if type(r.paused)~='boolean' then return fail('snapshot paused must be boolean') end
 if r.id==nil then
  -- house.snapshot returns ONLY ok/paused before its first race.
  for _,field in ipairs({'phase','seconds','payouts','positions','tick','order','ticket','oddsVersion'}) do
   if r[field]~=nil then return fail('no-race snapshot cannot contain '..field) end
  end
  return true
 end
 if not isString(r.id) then return fail('snapshot id must be a string') end
 local phases={OPEN=true,LOCKED=true,RUNNING=true,RESULT=true,CANCELLED=true}
 if not phases[r.phase] then return fail('invalid race phase') end
 if not whole(r.seconds) or r.seconds>60 then return fail('invalid countdown seconds') end
 if not whole(r.tick) then return fail('invalid simulation tick') end
 if not isString(r.oddsVersion) then return fail('oddsVersion must be a string') end
 if not denseArray(r.positions,3,3,function(v) return type(v)=='number' and v==v and v>=0 and v<=1 end) then
  return fail('positions must contain three normalized numbers')
 end
 if not denseArray(r.order,0,3,horse) then return fail('finish order must be a dense horse list') end
 local seen={}; for _,h in ipairs(r.order) do if seen[h] then return fail('finish order repeats a horse') end; seen[h]=true end
 if not denseArray(r.payouts,3,3,function(p)
  return type(p)=='table' and credits(p['5']) and credits(p['10']) and credits(p['20'])
 end) then return fail('payouts must contain three stake-keyed schedules') end
 if r.ticket~=nil and not ticket(r.ticket) then return fail('invalid ticket') end
 return true
end
local function balance(r) return whole(r.balance) end -- total balances can exceed the per-request cap
local function receipt(q,r)
 if r.pending~=nil then
  if r.pending~=true or not isString(r.id) or r.id~=q.id then return fail('invalid pending receipt') end
  return true
 end
 if r.bank~=nil then
  if not whole(r.bank) then return fail('invalid bank receipt') end
  return true
 end
 if not balance(r) then return fail('receipt balance must be nonnegative whole credits') end
 if r.moved~=nil then
  if not credits(r.moved) or not isString(r.id) or r.id~=q.id then return fail('invalid transfer receipt') end
 elseif r.paid~=nil then
  if not credits(r.paid) then return fail('invalid settlement receipt') end
 elseif r.account~=nil then
  if not isString(r.account) or r.balance~=0 then return fail('invalid create receipt') end
 elseif r.round~=nil and not isString(r.round) then return fail('invalid reservation receipt') end
 -- A bare ok/balance receipt is an increase. v1 status has no operation tag.
 return true
end
function M.validateResponse(q,r,originalRequest)
 if type(q)~='table' or not isString(q.op) then return fail('response needs its originating request') end
 if type(r)~='table' or type(r.ok)~='boolean' then return fail('response.ok must be boolean') end
 if r.offline~=nil and type(r.offline)~='boolean' then return fail('offline flag must be boolean') end
 if r.pending~=nil and type(r.pending)~='boolean' then return fail('pending flag must be boolean') end
 if not r.ok then
  if not isString(r.error) or #r.error==0 then return fail('failed response needs a nonempty error') end
  return true
 end
 if r.offline==true then return fail('successful response cannot be offline') end
 local op=q.op
 if r.pending==true and op~='status' and op~='deposit' and op~='withdraw' then return fail('operation cannot return a pending transfer') end
 if op=='status' then
  if originalRequest then
   if originalRequest.id~=q.id then return fail('status request does not identify original request') end
   if originalRequest.op=='status' then return fail('status origin must be a mutation') end
   return M.validateResponse(originalRequest,r)
  end
  return receipt(q,r)
 elseif op=='snapshot' then return snapshot(r)
 elseif op=='lookup' then
  if not balance(r) or not isString(r.name) or not isString(r.account) or r.account~=q.account then return fail('invalid lookup response') end
 elseif op=='roundStatus' then
  if not credits(r.stake) or not credits(r.maximum) or r.maximum<r.stake then return fail('round status needs valid authoritative stake and maximum') end
  if r.status=='open' then
   if r.paid~=nil then return fail('open round must not have a paid field') end
  elseif r.status=='settled' or r.status=='refunded' then
   if not credits(r.paid) or r.paid>r.maximum then return fail('closed round needs paid credits within its maximum') end
   if r.status=='refunded' and r.paid~=r.stake then return fail('refunded round must pay its full authoritative stake') end
  else return fail('invalid round status') end
 elseif op=='create' then
  if not isString(r.account) or r.balance~=0 then return fail('invalid create response') end
 elseif op=='reserve' then
  if not balance(r) or not isString(r.round) or r.round~=q.round then return fail('invalid reserve response') end
 elseif op=='increase' then
  if not balance(r) then return fail('invalid increase balance') end
 elseif op=='settle' or op=='refund' then
  if not balance(r) or not credits(r.paid) then return fail('invalid settlement response') end
  if op=='settle' and r.paid~=q.amount then return fail('settlement paid differs from request') end
 elseif op=='deposit' or op=='withdraw' then
  if r.id~=q.id then return fail('transfer id differs from request') end
  if r.pending==true then return true end
  if not balance(r) or not credits(r.moved) or not credits(q.amount) or r.moved>q.amount then return fail('invalid completed transfer') end
 elseif op=='bet' then
  if not ticket(r.ticket) then return fail('invalid betting ticket') end
  if r.ticket.horse~=q.horse or r.ticket.stake~=q.stake or r.ticket.transaction~=q.id then return fail('ticket differs from request') end
  -- Replayed bets omit balance in current house.bet.
  if r.balance~=nil and not balance(r) then return fail('invalid optional betting balance') end
 elseif op=='fund' then
  -- Operator receipts can be queried remotely through status.
  if not whole(r.bank) then return fail('invalid funding response') end
 else return fail('unknown response operation') end
 return true
end
function M.validateRequestEnvelope(e,auth)
 if type(e)~='table' or not isString(e.token) then return fail('request envelope needs a string token') end
 return M.validateRequest(e.request,auth)
end
function M.validateResponseEnvelope(e,q,expectedToken,originalRequest)
 if type(e)~='table' or not isString(e.token) then return fail('response envelope needs a string token') end
 if expectedToken~=nil and e.token~=expectedToken then return fail('response token does not match') end
 return M.validateResponse(q,e.result,originalRequest)
end

local payouts={{['5']=11,['10']=23,['20']=47},{['5']=17,['10']=34,['20']=68},{['5']=12,['10']=25,['20']=50}}
local oddsVersion='sim-1-calibration-100000-v1'
local function raceSnapshot()
 return {ok=true,id='race-1',phase='OPEN',paused=false,seconds=60,payouts=M.copy(payouts),positions={0,0,0},tick=0,order={},oddsVersion=oddsVersion}
end
function M.fixtureState(context)
 context=context or 'funded'
 local s={version=1,bank=1000,accounts={['house-1']={name='ALPHA',balance=100},['house-2']={name='BETA',balance=30}},
  rounds={},transactions={},nextAccount=2,pending={},raceNumber=0,paused=false,
  odds={version=oddsVersion,payouts=M.copy(payouts)}}
 if context=='empty' then s.bank=0; s.accounts={}; s.nextAccount=0
 elseif context=='rich' then s.bank=M.maxCredits; s.accounts['house-1'].balance=M.maxCredits; s.accounts['house-2'].balance=0
 elseif context=='largeBalance' then s.bank=2000000000; s.accounts['house-1'].balance=M.maxCredits+1
 elseif context=='open' or context=='increased' or context=='settled' or context=='refunded' then
  s.rounds['arcade:42:1']={account='house-1',stake=10,maximum=40,status='open',game='pinejack',owner='42'}
  s.accounts['house-1'].balance=90
  if context=='increased' then
   local r=s.rounds['arcade:42:1']; r.stake=20; r.maximum=80; s.accounts['house-1'].balance=80
  elseif context~='open' then
   local r=s.rounds['arcade:42:1']; r.status=context; r.paid=context=='settled' and 30 or 10
   s.accounts['house-1'].balance=s.accounts['house-1'].balance+r.paid
  end
 elseif context=='receipt' then
  s.transactions['42:receipt']={fingerprint='fixture:read-only-receipt',result={ok=true,balance=120,paid=30}}
 elseif context=='pending' then
  s.pending['7:pending']={kind='deposit',account='house-1',amount=5,beforeBank=1000}
  s.transactions['7:pending']={fingerprint='fixture:read-only-pending',result={ok=true,pending=true,id='7:pending'}}
 elseif context=='race' then
  s.raceNumber=1; s.race={id='race-1',phase='OPEN',elapsed=0,seed=743,tickets={},payouts=M.copy(payouts),oddsVersion=oddsVersion}
 elseif context~='funded' then error('Unknown house_v1 fixture context: '..tostring(context)) end
 return s
end

M.validRequests={}
local function valid(name,q,expected,context,role,owner)
 M.validRequests[#M.validRequests+1]={name=name,request=q,expected=expected,context=context or 'funded',role=role or 'station',owner=owner or 42}
end
valid('snapshot before first race',{op='snapshot'},{ok=true,paused=false})
valid('snapshot active race',{op='snapshot'},{ok=true,id='race-1',phase='OPEN',paused=false,seconds=60,payouts=M.copy(payouts),positions={0,0,0},tick=0,order={},oddsVersion=oddsVersion},'race','display')
valid('snapshot unknown account remains public',{op='snapshot',account='house-missing'},raceSnapshot(),'race')
valid('lookup account',{op='lookup',account='house-1'},{ok=true,account='house-1',name='ALPHA',balance=100})
valid('lookup accumulated balance above request cap',{op='lookup',account='house-1'},{ok=true,account='house-1',name='ALPHA',balance=1000000001},'largeBalance')
valid('lookup from display',{op='lookup',account='house-2'},{ok=true,account='house-2',name='BETA',balance=30},'funded','display')
valid('status returns original receipt',{op='status',id='42:receipt'},{ok=true,balance=120,paid=30},'receipt','display',9)
valid('status pending receipt',{op='status',id='7:pending'},{ok=true,pending=true,id='7:pending'},'pending')
valid('roundStatus open omits paid',{op='roundStatus',account='house-1',round='arcade:42:1'},{ok=true,status='open',stake=10,maximum=40},'open','display')
valid('roundStatus reports increased total terms',{op='roundStatus',account='house-1',round='arcade:42:1'},{ok=true,status='open',stake=20,maximum=80},'increased')
valid('roundStatus settled',{op='roundStatus',account='house-1',round='arcade:42:1'},{ok=true,status='settled',paid=30,stake=10,maximum=40},'settled')
valid('roundStatus refunded',{op='roundStatus',account='house-1',round='arcade:42:1'},{ok=true,status='refunded',paid=10,stake=10,maximum=40},'refunded')
valid('create named account',{op='create',id='7:create',name='NEW PLAYER'},{ok=true,account='house-3',balance=0},nil,'cashier',7)
valid('create default guest',{op='create',id='7:guest'},{ok=true,account='house-1',balance=0},'empty','cashier',7)
valid('create coerces numeric name',{op='create',id='7:number',name=123},{ok=true,account='house-3',balance=0},nil,'cashier',7)
valid('create false name selects Guest',{op='create',id='7:false',name=false},{ok=true,account='house-3',balance=0},nil,'cashier',7)
valid('create long name is truncated',{op='create',id='7:long',name='ABCDEFGHIJKLMNOPQRSTUVWXYZ'},{ok=true,account='house-3',balance=0},nil,'cashier',7)
valid('bet creates backed derby ticket',{op='bet',id='42:bet',account='house-1',race='race-1',horse=1,stake=5},{ok=true,ticket={horse=1,stake=5,returns=11,round='race-1:house-1',transaction='42:bet'},balance=95},'race')
valid('reserve 160-byte transaction ID',{op='reserve',id='42:'..string.rep('x',157),account='house-1',round='boundary',game='test',stake=0,maximum=0},{ok=true,round='boundary',balance=100})
valid('reserve regular round',{op='reserve',id='42:reserve',account='house-1',round='arcade:42:2',game='pineslots',stake=10,maximum=50},{ok=true,round='arcade:42:2',balance=90})
valid('reserve zero-cost future reward',{op='reserve',id='42:reward',account='house-1',round='reward',game='rps_rogue',stake=0,maximum=5},{ok=true,round='reward',balance=100})
valid('reserve zero-liability round',{op='reserve',id='42:zero',account='house-1',round='zero',game='test',stake=0,maximum=0},{ok=true,round='zero',balance=100})
valid('reserve accepts current empty string identifiers',{op='reserve',id='42:empty',account='house-1',round='',game='',stake=0,maximum=0},{ok=true,round='',balance=100})
valid('reserve max integer boundary',{op='reserve',id='42:cap',account='house-1',round='cap',game='test',stake=M.maxCredits,maximum=M.maxCredits},{ok=true,round='cap',balance=0},'rich')
valid('reserve ignores supplied owner',{op='reserve',id='42:owner',account='house-1',round='owner',game='test',stake=10,maximum=20,owner='43'},{ok=true,round='owner',balance=90})
valid('increase open round',{op='increase',id='42:increase',account='house-1',round='arcade:42:1',stake=10,maximum=80},{ok=true,balance=80},'open')
valid('increase zero-cost liability',{op='increase',id='42:increase-zero',account='house-1',round='arcade:42:1',stake=0,maximum=50},{ok=true,balance=90},'open')
valid('settle win',{op='settle',id='42:settle',account='house-1',round='arcade:42:1',amount=30},{ok=true,balance=120,paid=30},'open')
valid('settle loss',{op='settle',id='42:loss',account='house-1',round='arcade:42:1',amount=0},{ok=true,balance=90,paid=0},'open')
valid('settle maximum',{op='settle',id='42:max',account='house-1',round='arcade:42:1',amount=40},{ok=true,balance=130,paid=40},'open')
valid('refund exact reserved stake',{op='refund',id='42:refund',account='house-1',round='arcade:42:1'},{ok=true,balance=100,paid=10},'open')
valid('refund ignores supplied amount',{op='refund',id='42:refund-amount',account='house-1',round='arcade:42:1',amount='ignored'},{ok=true,balance=100,paid=10},'open')
valid('settle ignores forged owner field',{op='settle',id='42:settle-owner',account='house-1',round='arcade:42:1',amount=10,owner='43'},{ok=true,balance=100,paid=10},'open')

M.malformedRequests={}
local function malformed(name,q,message,context)
 M.malformedRequests[#M.malformedRequests+1]={name=name,request=q,expected={ok=false,error=message},context=context or 'funded',role='station',owner=42}
end
malformed('missing request',nil,'Invalid request')
malformed('string request','reserve','Invalid request')
malformed('numeric request',17,'Invalid request')
malformed('missing operation',{},'Invalid request')
malformed('numeric operation',{op=1},'Invalid request')
malformed('unknown operation',{op='future-v2',id='42:unknown'},'Operation not available remotely')
malformed('missing mutation id',{op='reserve',account='house-1',round='x',game='test',stake=1,maximum=1},'Wrong transaction owner')
malformed('numeric mutation id',{op='reserve',id=42,account='house-1',round='x',game='test',stake=1,maximum=1},'Wrong transaction owner')
malformed('oversize mutation id',{op='reserve',id='42:'..string.rep('x',158),account='house-1',round='x',game='test',stake=1,maximum=1},'Transaction ID required')
malformed('lookup missing account',{op='lookup'},'Insert a new house account card')
malformed('lookup numeric account',{op='lookup',account=1},'Insert a new house account card')
malformed('lookup table account',{op='lookup',account={}},'Insert a new house account card')
malformed('status missing id',{op='status'},'Unknown transaction')
malformed('status boolean id',{op='status',id=false},'Unknown transaction')
malformed('roundStatus missing round',{op='roundStatus',account='house-1'},'Unknown round','open')
malformed('roundStatus numeric round',{op='roundStatus',account='house-1',round=1},'Unknown round','open')
malformed('reserve missing account',{op='reserve',id='42:bad-account',round='x',game='test',stake=1,maximum=1},'Unknown account')
malformed('reserve missing round',{op='reserve',id='42:bad-round',account='house-1',game='test',stake=1,maximum=1},'Round and game required')
malformed('reserve table round',{op='reserve',id='42:table-round',account='house-1',round={},game='test',stake=1,maximum=1},'Round and game required')
malformed('reserve numeric game',{op='reserve',id='42:bad-game',account='house-1',round='x',game=1,stake=1,maximum=1},'Round and game required')
malformed('reserve maximum below stake',{op='reserve',id='42:small-max',account='house-1',round='x',game='test',stake=10,maximum=9},'Invalid stake or maximum return')
malformed('bet missing account',{op='bet',id='42:missing-account',race='race-1',horse=1,stake=5},'Unknown account','race')
malformed('bet table account',{op='bet',id='42:table-account',account={},race='race-1',horse=1,stake=5},'Unknown account','race')
malformed('bet boolean account',{op='bet',id='42:boolean-account',account=false,race='race-1',horse=1,stake=5},'Unknown account','race')
malformed('bet numeric account',{op='bet',id='42:number-account',account=1,race='race-1',horse=1,stake=5},'Unknown account','race')
malformed('bet invalid horse',{op='bet',id='42:horse',account='house-1',race='race-1',horse=4,stake=5},'Choose a horse','race')
malformed('bet invalid stake',{op='bet',id='42:stake',account='house-1',race='race-1',horse=1,stake=7},'Choose 5, 10 or 20 credits','race')
local badAmounts={{name='negative',value=-1},{name='fraction',value=1.5},{name='numeric string',value='10'},
 {name='boolean',value=true},{name='table',value={}},{name='over cap',value=1000000001},
 {name='positive infinity',value=math.huge},{name='negative infinity',value=-math.huge},{name='NaN',value=0/0},{name='missing'}}
for _,bad in ipairs(badAmounts) do
 for _,field in ipairs({'stake','maximum'}) do
  local q={op='reserve',id='42:bad-reserve-'..field..'-'..bad.name,account='house-1',round='x',game='test',stake=10,maximum=40}; q[field]=bad.value
  malformed('reserve '..field..' '..bad.name,q,'Invalid stake or maximum return')
  q={op='increase',id='42:bad-increase-'..field..'-'..bad.name,account='house-1',round='arcade:42:1',stake=10,maximum=80}; q[field]=bad.value
  malformed('increase '..field..' '..bad.name,q,'Invalid increase','open')
 end
 malformed('settle amount '..bad.name,{op='settle',id='42:bad-settle-'..bad.name,account='house-1',round='arcade:42:1',amount=bad.value},'Return exceeds reservation','open')
end

M.authorizationCases={
 {name='display mutation',request={op='refund',id='42:display',account='house-1',round='arcade:42:1'},role='display',owner=42,context='open',expected={ok=false,error='Display is read only'}},
 {name='station cannot create',request={op='create',id='42:create'},role='station',owner=42,expected={ok=false,error='Cashier operation'}},
 {name='transaction belongs to another sender',request={op='refund',id='43:refund',account='house-1',round='arcade:42:1'},role='station',owner=42,context='open',expected={ok=false,error='Wrong transaction owner'}},
 {name='owner prefix includes delimiter',request={op='refund',id='420:refund',account='house-1',round='arcade:42:1'},role='station',owner=42,context='open',expected={ok=false,error='Wrong transaction owner'}},
 {name='another station cannot increase',request={op='increase',id='43:increase',account='house-1',round='arcade:42:1',stake=10,maximum=80,owner='42'},role='station',owner=43,context='open',expected={ok=false,error='Round unavailable'}},
 {name='another station cannot settle',request={op='settle',id='43:settle',account='house-1',round='arcade:42:1',amount=30,owner='42'},role='station',owner=43,context='open',expected={ok=false,error='Round unavailable'}},
 {name='another station cannot refund',request={op='refund',id='43:refund',account='house-1',round='arcade:42:1',owner='42'},role='station',owner=43,context='open',expected={ok=false,error='Round unavailable'}},
}
M.stateRejections={}
local function rejected(name,q,message,context)
 M.stateRejections[#M.stateRejections+1]={name=name,request=q,role='station',owner=42,context=context or 'funded',expected={ok=false,error=message}}
end
rejected('unknown account',{op='lookup',account='house-missing'},'Insert a new house account card')
rejected('bet unknown account',{op='bet',id='42:unknown-account',account='missing',race='race-1',horse=1,stake=5},'Unknown account','race')
rejected('unknown receipt',{op='status',id='42:missing'},'Unknown transaction')
rejected('round belongs to another account',{op='roundStatus',account='house-2',round='arcade:42:1'},'Unknown round','open')
rejected('reserve insufficient credits',{op='reserve',id='42:poor',account='house-1',round='poor',game='test',stake=101,maximum=101},'Not enough credits')
rejected('reserve insufficient bank',{op='reserve',id='42:bank',account='house-1',round='bank',game='test',stake=0,maximum=871},'House reserve cannot cover this round')
rejected('reserve existing round',{op='reserve',id='42:existing',account='house-1',round='arcade:42:1',game='test',stake=1,maximum=1},'Round already exists','open')
rejected('increase lowers reserved maximum',{op='increase',id='42:lower',account='house-1',round='arcade:42:1',stake=0,maximum=39},'Invalid increase','open')
rejected('increase cannot cover total stake',{op='increase',id='42:stake',account='house-1',round='arcade:42:1',stake=40,maximum=40},'Invalid increase','open')
rejected('increase insufficient balance',{op='increase',id='42:poor-increase',account='house-1',round='arcade:42:1',stake=91,maximum=101},'Insufficient credits or house reserve','open')
rejected('settle exceeds reservation',{op='settle',id='42:overpay',account='house-1',round='arcade:42:1',amount=41},'Return exceeds reservation','open')
rejected('settle already settled',{op='settle',id='42:closed',account='house-1',round='arcade:42:1',amount=10},'Round already settled','settled')
rejected('refund already refunded',{op='refund',id='42:closed',account='house-1',round='arcade:42:1'},'Round already settled','refunded')
rejected('pending transfer freezes reservations',{op='reserve',id='42:pending',account='house-1',round='pending',game='test',stake=1,maximum=1},'Cashier transfer requires reconciliation','pending')

M.validResponses={}
for _,c in ipairs(M.validRequests) do M.validResponses[#M.validResponses+1]={name=c.name,request=M.copy(c.request),response=M.copy(c.expected)} end
local function response(name,q,r) M.validResponses[#M.validResponses+1]={name=name,request=q,response=r} end
response('roundStatus zero-cost reward terms',{op='roundStatus'},{ok=true,status='open',stake=0,maximum=5})
response('roundStatus zero-liability terms',{op='roundStatus'},{ok=true,status='open',stake=0,maximum=0})
response('roundStatus maximum integer terms',{op='roundStatus'},{ok=true,status='open',stake=1000000000,maximum=1000000000})
response('roundStatus settled loss retains reserved terms',{op='roundStatus'},{ok=true,status='settled',stake=10,maximum=40,paid=0})
response('ordinary denial',{op='lookup',account='missing'},{ok=false,error='Insert a new house account card'})
response('transport timeout',{op='lookup',account='house-1'},{ok=false,error='House offline; request retained for retry',offline=true})
response('client pending reconciliation',{op='deposit',id='7:1',account='house-1',amount=5},{ok=false,error='Cashier transfer pending reconciliation',pending=true})
response('transfer pending raw receipt',{op='deposit',id='7:1',account='house-1',amount=5},{ok=true,pending=true,id='7:1'})
response('partial transfer completion',{op='withdraw',id='7:1',account='house-1',amount=5},{ok=true,moved=3,balance=97,id='7:1'})
response('status operator fund receipt',{op='status',id='fund:123'},{ok=true,bank=1000})
response('status reserve receipt',{op='status',id='42:reserve'},{ok=true,round='arcade:42:2',balance=90})
response('status increase receipt',{op='status',id='42:increase'},{ok=true,balance=80})
response('status create receipt',{op='status',id='7:create'},{ok=true,account='house-3',balance=0})
response('status completed transfer',{op='status',id='7:1'},{ok=true,moved=5,balance=105,id='7:1'})
for _,phase in ipairs({'LOCKED','RUNNING','RESULT','CANCELLED'}) do
 local r=raceSnapshot(); r.phase=phase; r.seconds=phase=='LOCKED' and 5 or 0
 if phase=='RUNNING' then r.tick=300; r.positions={.65,.56,.71}
 elseif phase=='RESULT' then r.tick=470; r.positions={1,1,1}; r.order={3,1,2} end
 response('snapshot '..phase,{op='snapshot'},r)
end
local ticketExample={horse=1,stake=5,returns=11,round='race-1:house-1',transaction='42:bet'}
local r=raceSnapshot(); r.ticket=M.copy(ticketExample)
response('snapshot account ticket',{op='snapshot',account='house-1'},r)
response('bet original receipt',{op='bet',id='42:bet',account='house-1',race='race-1',horse=1,stake=5},{ok=true,ticket=M.copy(ticketExample),balance=95})
response('bet retry omits balance',{op='bet',id='42:bet',account='house-1',race='race-1',horse=1,stake=5},{ok=true,ticket=M.copy(ticketExample)})

M.malformedResponses={}
local function badResponse(name,q,r) M.malformedResponses[#M.malformedResponses+1]={name=name,request=q,response=r} end
local lookup={op='lookup',account='house-1'}
badResponse('missing response',lookup,nil)
badResponse('string response',lookup,'ok')
badResponse('truthy numeric ok',lookup,{ok=1,account='house-1',name='ALPHA',balance=100})
badResponse('false without error',lookup,{ok=false})
badResponse('false with numeric error',lookup,{ok=false,error=1})
badResponse('success flagged offline',lookup,{ok=true,account='house-1',name='ALPHA',balance=100,offline=true})
badResponse('string balance',lookup,{ok=true,account='house-1',name='ALPHA',balance='100'})
badResponse('negative balance',lookup,{ok=true,account='house-1',name='ALPHA',balance=-1})
badResponse('NaN balance',lookup,{ok=true,account='house-1',name='ALPHA',balance=0/0})
badResponse('wrong lookup account',lookup,{ok=true,account='house-2',name='BETA',balance=30})
badResponse('missing name',lookup,{ok=true,account='house-1',balance=100})
badResponse('open round with paid',{op='roundStatus'},{ok=true,status='open',paid=0,stake=10,maximum=40})
badResponse('settled round without paid',{op='roundStatus'},{ok=true,status='settled',stake=10,maximum=40})
badResponse('unknown round status',{op='roundStatus'},{ok=true,status='complete',paid=10,stake=10,maximum=40})
badResponse('roundStatus legacy missing recovery terms',{op='roundStatus'},{ok=true,status='open'})
for _,status in ipairs({'open','settled','refunded'}) do
 for _,field in ipairs({'stake','maximum'}) do
  for _,bad in ipairs({{name='missing'},{name='string',value='10'},{name='negative',value=-1},
   {name='fractional',value=.5},{name='over cap',value=1000000001},{name='NaN',value=0/0},{name='infinite',value=math.huge}}) do
   local r={ok=true,status=status,stake=10,maximum=40}; if status~='open' then r.paid=10 end; r[field]=bad.value
   badResponse('roundStatus '..status..' '..field..' '..bad.name,{op='roundStatus'},r)
  end
 end
end
badResponse('roundStatus maximum below total stake',{op='roundStatus'},{ok=true,status='open',stake=20,maximum=10})
badResponse('roundStatus paid exceeds maximum',{op='roundStatus'},{ok=true,status='settled',stake=10,maximum=40,paid=41})
badResponse('roundStatus refund differs from total stake',{op='roundStatus'},{ok=true,status='refunded',stake=20,maximum=80,paid=10})
badResponse('create nonzero opening balance',{op='create'},{ok=true,account='house-3',balance=10})
badResponse('reserve wrong round',{op='reserve',round='wanted'},{ok=true,round='other',balance=90})
badResponse('increase missing balance',{op='increase'},{ok=true})
badResponse('increase cannot be pending',{op='increase'},{ok=true,balance=90,pending=true})
badResponse('settlement wrong paid',{op='settle',amount=10},{ok=true,balance=100,paid=9})
badResponse('refund missing paid',{op='refund'},{ok=true,balance=100})
badResponse('status empty success',{op='status',id='42:x'},{ok=true})
badResponse('status mismatched transfer id',{op='status',id='7:wanted'},{ok=true,moved=1,balance=99,id='7:other'})
badResponse('pending receipt no id',{op='deposit',id='7:1',amount=5},{ok=true,pending=true})
badResponse('transfer more than requested',{op='withdraw',id='7:1',amount=5},{ok=true,moved=6,balance=94,id='7:1'})
badResponse('snapshot missing paused',{op='snapshot'},{ok=true})
badResponse('no-race snapshot with phase',{op='snapshot'},{ok=true,paused=false,phase='OPEN'})
for _,change in ipairs({
 {name='positions missing horse',field='positions',value={0,0}},
 {name='positions out of range',field='positions',value={0,1.1,0}},
 {name='positions string element',field='positions',value={0,'0',0}},
 {name='positions sparse array',field='positions',value={[1]=0,[3]=0}},
 {name='repeated finish horse',field='order',value={1,1}},
 {name='unknown finish horse',field='order',value={4}},
 {name='phase from a different protocol',field='phase',value='waiting'},
 {name='numeric odds version',field='oddsVersion',value=1},
 {name='fractional countdown',field='seconds',value=1.5},
 {name='negative tick',field='tick',value=-1},
 {name='payouts numeric stake keys',field='payouts',value={ {[5]=11,[10]=23,[20]=47}, {[5]=17,[10]=34,[20]=68}, {[5]=12,[10]=25,[20]=50} }},
 {name='malformed ticket',field='ticket',value={horse=4,stake=5,returns=11,round='x',transaction='42:x'}},
}) do local changed=raceSnapshot(); changed[change.field]=change.value; badResponse('snapshot '..change.name,{op='snapshot'},changed) end

M.validEnvelopes={
 {name='lookup request envelope',direction='request',envelope={token='42:1000:1',request=M.copy(lookup)}},
 {name='empty token is accepted in v1',direction='request',envelope={token='',request={op='snapshot'}}},
 {name='lookup response envelope',direction='response',token='42:1000:1',request=M.copy(lookup),envelope={token='42:1000:1',result={ok=true,account='house-1',name='ALPHA',balance=100}}},
 {name='failure response envelope',direction='response',token='42:1000:2',request=M.copy(lookup),envelope={token='42:1000:2',result={ok=false,error='Computer not registered at house host'}}},
}
M.malformedEnvelopes={
 {name='request envelope not a table',direction='request',envelope='request'},
 {name='request missing token',direction='request',envelope={request=M.copy(lookup)}},
 {name='request numeric token',direction='request',envelope={token=42,request=M.copy(lookup)}},
 {name='request missing body',direction='request',envelope={token='t'}},
 {name='request wrong body name',direction='request',envelope={token='t',payload=M.copy(lookup)}},
 {name='response numeric token',direction='response',token='t',request=M.copy(lookup),envelope={token=42,result={ok=false,error='no'}}},
 {name='response wrong token',direction='response',token='t',request=M.copy(lookup),envelope={token='other',result={ok=false,error='no'}}},
 {name='response missing result',direction='response',token='t',request=M.copy(lookup),envelope={token='t'}},
 {name='response result wrong type',direction='response',token='t',request=M.copy(lookup),envelope={token='t',result='ok'}},
}
M.contractGaps={
 {name='snapshot accepts non-string account',request={op='snapshot',account={}},context='race',role='station',owner=42,
  observed='accepted',expected= raceSnapshot(),source='derby/house.lua:M.snapshot',
  note='Host ignores a table-valued unknown account instead of rejecting its type; validator rejects it.'},
 {name='client trusts malformed matching result',request=M.copy(lookup),response={ok=true,balance='100'},
  observed='accepted-by-client',source='derby/client.lua:transport',
  note='Transport checks sender/protocol/token and table type, but does not validate response fields.'},
}
return M
