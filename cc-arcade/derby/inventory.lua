-- The host alone moves items. There is no automatic retry after an uncertain transfer.
local M={}
function M.count(inv)
 local n=0
 for _,item in pairs(inv.list()) do if item.name=='minecraft:diamond' then n=n+item.count end end
 return n
end
function M.move(source,destinationName,amount)
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
return M
