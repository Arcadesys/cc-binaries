-- Production currency/adapter assertions with fictional inventories only.
-- These tests do not establish hardware, modpack, or deployed-item acceptance.
local currency=require('derby.currency')
local inventory=require('derby.inventory')
local oracle=require('tests.contracts.currency_policy')
local checks=0
local function check(v,message) checks=checks+1; assert(v,message) end
local function eq(a,b,message) check(a==b,(message or '')..': expected '..tostring(b)..', got '..tostring(a)) end
local function rejects(fn,message) check(not pcall(fn),message) end
local function copy(v)
 if type(v)~='table' then return v end
 local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
end
local p=currency.default()
eq(currency.validate(p),p,'validation returns policy')
eq(p.schema,'pine-currency-policy','production schema')
eq(p.revision,1,'default revision')
eq(p.creditScale,1,'single integer scale')
eq(p.entries.diamond.unitsPerItem,1,'existing credit denomination')
eq(p.entries.gold.unitsPerItem,nil,'gold rate is unset')
eq(p.entries.ender_eye.unitsPerItem,nil,'ender eye rate is unset')
check(not p.entries.gold.depositEnabled and not p.entries.gold.redeemEnabled,'gold disabled in both directions')
check(not p.entries.ender_eye.depositEnabled and not p.entries.ender_eye.redeemEnabled,'ender eye disabled in both directions')
local fresh=currency.default(); fresh.entries.diamond.identity.nbtHashes[1]='only-this-copy'
eq(#p.entries.diamond.identity.nbtHashes,0,'defaults are independent copies')
for _,mutate in ipairs({
 function(v) v.schema='pine-currency-policy-proposal' end,
 function(v) v.schemaVersion=2 end,
 function(v) v.revision=0 end,
 function(v) v.revision=0/0 end,
 function(v) v.policyId='' end,
 function(v) v.creditScale=100 end,
 function(v) v.maxTransferUnits=1000000001 end,
 function(v) v.maxTransferUnits=0 end,
 function(v) v.entries={} end,
 function(v) v.entries.diamond.itemId='Minecraft:diamond' end,
 function(v) v.entries.diamond.itemId='minecraft:*' end,
 function(v) v.entries.gold.itemId='minecraft:diamond' end,
 function(v) v.entries.diamond.depositEnabled=nil end,
 function(v) v.entries.gold.depositEnabled=true end,
 function(v) v.entries.gold.redeemEnabled=true end,
 function(v) v.entries.gold.unitsPerItem=0 end,
 function(v) v.entries.diamond.unitsPerItem=.5 end,
 function(v) v.entries.diamond.unitsPerItem=math.huge end,
 function(v) v.entries.diamond.unitsPerItem=1000000001 end,
 function(v) v.entries.diamond.identity.allowNoNbt=false end,
 function(v) v.entries.diamond.identity.nbtHashes={one='hash'} end,
 function(v) v.entries.diamond.identity.nbtHashes={[2]='hash'} end,
 function(v) v.entries.diamond.identity.nbtHashes={'hash','hash'} end,
 function(v) v.entries.diamond.identity.metadata={damage={}} end,
 function(v) v.entries.diamond.identity.metadata={damage={-1}} end,
 function(v) v.entries.diamond.identity.metadata={damage={.5}} end,
 function(v) v.entries.diamond.identity.metadata={unbreakable={'yes'}} end,
 function(v) v.entries.diamond.identity.metadata={customDamage={0}} end,
 function(v) v.entries.diamond.identity.allowAnyNbt=true end,
 function(v) v.entries.diamond.tag='forge:diamonds' end,
 function(v) v.allowConversion=true end,
}) do
 local invalid=copy(p); mutate(invalid)
 rejects(function() currency.validate(invalid) end,'invalid policy rejected')
end
local both=copy(p); both.entries.gold.unitsPerItem=3; both.entries.gold.depositEnabled=true
check(currency.validate(both),'deposit-only valid')
both.entries.gold.depositEnabled=false; both.entries.gold.redeemEnabled=true
check(currency.validate(both),'redeem-only valid')
both.entries.gold.redeemEnabled=false
check(currency.validate(both),'retained priced exchange-disabled valid')
eq(currency.value(both,{diamond=2,gold=4}),14,'retained priced stock still backs credits')
eq(currency.value(p,{gold=0}),0,'explicit zero unpriced stock safe')
rejects(function() currency.value(p,{gold=1}) end,'unpriced positive stock rejected')
rejects(function() currency.quote(p.entries.gold,1,p) end,'unpriced quote rejected')
eq(currency.quote(p.entries.diamond,0,p),0,'zero confirmed movement has zero value')
eq(currency.quote(p.entries.diamond,1000000000,p),1000000000,'transfer boundary exact')
for _,count in ipairs({-1,.5,math.huge,1000000001}) do
 rejects(function() currency.quote(p.entries.diamond,count,p) end,'invalid count rejected')
end
rejects(function() currency.quote(p.entries.diamond,0/0,p) end,'NaN count rejected')
eq(currency.quote(both.entries.gold,333333333,both),999999999,'weighted transfer below cap exact')
rejects(function() currency.quote(both.entries.gold,333333334,both) end,'weighted transfer above cap rejected')
eq(currency.value(p,{diamond=currency.maxExactInteger}),currency.maxExactInteger,'max exact backing boundary')
rejects(function() currency.value(p,{diamond=currency.maxExactInteger+1}) end,'backing count overflow rejected')
rejects(function() currency.value(both,{diamond=currency.maxExactInteger,gold=1}) end,'aggregate backing overflow rejected')
rejects(function() currency.value(both,{gold=3002399751580331}) end,'product backing overflow rejected')
rejects(function() currency.value(p,{unknown=0}) end,'unknown stock entry rejected')

local diamond=p.entries.diamond
check(currency.match(diamond,{name='minecraft:diamond',count=3}),'plain raw item admitted')
check(currency.match(diamond,{name='minecraft:diamond',count=3,metadata={}}),'plain normalized item admitted')
check(currency.match(diamond,{name='minecraft:diamond',count=3,displayName='Display only',maxCount=64,tags={['forge:gems']=true},itemGroups={}}),'known presentation fields ignored')
check(not currency.match(diamond,{name='minecraft:diamond_block',count=1}),'no automatic block equivalence')
check(not currency.match(diamond,{name='minecraft:gold_ingot',displayName='Diamond',count=1}),'display-name spoof rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=1,nbt='renamed'}),'unapproved NBT rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=1,nbt=''}),'empty NBT rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=-1}),'negative observed count rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=1,components={}}),'unknown raw identity field rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=1,metadata={},displayName='Diamond'}),'mixed raw and normalized fields rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=1,metadata={damage=0}}),'unconfigured scalar metadata rejected')
check(not currency.match(diamond,{name='minecraft:diamond',count=1,damage=0}),'unconfigured raw scalar metadata rejected')
local token=copy(oracle.syntheticPolicy.entries.token)
check(currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',metadata={damage=0}}),'oracle allowlisted normalized token admitted')
check(currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',damage=0,displayName='Token'}),'raw top-level metadata normalized')
check(not currency.match(token,{name=token.itemId,count=1,damage=0}),'required NBT cannot be omitted')
check(not currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT'}),'required metadata cannot be omitted')
check(not currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',damage=1}),'wrong metadata rejected')
check(not currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',damage=0,maxDamage=10}),'extra documented metadata requires explicit admission')
check(not currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',metadata={damage=0,customDamage=0}}),'unknown normalized metadata rejected')
token.identity.metadata.maxDamage={10}; token.identity.metadata.unbreakable={true}
check(currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',damage=0,maxDamage=10,unbreakable=true}),'all explicit documented metadata admitted')
check(not currency.match(token,{name=token.itemId,count=1,nbt='SYNTHETIC-NBT-FINGERPRINT',damage=0,maxDamage=10,unbreakable=false}),'boolean metadata checked exactly')
local multi=copy(diamond); multi.identity.nbtHashes={'a','b'}
check(currency.match(multi,{name=multi.itemId,nbt='a'}) and currency.match(multi,{name=multi.itemId,nbt='b'}),'multiple explicit fingerprints admitted')
check(not currency.match(multi,{name=multi.itemId,nbt='A'}),'fingerprints are exact case-sensitive strings')

local function inv(items)
 local obj={items=copy(items),calls={},details={}}
 function obj.list()
  local out={}
  for slot,item in pairs(obj.items) do out[slot]={name=item.name,count=item.count,nbt=item.nbt} end
  return out
 end
 function obj.getItemDetail(slot) obj.details[#obj.details+1]=slot; return copy(obj.items[slot]) end
 function obj.pushItems(destination,slot,limit)
  obj.calls[#obj.calls+1]={destination=destination,slot=slot,limit=limit}
  local moved=math.min(limit,obj.items[slot].count,obj.capacity or limit)
  obj.items[slot].count=obj.items[slot].count-moved
  if obj.items[slot].count==0 then obj.items[slot]=nil end
  return moved
 end
 return obj
end
local source=inv({[2]={name='minecraft:diamond',count=2},[9]={name='minecraft:diamond',count=3},
 [14]={name='minecraft:diamond',count=50,nbt='unapproved'},[21]={name='minecraft:gold_ingot',count=12},[30]={name='minecraft:dirt',count=64}})
eq(inventory.stock(source,p).diamond,5,'sparse admitted stock counted')
eq(inventory.stock(source,p).gold,nil,'unpriced disabled stock omitted')
eq(inventory.count(source),55,'legacy diamond count includes old NBT behavior')
eq(inventory.stock(source,both).gold,12,'priced disabled stock classified')
eq(inventory.move(source,'bank',4,diamond),4,'strict sparse movement')
eq(source.calls[1].slot,2,'slots sorted ascending')
eq(source.calls[2].slot,9,'next sparse slot moved')
eq(source.calls[2].limit,2,'remaining count caps final slot')
eq(source.items[9].count,1,'partial source count exact')
eq(source.items[14].count,50,'unapproved NBT never moved')
eq(inventory.stock(source,p).diamond,1,'post-move admitted stock exact')
source=inv({[8]={name='minecraft:diamond',count=5,nbt='unapproved'}})
eq(inventory.move(source,'bank',2,diamond),0,'wrong identity reports zero')
eq(#source.calls,0,'wrong identity never invokes push')
eq(inventory.move(source,'bank',2),2,'legacy move remains compatible')
source=inv({[4]={name='minecraft:diamond',count=7}}); source.capacity=0
eq(inventory.move(source,'bank',5,diamond),0,'full destination reports zero')
source.capacity=3
eq(inventory.move(source,'bank',5,diamond),3,'partial movement receipt exact')
source=inv({[4]={name='minecraft:diamond',count=7}})
eq(inventory.move(source,'bank',0,diamond),0,'zero transfer no movement')
eq(#source.calls,0,'zero transfer never invokes push')
for _,mutation in ipairs({
 function(x) x.name='minecraft:dirt' end,
 function(x) x.count=6 end,
 function(x) x.nbt='changed' end,
}) do
 source=inv({[1]={name='minecraft:diamond',count=7}})
 source.getItemDetail=function() local x=copy(source.items[1]); mutation(x); return x end
 rejects(function() inventory.stock(source,p) end,'stale stock read fails closed')
 rejects(function() inventory.move(source,'bank',1,diamond) end,'stale movement read fails closed')
 eq(#source.calls,0,'stale identity never invokes push')
end
source=inv({[1]={name='minecraft:diamond',count=7}}); source.getItemDetail=function() return nil end
rejects(function() inventory.stock(source,p) end,'missing details fail closed')
source.getItemDetail=nil
rejects(function() inventory.stock(source,p) end,'missing detail API fails closed')
for _,receipt in ipairs({-1,.5,2,math.huge}) do
 source=inv({[1]={name='minecraft:diamond',count=1}}); source.pushItems=function() return receipt end
 rejects(function() inventory.move(source,'bank',5,diamond) end,'receipt cannot exceed per-slot limit or be invalid')
end
source=inv({[1]={name='minecraft:diamond',count=1}}); source.pushItems=function() return 0/0 end
rejects(function() inventory.move(source,'bank',1,diamond) end,'NaN receipt rejected')
source.pushItems=function() return nil end
rejects(function() inventory.move(source,'bank',1,diamond) end,'missing receipt rejected')
rejects(function() inventory.move(source,'bank',1,both.entries.gold) end,'exchange-disabled entry cannot move')
source=inv({[1]={name='minecraft:diamond',count=currency.maxExactInteger},[2]={name='minecraft:diamond',count=1}})
rejects(function() inventory.stock(source,p) end,'stock count aggregate overflow rejected')
source=inv({}); source.list=function() return {[0]={name='minecraft:diamond',count=1}} end
rejects(function() inventory.stock(source,p) end,'invalid slot rejected')
source.list=function() return {[1]={name='minecraft:diamond',count=0}} end
rejects(function() inventory.stock(source,p) end,'invalid listed zero count rejected')

local a={a='x;string:b=y',b='z'}; local b={b='z',a='x;string:b=y'}
eq(currency.canonical(a),currency.canonical(b),'canonical key order stable')
eq(currency.canonical(1),currency.canonical(1.0),'equal numeric encodings stable')
check(currency.canonical({a='x;b=y'})~=currency.canonical({a='x',b='y'}),'delimiters cannot collide')
check(currency.canonical({a=true})~=currency.canonical({a='true'}),'value types cannot collide')
local cycle={}; cycle.self=cycle
rejects(function() currency.canonical(cycle) end,'cyclic canonical input rejected')
rejects(function() currency.canonical({value=0/0}) end,'NaN canonical input rejected')
print(('PASS currency identity and inventory (%d assertions; mocks only, no hardware acceptance)'):format(checks))
return checks
