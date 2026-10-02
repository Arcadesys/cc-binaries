-- The host alone moves items. There is no automatic retry after an uncertain transfer.
local currency=require('derby.currency')
local M={}
-- Legacy v1 intentionally keeps its historical diamond-only interpretation.
function M.count(inv)
 local n=0
 for _,item in pairs(inv.list()) do if item.name=='minecraft:diamond' then n=n+item.count end end
 return n
end
local function integer(v) return type(v)=='number' and v==v and v>=0 and v<=currency.maxExactInteger and v%1==0 end
local function listed(inv)
 assert(type(inv)=='table' and type(inv.list)=='function','Inventory list unavailable')
 local items=inv.list(); assert(type(items)=='table','Invalid inventory list')
 local slots={}
 for slot,item in pairs(items) do
  assert(integer(slot) and slot>0,'Invalid inventory slot')
  assert(type(item)=='table' and type(item.name)=='string' and integer(item.count) and item.count>0,'Invalid listed item')
  assert(item.nbt==nil or (type(item.nbt)=='string' and #item.nbt>0),'Invalid listed NBT fingerprint')
  slots[#slots+1]=slot
 end
 table.sort(slots)
 return items,slots
end
local function detail(inv,slot,basic)
 assert(type(inv.getItemDetail)=='function','Detailed inventory identity unavailable')
 local item=inv.getItemDetail(slot)
 -- A stale read cannot establish a stable before/after inventory snapshot.
 assert(type(item)=='table' and item.name==basic.name and item.count==basic.count and item.nbt==basic.nbt,'Inventory changed during identity inspection')
 return item
end
-- CC:Tweaked list supplies name/count/optional nbt; configured scalar metadata
-- comes from getItemDetail. A missing detail or a disagreement aborts the scan.
-- Only priced, admitted entries count as backing, even when exchange-disabled.
-- References: https://tweaked.cc/generic_peripheral/inventory.html and
-- https://tweaked.cc/reference/item_details.html (verified 2026-10-01).
function M.stock(inv,policy)
 currency.validate(policy)
 local stock,byItem={},{}
 for id,e in pairs(policy.entries) do
  if e.unitsPerItem then stock[id]=0; byItem[e.itemId]={id=id,entry=e} end
 end
 local items,slots=listed(inv)
 for _,slot in ipairs(slots) do
  local basic=items[slot]; local selected=byItem[basic.name]
  if selected then
   local observed=detail(inv,slot,basic)
   if currency.match(selected.entry,observed) then
    assert(basic.count<=currency.maxExactInteger-stock[selected.id],'Inventory item-count overflow')
    stock[selected.id]=stock[selected.id]+basic.count
   end
  end
 end
 return stock
end
function M.move(source,destinationName,amount,entry)
 if entry==nil then
  -- Preserve the old public adapter for the v1 service until explicit migration.
  local moved=0
  local slots={}; for slot in pairs(source.list()) do slots[#slots+1]=slot end; table.sort(slots)
  for _,slot in ipairs(slots) do
   local item=source.getItemDetail(slot)
   if item and item.name=='minecraft:diamond' and moved<amount then
    local n=source.pushItems(destinationName,slot,math.min(item.count,amount-moved))
    assert(type(n)=='number' and n>=0 and n%1==0 and n<=amount-moved,'Invalid inventory transfer receipt')
    moved=moved+n
   end
  end
  return moved
 end
 assert(integer(amount) and amount<=currency.maxTransferUnits,'Invalid requested item count')
 assert(type(destinationName)=='string' and #destinationName>0,'Destination inventory name required')
 assert(type(source)=='table' and type(source.pushItems)=='function','Inventory movement unavailable')
 assert(type(entry)=='table' and integer(entry.unitsPerItem) and entry.unitsPerItem>0,'Priced currency entry required')
 assert(entry.depositEnabled==true or entry.redeemEnabled==true,'Currency exchange is disabled')
 local moved=0
 local items,slots=listed(source)
 for _,slot in ipairs(slots) do
  if moved>=amount then break end
  local basic=items[slot]
  if basic.name==entry.itemId then
   local item=detail(source,slot,basic)
   if currency.match(entry,item) then
    local limit=math.min(item.count,amount-moved)
    local n=source.pushItems(destinationName,slot,limit)
    assert(integer(n) and n<=limit,'Invalid inventory transfer receipt')
    moved=moved+n
   end
  end
 end
 -- This number is not an identity proof. The service must verify both classified
 -- source and destination deltas before crediting/debiting. Controlled physical
 -- access is required: getItemDetail + pushItems is not an atomic operation.
 return moved
end
return M
