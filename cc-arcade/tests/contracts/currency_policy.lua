-- DESIGN ACCEPTANCE ORACLE ONLY. No production module imports or cashier actions.
-- This proposed schema is NOT understood by deployed pine-derby-house-v1.
-- All rates below are synthetic test arithmetic, not an economic recommendation.
local M={schema='pine-currency-policy-proposal',schemaVersion=1,maxExactInteger=9007199254740991,
 deployed={configurableItems=false,depositItem='minecraft:diamond',redeemItem='minecraft:diamond',creditsPerDiamond=1}}
local function copy(v)
 if type(v)~='table' then return v end
 local r={}; for k,x in pairs(v) do r[k]=copy(x) end; return r
end
M.copy=copy
local function fail(message) return false,message end
local function integer(v) return type(v)=='number' and v==v and v>=0 and v<=M.maxExactInteger and v%1==0 end
local function positive(v) return integer(v) and v>0 end
local function text(v) return type(v)=='string' and #v>0 end
local function registry(v) return text(v) and v:match('^[a-z0-9_.%-]+:[a-z0-9_./%-]+$')~=nil end
local function contains(list,value) for _,allowed in ipairs(list) do if value==allowed then return true end end; return false end
local function array(t,predicate)
 if type(t)~='table' then return false end
 local count=0
 for k,v in pairs(t) do if not positive(k) or not predicate(v) then return false end; count=count+1 end
 for i=1,count do if t[i]==nil then return false end end
 return count==#t
end
local function scalar(v) return type(v)=='boolean' or type(v)=='string' or integer(v) end
function M.validatePolicy(p)
 if type(p)~='table' or p.schema~=M.schema or p.schemaVersion~=M.schemaVersion then return fail('unsupported proposed policy schema') end
 if not text(p.policyId) or not positive(p.revision) or not positive(p.creditScale) or not positive(p.maxTransferUnits) then return fail('invalid policy identity, scale or limit') end
 if type(p.entries)~='table' or not next(p.entries) then return fail('policy needs at least one item entry') end
 local used={}
 for key,e in pairs(p.entries) do
  if not text(key) or not key:match('^[a-z0-9_.%-]+$') or type(e)~='table' or not registry(e.itemId) then return fail('exact entry and registry IDs required') end
  if used[e.itemId] then return fail('one value/identity rule per registry ID; overlapping entries are not supported') end
  used[e.itemId]=true
  if type(e.depositEnabled)~='boolean' or type(e.redeemEnabled)~='boolean' then return fail('explicit deposit and redeem flags required') end
  if not positive(e.unitsPerItem) or e.unitsPerItem>p.maxTransferUnits then return fail('item value must be positive integer atomic units') end
  local identity=e.identity
  if type(identity)~='table' or type(identity.allowNoNbt)~='boolean' or not array(identity.nbtHashes,text) then return fail('explicit NBT allowlist required') end
  if not identity.allowNoNbt and #identity.nbtHashes==0 then return fail('identity cannot reject every NBT variant') end
  if type(identity.metadata)~='table' then return fail('explicit metadata allowlist required') end
  for field,allowed in pairs(identity.metadata) do
   if not text(field) or not array(allowed,scalar) or #allowed==0 then return fail('metadata fields need nonempty scalar allowlists') end
  end
 end
 return true
end
function M.identifyItem(p,entryId,item,direction)
 local ok,why=M.validatePolicy(p); if not ok then return false,why end
 local e=p.entries[entryId]
 if not e or type(item)~='table' or item.name~=e.itemId then return fail('item registry ID does not match policy entry') end
 if direction~='deposit' and direction~='redeem' then return fail('unknown transfer direction') end
 if not e[direction=='deposit' and 'depositEnabled' or 'redeemEnabled'] then return fail('item is disabled for this direction') end
 for key in pairs(item) do if key~='name' and key~='nbt' and key~='metadata' and key~='count' then return fail('unrecognized normalized item field') end end
 if item.count~=nil and not integer(item.count) then return fail('invalid observed item count') end
 if item.nbt==nil then
  if not e.identity.allowNoNbt then return fail('plain item identity is not allowed') end
 elseif not text(item.nbt) or not contains(e.identity.nbtHashes,item.nbt) then return fail('NBT fingerprint is not allowlisted') end
 local metadata=item.metadata or {}
 if type(metadata)~='table' then return fail('normalized metadata must be a table') end
 for field,allowed in pairs(e.identity.metadata) do
  if not contains(allowed,metadata[field]) then return fail('missing or disallowed metadata value') end
 end
 for field in pairs(metadata) do if e.identity.metadata[field]==nil then return fail('unapproved metadata field') end end
 return true
end
function M.quote(p,q)
 local ok,why=M.validatePolicy(p); if not ok then return false,why end
 if type(q)~='table' or not text(q.id) or not text(q.account) or q.policyId~=p.policyId or q.policyRevision~=p.revision then return fail('request must pin transaction, account and policy revision') end
 local e=p.entries[q.entryId]
 if not e or (q.direction~='deposit' and q.direction~='redeem') then return fail('unknown entry or direction') end
 if not e[q.direction=='deposit' and 'depositEnabled' or 'redeemEnabled'] then return fail('direction disabled') end
 if not positive(q.requestedItems) or q.requestedItems>math.floor(p.maxTransferUnits/e.unitsPerItem) then return fail('item quantity exceeds exact transfer-unit limit') end
 -- No division/rounding of monetary value: callers request whole items.
 return true,{policyId=p.policyId,policyRevision=p.revision,entryId=q.entryId,itemId=e.itemId,
  requestedItems=q.requestedItems,unitsPerItem=e.unitsPerItem,requestedUnits=q.requestedItems*e.unitsPerItem}
end
function M.backingUnits(p,counts)
 local ok,why=M.validatePolicy(p); if not ok then return false,why end
 if type(counts)~='table' then return fail('classified inventory counts required') end
 local total=0
 for entryId,count in pairs(counts) do
  local entry=p.entries[entryId]
  if not entry or not integer(count) or count>math.floor((M.maxExactInteger-total)/entry.unitsPerItem) then return fail('unknown item count or valuation overflow') end
  total=total+count*entry.unitsPerItem
 end
 return true,total
end
-- Validate observations of ONE proposed transaction, not a transfer simulator.
-- Every event includes the money/bank snapshot it claims. Golden fixtures below
-- spell those observations out; no production code or inventories are involved.
function M.validateTransferTrace(p,q,events)
 local ok,quoted=M.quote(p,q); if not ok then return false,quoted end
 if not integer(q.initialBalanceUnits) or not integer(q.initialBankItems) or not integer(q.availableSourceItems)
  or not integer(q.targetCapacityItems) then return fail('trace requires measured starting counts, capacity and balance') end
 if q.direction=='redeem' and q.availableSourceItems~=q.initialBankItems then return fail('redeem source must be the classified bank inventory') end
 if not array(events,function(event) return type(event)=='table' end) or #events==0 then return fail('trace must contain a dense event sequence') end
 local deposit=q.direction=='deposit'; local sign=deposit and 1 or -1
 if not deposit and q.initialBalanceUnits<quoted.requestedUnits then return fail('insufficient credits for requested redemption hold') end
 if deposit and quoted.requestedUnits>M.maxExactInteger-q.initialBalanceUnits then return fail('possible credit-balance overflow') end
 local balance,held,bank=q.initialBalanceUnits,0,q.initialBankItems
 local prepared,attempted,committed,uncertain,crashed=false,false,false,false,false
 local actual,confirmed=0,nil
 for _,event in ipairs(events) do
  if type(event)~='table' then return fail('event must be a table') end
  if event.policyId~=q.policyId or event.policyRevision~=q.policyRevision or event.id~=q.id or event.entryId~=q.entryId or event.account~=q.account then
   return fail('every event must retain transaction/account/item/policy identity')
  end
  local kind=event.kind
  if kind=='intent' then
   if prepared or committed then return fail('intent must be saved once') end
   prepared=true
   if not deposit then held=quoted.requestedUnits; balance=balance-held end
  elseif kind=='move' then
   if not prepared or attempted or committed or uncertain or crashed then return fail('physical transfer requires one fresh durable intent') end
   if not integer(event.actualItems) or event.actualItems>q.requestedItems or event.actualItems>q.availableSourceItems or event.actualItems>q.targetCapacityItems then return fail('invalid physical moved count') end
   local matching,why=M.identifyItem(p,q.entryId,event.item,q.direction); if not matching then return false,why end
   attempted=true; actual=event.actualItems; confirmed=actual; bank=bank+sign*actual
   if not integer(bank) then return fail('bank item-count underflow or overflow') end
  elseif kind=='uncertain' then
   if not prepared or committed then return fail('uncertain transfer requires a pending intent') end
   uncertain=true; confirmed=nil
  elseif kind=='crash' then
   if not prepared or crashed then return fail('crash must interrupt a prepared transaction') end
   crashed=true
   if not committed then uncertain=true; confirmed=nil end
  elseif kind=='restart' then
   if not crashed then return fail('restart requires crash') end
   crashed=false
  elseif kind=='reconcile' then
   if not prepared or committed or not uncertain or crashed then return fail('operator reconciliation only resolves an uncertain intent') end
   if event.observedBankItems~=bank or event.confirmedItems~=actual then return fail('reconciliation must match the classified physical item delta') end
   confirmed=actual; uncertain=false
  elseif kind=='receipt' then
   if not prepared or committed or uncertain or crashed or confirmed==nil then return fail('receipt needs confirmed movement or completed reconciliation') end
   if event.confirmedItems~=confirmed or event.unitsDelta~=sign*confirmed*quoted.unitsPerItem then return fail('receipt must value actual movement at pinned integer rate') end
   balance=q.initialBalanceUnits+event.unitsDelta; held=0; committed=true
  elseif kind=='retry' then
   if not prepared or crashed then return fail('retry requires a recovered transaction') end
   if committed then
    if event.status~='completed' or event.confirmedItems~=actual or event.unitsDelta~=sign*actual*quoted.unitsPerItem then return fail('retry must replay the unchanged durable receipt') end
   elseif event.status~='pending_reconciliation' or event.confirmedItems~=nil or event.unitsDelta~=nil then
    return fail('uncommitted retry cannot claim movement or credit')
   end
  else return fail('unknown trace event') end
  if event.balanceUnits~=balance or event.heldUnits~=held or event.bankItems~=bank then return fail('event snapshot violates conservation or credits an unconfirmed transfer') end
 end
 if not committed and not uncertain then return fail('trace ends before either durable receipt or explicit reconciliation requirement') end
 return true,{balanceUnits=balance,heldUnits=held,bankItems=bank,status=committed and 'completed' or 'pending_reconciliation',physicalAttempts=attempted and 1 or 0}
end

local function plain() return {allowNoNbt=true,nbtHashes={},metadata={}} end
M.syntheticPolicy={schema=M.schema,schemaVersion=1,policyId='SYNTHETIC-TEST-ONLY',revision=7,creditScale=1,maxTransferUnits=1000000000,
 entries={
  diamond={itemId='minecraft:diamond',depositEnabled=true,redeemEnabled=true,unitsPerItem=12,identity=plain()},
  gold={itemId='minecraft:gold_ingot',depositEnabled=true,redeemEnabled=true,unitsPerItem=3,identity=plain()},
  eye={itemId='minecraft:ender_eye',depositEnabled=true,redeemEnabled=false,unitsPerItem=24,identity=plain()},
  token={itemId='examplemod:arcade_token',depositEnabled=false,redeemEnabled=true,unitsPerItem=6,
   identity={allowNoNbt=false,nbtHashes={'SYNTHETIC-NBT-FINGERPRINT'},metadata={damage={0}}}},
 }}
local function request(direction,entry,items,balance,bank,source,capacity)
 return {id='7:synthetic',account='fixture-account',policyId='SYNTHETIC-TEST-ONLY',policyRevision=7,
  direction=direction,entryId=entry,requestedItems=items,initialBalanceUnits=balance,initialBankItems=bank,
  availableSourceItems=source,targetCapacityItems=capacity}
end
-- Identity decoration contains no arithmetic or expected-state calculation.
local function trace(q,events)
 for _,event in ipairs(events) do
  event.id=q.id; event.account=q.account; event.entryId=q.entryId; event.policyId=q.policyId; event.policyRevision=q.policyRevision
 end
 return events
end
M.traces={}
local function fixture(name,q,events,expected)
 M.traces[#M.traces+1]={name=name,request=q,events=trace(q,events),expected=expected}
end
fixture('partial deposit credits only three moved items',request('deposit','diamond',5,100,20,3,100),{
 {kind='intent',balanceUnits=100,heldUnits=0,bankItems=20},
 {kind='move',actualItems=3,item={name='minecraft:diamond'},balanceUnits=100,heldUnits=0,bankItems=23},
 {kind='receipt',confirmedItems=3,unitsDelta=36,balanceUnits=136,heldUnits=0,bankItems=23},
 {kind='retry',status='completed',confirmedItems=3,unitsDelta=36,balanceUnits=136,heldUnits=0,bankItems=23},
},{balanceUnits=136,heldUnits=0,bankItems=23,status='completed',physicalAttempts=1})
fixture('partial redemption refunds unmoved reservation',request('redeem','diamond',5,100,20,20,3),{
 {kind='intent',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='move',actualItems=3,item={name='minecraft:diamond'},balanceUnits=40,heldUnits=60,bankItems=17},
 {kind='receipt',confirmedItems=3,unitsDelta=-36,balanceUnits=64,heldUnits=0,bankItems=17},
},{balanceUnits=64,heldUnits=0,bankItems=17,status='completed',physicalAttempts=1})
fixture('empty deposit source creates zero credit',request('deposit','gold',5,100,20,0,100),{
 {kind='intent',balanceUnits=100,heldUnits=0,bankItems=20},
 {kind='move',actualItems=0,item={name='minecraft:gold_ingot'},balanceUnits=100,heldUnits=0,bankItems=20},
 {kind='receipt',confirmedItems=0,unitsDelta=0,balanceUnits=100,heldUnits=0,bankItems=20},
},{balanceUnits=100,heldUnits=0,bankItems=20,status='completed',physicalAttempts=1})
fixture('full deposit bank creates zero credit',request('deposit','gold',5,100,20,5,0),{
 {kind='intent',balanceUnits=100,heldUnits=0,bankItems=20},
 {kind='move',actualItems=0,item={name='minecraft:gold_ingot'},balanceUnits=100,heldUnits=0,bankItems=20},
 {kind='receipt',confirmedItems=0,unitsDelta=0,balanceUnits=100,heldUnits=0,bankItems=20},
},{balanceUnits=100,heldUnits=0,bankItems=20,status='completed',physicalAttempts=1})
fixture('empty redemption bank releases full hold',request('redeem','diamond',5,100,0,0,100),{
 {kind='intent',balanceUnits=40,heldUnits=60,bankItems=0},
 {kind='move',actualItems=0,item={name='minecraft:diamond'},balanceUnits=40,heldUnits=60,bankItems=0},
 {kind='receipt',confirmedItems=0,unitsDelta=0,balanceUnits=100,heldUnits=0,bankItems=0},
},{balanceUnits=100,heldUnits=0,bankItems=0,status='completed',physicalAttempts=1})
fixture('full redemption output releases full hold',request('redeem','diamond',5,100,20,20,0),{
 {kind='intent',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='move',actualItems=0,item={name='minecraft:diamond'},balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='receipt',confirmedItems=0,unitsDelta=0,balanceUnits=100,heldUnits=0,bankItems=20},
},{balanceUnits=100,heldUnits=0,bankItems=20,status='completed',physicalAttempts=1})
fixture('receipt-write crash requires reconciliation before credit',request('deposit','diamond',5,100,20,5,100),{
 {kind='intent',balanceUnits=100,heldUnits=0,bankItems=20},
 {kind='move',actualItems=3,item={name='minecraft:diamond'},balanceUnits=100,heldUnits=0,bankItems=23},
 {kind='crash',balanceUnits=100,heldUnits=0,bankItems=23},
 {kind='restart',balanceUnits=100,heldUnits=0,bankItems=23},
 {kind='retry',status='pending_reconciliation',balanceUnits=100,heldUnits=0,bankItems=23},
 {kind='reconcile',confirmedItems=3,observedBankItems=23,balanceUnits=100,heldUnits=0,bankItems=23},
 {kind='receipt',confirmedItems=3,unitsDelta=36,balanceUnits=136,heldUnits=0,bankItems=23},
},{balanceUnits=136,heldUnits=0,bankItems=23,status='completed',physicalAttempts=1})
fixture('crash before movement reconciles zero without replaying',request('redeem','diamond',5,100,20,20,100),{
 {kind='intent',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='crash',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='restart',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='retry',status='pending_reconciliation',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='reconcile',confirmedItems=0,observedBankItems=20,balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='receipt',confirmedItems=0,unitsDelta=0,balanceUnits=100,heldUnits=0,bankItems=20},
},{balanceUnits=100,heldUnits=0,bankItems=20,status='completed',physicalAttempts=0})
fixture('durable receipt survives crash and repeated retry',request('redeem','gold',4,100,20,20,100),{
 {kind='intent',balanceUnits=88,heldUnits=12,bankItems=20},
 {kind='move',actualItems=4,item={name='minecraft:gold_ingot'},balanceUnits=88,heldUnits=12,bankItems=16},
 {kind='receipt',confirmedItems=4,unitsDelta=-12,balanceUnits=88,heldUnits=0,bankItems=16},
 {kind='crash',balanceUnits=88,heldUnits=0,bankItems=16},
 {kind='restart',balanceUnits=88,heldUnits=0,bankItems=16},
 {kind='retry',status='completed',confirmedItems=4,unitsDelta=-12,balanceUnits=88,heldUnits=0,bankItems=16},
 {kind='retry',status='completed',confirmedItems=4,unitsDelta=-12,balanceUnits=88,heldUnits=0,bankItems=16},
},{balanceUnits=88,heldUnits=0,bankItems=16,status='completed',physicalAttempts=1})
fixture('uncertain movement stays held for operator',request('redeem','diamond',5,100,20,20,100),{
 {kind='intent',balanceUnits=40,heldUnits=60,bankItems=20},
 {kind='move',actualItems=2,item={name='minecraft:diamond'},balanceUnits=40,heldUnits=60,bankItems=18},
 {kind='uncertain',balanceUnits=40,heldUnits=60,bankItems=18},
 {kind='retry',status='pending_reconciliation',balanceUnits=40,heldUnits=60,bankItems=18},
},{balanceUnits=40,heldUnits=60,bankItems=18,status='pending_reconciliation',physicalAttempts=1})

function M.test(check,eq)
 local p=copy(M.syntheticPolicy)
 check(M.validatePolicy(p),'Synthetic configurable-item proposal is internally valid')
 eq(M.deployed.configurableItems,false,'Current production remains diamond-only')
 eq(M.deployed.creditsPerDiamond,1,'Current diamond denomination is unchanged')
 for _,mutation in ipairs({
  function(x) x.schemaVersion=2 end,
  function(x) x.entries.gold.itemId='gold ingot' end,
  function(x) x.entries.gold.itemId='minecraft:*' end,
  function(x) x.entries.gold.itemId='Minecraft:gold_ingot' end,
  function(x) x.entries.gold.itemId='minecraft:diamond' end,
  function(x) x.entries.gold.unitsPerItem=1.5 end,
  function(x) x.entries.gold.unitsPerItem=0 end,
  function(x) x.entries.gold.unitsPerItem=0/0 end,
  function(x) x.entries.gold.unitsPerItem=math.huge end,
  function(x) x.entries.gold.depositEnabled=nil end,
  function(x) x.entries.gold.identity=nil end,
  function(x) x.entries.gold.identity.allowNoNbt=false end,
  function(x) x.entries.gold.identity.metadata.damage={} end,
 }) do local bad=copy(p); mutation(bad); check(not M.validatePolicy(bad),'Malformed currency policy rejected') end
 local disabled=copy(p); disabled.entries.gold.depositEnabled=false; disabled.entries.gold.redeemEnabled=false
 check(M.validatePolicy(disabled),'A retained entry can disable both exchange directions')
 check(not M.identifyItem(disabled,'gold',{name='minecraft:gold_ingot'},'deposit'),'Disabled deposits rejected')
 check(not M.identifyItem(disabled,'gold',{name='minecraft:gold_ingot'},'redeem'),'Disabled redemptions rejected')
 check(M.identifyItem(p,'diamond',{name='minecraft:diamond'},'deposit'),'Exact plain diamond identity')
 check(not M.identifyItem(p,'diamond',{name='minecraft:diamond_block'},'deposit'),'No tag/name equivalence for diamond blocks')
 check(not M.identifyItem(p,'diamond',{name='minecraft:diamond',nbt='unknown'},'deposit'),'Unapproved NBT rejected')
 check(not M.identifyItem(p,'diamond',{name='minecraft:diamond',metadata={damage=1}},'deposit'),'Unapproved metadata rejected')
 check(not M.identifyItem(p,'diamond',{name='minecraft:diamond',displayName='Diamond'},'deposit'),'Raw peripheral records require explicit normalization')
 check(M.identifyItem(p,'token',{name='examplemod:arcade_token',nbt='SYNTHETIC-NBT-FINGERPRINT',metadata={damage=0}},'redeem'),'Allowlisted modded identity')
 check(not M.identifyItem(p,'token',{name='examplemod:arcade_token',nbt='SYNTHETIC-NBT-FINGERPRINT',metadata={damage=1}},'redeem'),'Disallowed modded metadata')
 check(not M.identifyItem(p,'token',{name='examplemod:arcade_token',nbt='SYNTHETIC-NBT-FINGERPRINT',metadata={damage=0}},'deposit'),'Redeem-only item cannot be deposited')
 check(not M.identifyItem(p,'eye',{name='minecraft:ender_eye'},'redeem'),'Deposit-only item cannot be redeemed')
 local q=request('deposit','gold',3,100,20,3,100)
 local ok,quoted=M.quote(p,q); check(ok,'Whole-item quote'); eq(quoted.requestedUnits,9,'Synthetic rate multiplies exactly')
 for _,amount in ipairs({-1,0,1.5,'3',true,math.huge,0/0,1000000000}) do
  local bad=copy(q); bad.requestedItems=amount; check(not M.quote(p,bad),'Nonwhole/overflow quantity rejected')
 end
 local old=copy(q); old.policyRevision=6; check(not M.quote(p,old),'Stale quote cannot silently use a new policy')
 local fractional=copy(p); fractional.creditScale=100; fractional.entries.gold.unitsPerItem=25
 ok,quoted=M.quote(fractional,q); check(ok,'Fractional display prices use integer atomic units'); eq(quoted.requestedUnits,75,'Three synthetic quarter-credit items are 75 atomic units')
 local tiny=copy(p); tiny.entries.gold.unitsPerItem=.25; check(not M.validatePolicy(tiny),'Fractional atomic units are never rounded')
 local valued,units=M.backingUnits(p,{diamond=2,gold=4,eye=1}); check(valued,'Inventory valuation'); eq(units,60,'Synthetic weighted backing counts each classified entry once')
 check(not M.backingUnits(p,{diamond=M.maxExactInteger}),'Aggregate valuation overflow rejected')
 check(not M.backingUnits(p,{unconfigured=1}),'Unconfigured items have no assumed backing value')
 for _,case in ipairs(M.traces) do
  local valid,result=M.validateTransferTrace(p,case.request,case.events); check(valid,case.name..': '..tostring(result))
  for field,value in pairs(case.expected) do eq(result[field],value,case.name..' '..field) end
 end
 local function rejected(index,label,mutate)
  local case=copy(M.traces[index]); mutate(case); check(not M.validateTransferTrace(p,case.request,case.events),label)
 end
 rejected(1,'Sparse traces cannot hide later events',function(c) c.events[8]=copy(c.events[2]) end)
 rejected(1,'No movement before durable intent',function(c) table.remove(c.events,1) end)
 rejected(1,'Requested quantity never substitutes for moved quantity',function(c) c.events[3].confirmedItems=5; c.events[3].unitsDelta=60 end)
 rejected(1,'No credit at physical movement before durable receipt',function(c) c.events[2].balanceUnits=136 end)
 rejected(1,'Duplicate transfer cannot repeat physical movement',function(c) table.insert(c.events,3,copy(c.events[2])) end)
 rejected(1,'Duplicate receipt cannot apply credit again',function(c) table.insert(c.events,4,copy(c.events[3])) end)
 rejected(1,'Retry cannot increase receipt credit',function(c) c.events[4].unitsDelta=72; c.events[4].balanceUnits=172 end)
 rejected(1,'Receipt cannot switch policy revision',function(c) c.events[3].policyRevision=8 end)
 rejected(1,'Receipt cannot switch account',function(c) c.events[3].account='other-account' end)
 rejected(1,'Wrong registry item cannot create credit',function(c) c.events[2].item.name='minecraft:cobblestone' end)
 rejected(2,'Partial redemption must release unused held value',function(c) c.events[3].balanceUnits=40 end)
 rejected(3,'Empty source cannot report movement',function(c) c.events[2].actualItems=1 end)
 rejected(6,'Full output cannot report movement',function(c) c.events[2].actualItems=1 end)
 rejected(7,'Crash retry cannot complete without reconciliation',function(c) c.events[5].status='completed' end)
 rejected(7,'Reconciliation must match physical counts',function(c) c.events[6].observedBankItems=25 end)
 rejected(7,'Reconciliation cannot invent moved quantity',function(c) c.events[6].confirmedItems=5 end)
 rejected(7,'Uncertain intent cannot make a second transfer',function(c) table.insert(c.events,6,copy(c.events[2])) end)
 rejected(8,'Missing policy epoch invalidates transaction',function(c) c.request.policyRevision=nil end)
 rejected(10,'Held funds cannot be returned while movement is uncertain',function(c) c.events[4].balanceUnits=100; c.events[4].heldUnits=0 end)
end
return M
