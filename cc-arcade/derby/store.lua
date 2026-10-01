-- Two generation slots: interrupted writes leave the previous committed state.
local M={}
local function checksum(s)
 local n=0
 for i=1,#s do n=(n*31+s:byte(i))%2147483647 end
 return n
end
function M.copy(t)
 if type(t)~='table' then return t end
 local out={}; for k,v in pairs(t) do out[M.copy(k)]=M.copy(v) end
 return out
end
function M.open(base, initial)
 local seq=0
 local state
 local seen=false
 for slot=0,1 do
  local path=base..'.'..slot
  if fs.exists(path) then
   seen=true
   local f=fs.open(path,'r'); local data=f and f.readAll(); if f then f.close() end
   local ok,v=pcall(textutils.unserializeJSON,data or '')
   if ok and type(v)=='table' and type(v.payload)=='string' and type(v.seq)=='number' and checksum(v.payload)==v.checksum then
    local good,p=pcall(textutils.unserializeJSON,v.payload)
    if good and type(p)=='table' and v.seq>seq then state=p; seq=v.seq end
   end
  end
 end
 assert(state or not seen,'Both saved state slots are invalid; restore backup. No new bank was created.')
 state=state or M.copy(initial)
 local api={}
 function api:get() return M.copy(state) end
 function api:save(value)
  local payload=textutils.serializeJSON(M.copy(value))
  local path=base..'.'..((seq+1)%2)
  fs.makeDir(fs.getDir(base))
  local f=assert(fs.open(path,'w'),'Cannot persist '..path)
  f.write(textutils.serializeJSON({seq=seq+1,payload=payload,checksum=checksum(payload)})); f.close()
  local verify=assert(fs.open(path,'r')); local disk=textutils.unserializeJSON(verify.readAll()); verify.close()
  assert(disk and disk.payload==payload and disk.checksum==checksum(payload),'Persistence readback failed')
  seq=seq+1; state=M.copy(value)
 end
 return api
end
return M
