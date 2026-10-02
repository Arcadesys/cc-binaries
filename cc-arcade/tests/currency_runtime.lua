-- Production v2 ledger/service/store with deterministic, fictional CC inventories.
local platform=require('tests.support.platform').new()
fs=platform.fs; textutils=platform.textutils
os.epoch=function() return 12345 end
local store=require('derby.store')
local ledger=require('derby.ledger')
local service=require('derby.service')
local currency=require('derby.currency')
local passed=0
local function check(v,m) assert(v,m); passed=passed+1 end
local function eq(a,b,m) check(a==b,(m or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local inventories={}
local function inv(name,items)
 local a={items=items or {},moves=0,capacity=1000000}; inventories[name]=a
 function a.list() return store.copy(a.items) end
 function a.getItemDetail(slot) return store.copy(a.items[slot]) end
 function a.pushItems(dest,slot,limit)
  a.moves=a.moves+1
  if a.beforeError then error('Disconnected before push') end
  local target=inventories[dest]; local item=a.items[slot]
  local n=math.min(limit,item.count,target.capacity); target.capacity=target.capacity-n
  if n>0 then
   local key=1; while target.items[key] do key=key+1 end
   target.items[key]=store.copy(item); target.items[key].count=n; a.lastTargetSlot=key
   if a.lose then target.items[key]=nil end
   item.count=item.count-n; if item.count==0 then a.items[slot]=nil end
  end
  if a.afterError then error('Lost push return') end
  if a.dupe and n>0 then target.items[99]={name='minecraft:diamond',count=1} end
  return n
 end
 return a
end
local bank=inv('bank',{[1]={name='minecraft:diamond',count=100}})
local intake=inv('intake',{[1]={name='minecraft:diamond',count=50},[2]={name='minecraft:gold_ingot',count=40},[3]={name='minecraft:ender_eye',count=5}})
local output=inv('output')
local cfg={bank='bank',intake='intake',payout='output'}
local initial=ledger.new(); initial.paused=true; initial.bank=100
initial.accounts['house-1']={name='Guest',balance=20}; initial.nextAccount=1
initial.rounds.old={status='open',account='house-1',stake=5,maximum=15,owner='3',game='slots'}
initial.transactions.old={fingerprint='unchanged',result={ok=true,moved=20,balance=20}}
local db=store.open('/bank',initial); db:save(initial); db:save(initial)
local legacy0=platform.files['/bank.0']; local legacy1=platform.files['/bank.1']
local function host(storage) return service.new(storage or db,cfg,function(name) return inventories[name] end) end
local api=host()
check(api:operator('currency').ok,'migrate default policy')
local state=api:state(); eq(state.version,2); eq(state.bank,100); eq(state.accounts['house-1'].balance,20)
eq(state.rounds.old.maximum,15); eq(state.transactions.old.result.moved,20)
eq(platform.files['/bank.backup-v1.0'],legacy0,'exact first backup'); eq(platform.files['/bank.backup-v1.1'],legacy1,'exact second backup')
local policy=state.currency; check(not policy.entries.gold.depositEnabled,'gold disabled until configured')
local seq=0
local function req(direction,id,count,extra)
 seq=seq+1
 local q={op='exchange',apiVersion=2,id='2:'..seq,account='house-1',direction=direction,entryId=id,
  requestedItems=count,policyId=policy.policyId,policyRevision=policy.revision}
 for k,v in pairs(extra or {}) do q[k]=v end
 return api:request(q,'cashier',2),q
end
check(not api:request({op='deposit',id='2:old',account='house-1',amount=1},'cashier',2).ok,'old cashier rejected')
check(not req('deposit','gold',1).ok,'unconfigured rate rejects')
for _,invalid in ipairs({math.huge,-math.huge,0/0,function() end}) do
 local ok,result=pcall(req,'deposit','diamond',invalid)
 check(ok and not result.ok,'malformed quantity denied without crashing host')
 ok,result=pcall(req,'deposit','diamond',1,{extra=invalid})
 check(ok and not result.ok,'unsupported/nonfinite field denied without crashing host')
end
local r,q=req('deposit','diamond',10); check(r.ok,'deposit'); eq(r.confirmedItems,10); eq(r.unitsDelta,10); eq(r.balance,30)
local calls=intake.moves; eq(api:request(q,'cashier',2).balance,30); eq(intake.moves,calls,'duplicate no physical move')
q.requestedItems=11; check(not api:request(q,'cashier',2).ok,'changed retry rejected')
output.capacity=3
r=req('redeem','diamond',10); eq(r.confirmedItems,3); eq(r.unitsDelta,-3); eq(r.balance,27)
output.capacity=0; r=req('redeem','diamond',10); eq(r.confirmedItems,0); eq(r.balance,27,'full output charges zero')
output.capacity=1000000
bank.capacity=0; r=req('deposit','diamond',5); eq(r.confirmedItems,0); eq(r.balance,27,'full bank credits zero'); bank.capacity=1000000
-- Explicit policy revision: synthetic rates used only in these fixtures.
cfg.currency=store.copy(policy); cfg.currency.revision=2
cfg.currency.entries.gold.unitsPerItem=3; cfg.currency.entries.gold.depositEnabled=true; cfg.currency.entries.gold.redeemEnabled=true
cfg.currency.entries.ender_eye.unitsPerItem=7; cfg.currency.entries.ender_eye.depositEnabled=true
check(api:operator('currency').ok,'apply synthetic policy'); policy=api:state().currency
r=req('deposit','gold',4); eq(r.confirmedItems,4); eq(r.unitsDelta,12); eq(r.balance,39)
r=req('deposit','ender_eye',2); eq(r.unitsDelta,14); eq(r.balance,53)
check(not req('redeem','ender_eye',1).ok,'deposit only cannot redeem')
check(not req('redeem','gold',5).ok,'aggregate solvency is not gold liquidity')
r=req('redeem','gold',3); eq(r.unitsDelta,-9); eq(r.balance,44)
local conserved=api:state()
eq(conserved.stock.diamond,107,'independent diamond stock')
eq(conserved.stock.gold,1,'independent gold stock')
eq(conserved.stock.ender_eye,2,'independent ender eye stock')
eq(conserved.bank,107+3+14,'independent weighted bank sum')
eq(ledger.liability(conserved),44+15,'independent account and open-round liability')
local before=api:state(); eq(before.bank,currency.value(policy,before.stock),'weighted backing exact')
check(ledger.available(before)>=0,'balances and open liabilities backed')
-- Pending intent before movement and reboot never replays a physical transfer.
intake.beforeError=true; r,q=req('deposit','gold',2); check(r.pending,'uncertainty explicit')
local pending=api:state().pending[q.id]; eq(pending.entry.unitsPerItem,3); eq(pending.policyRevision,2); eq(pending.requestedUnits,6)
api=host(); intake.beforeError=false; calls=intake.moves
check(api:request(q,'cashier',2).pending,'restart pending'); eq(intake.moves,calls,'no push replay')
check(not api:operator('currency').ok,'pending blocks policy edits')
check(api:operator('reconcile',q.id,0).ok,'verified zero reconcile')
-- Lost push return after real movement requires original inventory evidence.
intake.afterError=true; r,q=req('deposit','gold',2); check(r.pending,'lost return pending')
intake.afterError=false; api=host(); calls=intake.moves
check(api:request(q,'cashier',2).pending); eq(intake.moves,calls)
check(not api:operator('reconcile',q.id,0).ok,'wrong reconciliation rejected')
check(api:operator('reconcile',q.id,2).ok,'actual moved reconcile')
r=api:request(q,'cashier',2); eq(r.confirmedItems,2); eq(r.unitsDelta,6)
-- Receipt save failure leaves old intent and holds; no repeated debit or movement.
local crashDB={get=function() return db:get() end,save=function(_,value)
 if not next(value.pending) and next(db:get().pending) then error('Receipt write failed') end
 db:save(value)
end}
api=host(crashDB)
seq=seq+1; q={op='exchange',apiVersion=2,id='2:'..seq,account='house-1',direction='redeem',entryId='gold',requestedItems=1,policyId=policy.policyId,policyRevision=policy.revision}
local bal=db:get().accounts['house-1'].balance
check(not pcall(function() api:request(q,'cashier',2) end),'receipt crash propagates')
api=host(); calls=bank.moves; check(api:request(q,'cashier',2).pending); eq(bank.moves,calls)
eq(api:state().accounts['house-1'].balance,bal-3,'durable redemption hold')
check(api:operator('reconcile',q.id,1).ok); eq(api:request(q,'cashier',2).balance,bal-3)
-- Unexpected extra delivery fails closed instead of crediting a dupe.
intake.dupe=true; r,q=req('deposit','diamond',1); check(r.pending,'dupe detected'); intake.dupe=false
check(not api:operator('reconcile',q.id,1).ok,'extra inventory blocks reconciliation')
bank.items[99]=nil
check(api:operator('reconcile',q.id,1).ok,'restore exact evidence then reconcile')
-- Missing delivered items cannot produce a completed credit receipt.
intake.lose=true; local lost,lostq=req('deposit','gold',1); intake.lose=false
check(lost.pending,'lost item detected')
check(not api:operator('reconcile',lostq.id,1).ok,'loss cannot be reconciled as delivery')
bank.items[intake.lastTargetSlot]={name='minecraft:gold_ingot',count=1}
check(api:operator('reconcile',lostq.id,1).ok,'restore verified delivered item before completion')
-- Policy edits never reprice receipts; insufficient backing rate reduction rejected.
local receipt=api:request(q,'cashier',2)
cfg.currency=store.copy(policy); cfg.currency.revision=3; cfg.currency.entries.diamond.unitsPerItem=2
check(api:operator('currency').ok); policy=api:state().currency
eq(api:request(q,'cashier',2).unitsDelta,receipt.unitsDelta,'old receipt pinned')
check(not req('deposit','diamond',1,{policyRevision=2}).ok,'stale quote rejected')
cfg.currency=store.copy(policy); cfg.currency.revision=4; cfg.currency.entries.diamond.unitsPerItem=1
cfg.currency.entries.gold.unitsPerItem=1; cfg.currency.entries.ender_eye.unitsPerItem=1
-- A policy with insufficient backing cannot reprice away already-issued credits.
local illiquid=store.copy(api:state()); illiquid.accounts['house-1'].balance=illiquid.bank-15
local proposal=store.copy(policy); proposal.revision=4; proposal.entries.diamond.unitsPerItem=1
check(not pcall(ledger.changeCurrency,illiquid,proposal,illiquid.stock),'rate reduction cannot erase backing')
-- Removing the newest v2 generation must not fall back past a transfer/receipt.
local bytes0,bytes1=platform.files['/bank.0'],platform.files['/bank.1']
local a0=textutils.unserializeJSON(bytes0); local a1=textutils.unserializeJSON(bytes1)
local latest=a0.seq>a1.seq and '/bank.0' or '/bank.1'
platform.files[latest]='{corrupt'
check(not pcall(store.open,'/bank',{}),'v2 corruption cannot erase durable intent by fallback')
platform.files['/bank.0'],platform.files['/bank.1']=bytes0,bytes1
-- Sequence corruption in an old otherwise-checksummed envelope cannot fake newest.
local older=a0.seq<a1.seq and '/bank.0' or '/bank.1'
local oldEnvelope=textutils.unserializeJSON(platform.files[older]); oldEnvelope.seq=math.max(a0.seq,a1.seq)+100
platform.files[older]=textutils.serializeJSON(oldEnvelope)
check(not pcall(store.open,'/bank',{}),'old envelope cannot bypass guard by forged higher sequence')
platform.files['/bank.0'],platform.files['/bank.1']=bytes0,bytes1
local guarded=store.open('/bank',{}):get(); eq(guarded.currency.revision,3)
-- Non-destructive downgrade guard across currency revisions.
local v2r3=store.open('/bank',{}):get(); eq(v2r3.currency.revision,3)
platform.files['/bank.0']=legacy0; platform.files['/bank.1']=legacy1
check(not pcall(store.open,'/bank',{}),'legacy restore fails against version marker')
-- Exact arithmetic, invalid rates and caps.
local bad=store.copy(policy); bad.entries.gold.unitsPerItem=.5; check(not pcall(currency.validate,bad),'fractional atomic rate rejected')
check(not pcall(currency.quote,policy.entries.diamond,1000000000,policy),'transfer units cap')
-- Future/missing versions must never be interpreted as legacy diamond state.
for _,version in ipairs({99,0,false}) do
 local unknown=store.copy(initial); unknown.version=version or nil
 check(not pcall(service.new,{get=function() return store.copy(unknown) end},cfg,function(n) return inventories[n] end),'unsupported saved version refuses host startup')
 check(not pcall(ledger.changeCurrency,unknown,currency.default(),{diamond=100}),'unsupported migration source rejected')
 check(not ledger.apply(unknown,{op='create',id='x'}).ok,'unsupported ledger mutation rejected')
end
-- Inject failure on each migration write boundary. Backups remain untouched;
-- either legacy state survives or the guard blocks/reopens exact v2 state.
for failAt=1,7 do
 local path='/migration-'..failAt
 local original=ledger.new(); original.paused=true; original.bank=10
 local storage=store.open(path,original); storage:save(original); storage:save(original)
 local old0,old1=platform.files[path..'.0'],platform.files[path..'.1']
 local nextState=ledger.changeCurrency(original,currency.default(),{diamond=10})
 local realOpen=fs.open; local writes=0
 fs.open=function(name,mode)
  if mode=='w' then writes=writes+1; if writes==failAt then error('Injected migration write failure') end end
  return realOpen(name,mode)
 end
 local ok=pcall(function() storage:changeCurrency(nextState) end); fs.open=realOpen
 check(not ok,'injected migration failure occurred')
 local loaded,result=pcall(store.open,path,{})
 if loaded then local restored=result:get(); check(restored.version==1 or (restored.version==2 and restored.bank==10),'only coherent legacy/new state restored') end
 if platform.files[path..'.backup-v1.0'] then eq(platform.files[path..'.backup-v1.0'],old0,'backup never rewritten') end
 if platform.files[path..'.backup-v1.1'] then eq(platform.files[path..'.backup-v1.1'],old1,'backup never rewritten') end
end
print('PASS '..passed..' production currency assertions (mock inventories, no hardware acceptance)')
