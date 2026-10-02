-- Integer-credit policy. Rates are operator choices, never inferred from recipes.
local M={schema='pine-currency-policy',schemaVersion=1,maxExactInteger=9007199254740991,maxTransferUnits=1000000000}
local function integer(v) return type(v)=='number' and v==v and v>=0 and v<=M.maxExactInteger and v%1==0 end
local function positive(v) return integer(v) and v>0 end
local function text(v) return type(v)=='string' and #v>0 end
local function registry(v) return text(v) and v:match('^[a-z0-9_.%-]+:[a-z0-9_./%-]+$')~=nil end
local function fields(t,allowed,message)
 assert(type(t)=='table',message)
 for key in pairs(t) do assert(allowed[key],message..': '..tostring(key)) end
end
local function array(t,predicate,message)
 assert(type(t)=='table',message)
 local n=0
 for k,v in pairs(t) do assert(positive(k) and predicate(v),message); n=n+1 end
 for i=1,n do assert(t[i]~=nil,message) end
 assert(n==#t,message)
end
local function contains(list,value)
 for _,v in ipairs(list) do if v==value then return true end end
 return false
end
-- These are documented, scalar top-level getItemDetail fields. Unknown mod fields
-- need an explicit adapter extension, not a guessed extraction rule. NBT remains
-- an exact peripheral-provided fingerprint; no hash algorithm is assumed.
local metadataTypes={damage='number',maxDamage='number',unbreakable='boolean'}
local function identity(id)
 fields(id,{allowNoNbt=true,nbtHashes=true,metadata=true},'Invalid identity rule')
 assert(type(id.allowNoNbt)=='boolean','Explicit plain-item permission required')
 array(id.nbtHashes,text,'Explicit NBT fingerprint allowlist required')
 assert(id.allowNoNbt or #id.nbtHashes>0,'Identity must admit at least one variant')
 local seen={}
 for _,hash in ipairs(id.nbtHashes) do assert(not seen[hash],'Duplicate NBT fingerprint'); seen[hash]=true end
 assert(type(id.metadata)=='table','Explicit metadata allowlist required')
 for field,allowed in pairs(id.metadata) do
  local kind=metadataTypes[field]
  assert(kind,'Unsupported metadata field: '..tostring(field))
  array(allowed,function(v) return type(v)==kind and (kind~='number' or integer(v)) end,'Invalid metadata allowlist')
  assert(#allowed>0,'Empty metadata allowlist')
 end
end
local function entry(e,limit)
 fields(e,{itemId=true,depositEnabled=true,redeemEnabled=true,unitsPerItem=true,identity=true},'Invalid currency entry field')
 assert(registry(e.itemId),'Exact lowercase namespaced item ID required')
 assert(type(e.depositEnabled)=='boolean' and type(e.redeemEnabled)=='boolean','Explicit deposit and redemption flags required')
 if e.unitsPerItem==nil then
  assert(not e.depositEnabled and not e.redeemEnabled,'Enabled currency needs an explicit rate')
 else
  assert(positive(e.unitsPerItem) and e.unitsPerItem<=limit,'Rate must be positive integer credits within the transfer limit')
 end
 identity(e.identity)
 return e
end
function M.validate(p)
 fields(p,{schema=true,schemaVersion=true,policyId=true,revision=true,creditScale=true,maxTransferUnits=true,entries=true},'Invalid currency policy field')
 assert(p.schema==M.schema and p.schemaVersion==M.schemaVersion,'Unsupported currency policy schema')
 assert(text(p.policyId) and #p.policyId<=160 and positive(p.revision),'Invalid policy identity or revision')
 assert(p.creditScale==1,'This implementation supports whole credits only (creditScale=1)')
 assert(positive(p.maxTransferUnits) and p.maxTransferUnits<=M.maxTransferUnits,'Invalid transfer-unit limit')
 assert(type(p.entries)=='table' and next(p.entries),'Currency policy needs entries')
 local used={}
 for key,e in pairs(p.entries) do
  assert(text(key) and #key<=80 and key:match('^[a-z0-9_.%-]+$'),'Exact entry ID required')
  entry(e,p.maxTransferUnits)
  assert(not used[e.itemId],'Duplicate registry ID in currency policy')
  used[e.itemId]=true
 end
 return p
end
function M.default()
 local function plain() return {allowNoNbt=true,nbtHashes={},metadata={}} end
 return {schema=M.schema,schemaVersion=M.schemaVersion,policyId='pine-house-credits',revision=1,creditScale=1,maxTransferUnits=M.maxTransferUnits,
  entries={
   diamond={itemId='minecraft:diamond',depositEnabled=true,redeemEnabled=true,unitsPerItem=1,identity=plain()},
   gold={itemId='minecraft:gold_ingot',depositEnabled=false,redeemEnabled=false,identity=plain()},
   ender_eye={itemId='minecraft:ender_eye',depositEnabled=false,redeemEnabled=false,identity=plain()},
  }}
end
-- Both normalized records and CC:Tweaked details are accepted. Never use display
-- names/tags to identify an item. The documented NBT fingerprint covers variant
-- properties (including enchantments/lore); these display projections are ignored.
-- Reference: https://tweaked.cc/reference/item_details.html (verified 2026-10-01).
local rawFields={name=true,count=true,nbt=true,damage=true,maxDamage=true,unbreakable=true,
 displayName=true,lore=true,maxCount=true,tags=true,itemGroups=true,durability=true,
 enchantments=true,potionEffects=true,mapColour=true,mapColor=true}
local normalizedFields={name=true,count=true,nbt=true,metadata=true}
function M.normalize(item)
 if type(item)~='table' then return nil,'Item details required' end
 local normalized=item.metadata~=nil
 for key in pairs(item) do
  if not (normalized and normalizedFields[key] or not normalized and rawFields[key]) then return nil,'Unrecognized item detail field: '..tostring(key) end
 end
 if not registry(item.name) or (item.count~=nil and not integer(item.count)) or (item.nbt~=nil and not text(item.nbt)) then return nil,'Invalid item name, count or NBT fingerprint' end
 local metadata={}
 if normalized then
  if type(item.metadata)~='table' then return nil,'Normalized metadata must be a table' end
  for key,v in pairs(item.metadata) do metadata[key]=v end
 else
  for key in pairs(metadataTypes) do if item[key]~=nil then metadata[key]=item[key] end end
 end
 for key,v in pairs(metadata) do
  if not metadataTypes[key] or type(v)~=metadataTypes[key] or (type(v)=='number' and not integer(v)) then return nil,'Unsupported or invalid item metadata' end
 end
 return {name=item.name,count=item.count,nbt=item.nbt,metadata=metadata}
end
function M.match(e,item)
 local ok,why=pcall(entry,e,M.maxTransferUnits)
 if not ok then return false,why end
 local observed,problem=M.normalize(item)
 if not observed then return false,problem end
 if observed.name~=e.itemId then return false,'Registry ID does not match' end
 if observed.nbt==nil then
  if not e.identity.allowNoNbt then return false,'Plain item is not admitted' end
 elseif not contains(e.identity.nbtHashes,observed.nbt) then return false,'NBT fingerprint is not admitted' end
 for key,allowed in pairs(e.identity.metadata) do
  if not contains(allowed,observed.metadata[key]) then return false,'Required metadata is missing or disallowed' end
 end
 for key in pairs(observed.metadata) do
  if e.identity.metadata[key]==nil then return false,'Metadata field is not admitted' end
 end
 return true
end
function M.quote(e,count,p)
 M.validate(p); entry(e,p.maxTransferUnits)
 assert(positive(e.unitsPerItem),'Currency has no configured rate')
 assert(integer(count) and count<=math.floor(p.maxTransferUnits/e.unitsPerItem),'Item count exceeds exact transfer-unit limit')
 return count*e.unitsPerItem
end
function M.value(p,stock)
 M.validate(p)
 assert(type(stock)=='table','Classified stock required')
 local total=0
 for key,count in pairs(stock) do
  local e=p.entries[key]
  assert(e and integer(count),'Unknown entry or invalid stock count')
  if e.unitsPerItem==nil then
   assert(count==0,'Unpriced items cannot count as backing')
  else
   assert(count<=math.floor((M.maxExactInteger-total)/e.unitsPerItem),'Inventory valuation overflow')
   total=total+count*e.unitsPerItem
  end
 end
 return total
end
-- Length-delimited encoding avoids delimiter collisions in policy/receipt pins.
-- Numeric formatting gives 1 and 1.0 the same canonical representation.
function M.canonical(value)
 local active={}
 local function encode(v)
  local kind=type(v)
  if kind=='nil' then return 'z' end
  if kind=='boolean' then return v and 'b1' or 'b0' end
  if kind=='string' then return 's'..#v..':'..v end
  if kind=='number' then
   assert(v==v and v~=math.huge and v~=-math.huge,'Nonfinite canonical number')
   if v==0 then v=0 end
   return 'n'..string.format('%.17g',v)..';'
  end
  assert(kind=='table' and not active[v],'Unsupported or cyclic canonical value')
  active[v]=true
  local keys={}
  for key in pairs(v) do
   assert(type(key)=='string' or type(key)=='number' or type(key)=='boolean','Unsupported canonical key')
   keys[#keys+1]={encoded=encode(key),key=key}
  end
  table.sort(keys,function(a,b) return a.encoded<b.encoded end)
  local out={'t',tostring(#keys),':'}
  for _,key in ipairs(keys) do out[#out+1]=key.encoded; out[#out+1]=encode(v[key.key]) end
  active[v]=nil
  return table.concat(out)
 end
 return encode(value)
end
return M
