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
 local state,selectedChecksum
 local seen=false
 for slot=0,1 do
  local path=base..'.'..slot
  if fs.exists(path) then
   seen=true
   local f=fs.open(path,'r'); local data=f and f.readAll(); if f then f.close() end
   local ok,v=pcall(textutils.unserializeJSON,data or '')
   if ok and type(v)=='table' and type(v.payload)=='string' and type(v.seq)=='number' and checksum(v.payload)==v.checksum then
    local good,p=pcall(textutils.unserializeJSON,v.payload)
    if good and type(p)=='table' and v.seq>seq then state=p; seq=v.seq; selectedChecksum=checksum(v.payload) end
   end
  end
 end
 assert(state or not seen,'Both saved state slots are invalid; restore backup. No new bank was created.')
 state=state or M.copy(initial)
 local marker=base..'.currency-version'
 if fs.exists(marker) then
  local f=assert(fs.open(marker,'r')); local floor=textutils.unserializeJSON(f.readAll()); f.close()
  assert(type(floor)=='table' and floor.version==2
   and type(floor.revision)=='number' and floor.revision>=1 and floor.revision%1==0
   and type(floor.seq)=='number' and floor.seq>=0 and floor.seq%1==0
   and type(floor.checksum)=='number' and floor.checksum==selectedChecksum
   and state.version==2 and state.currency and state.currency.revision==floor.revision and seq==floor.seq,
   'Currency generation guard mismatch; restore verified versioned backup offline')
 end
 assert(state.version~=2 or fs.exists(marker),'Version 2 currency generation guard missing; offline recovery required')
 local api={}
 function api:get() return M.copy(state) end
 function api:save(value)
  local payload=textutils.serializeJSON(M.copy(value))
  if value.version==2 then
   -- A v2 generation rollback could erase an intent and replay physical movement.
   -- Persist a fail-closed floor BEFORE every generation write. Interrupted writes
   -- may require offline recovery, but never silently revive an older receipt.
   local boundary=textutils.serializeJSON({version=2,revision=value.currency.revision,seq=seq+1,checksum=checksum(payload)})
   fs.makeDir(fs.getDir(base))
   local guard=assert(fs.open(marker,'w')); guard.write(boundary); guard.close()
   guard=assert(fs.open(marker,'r')); local actual=guard.readAll(); guard.close()
   assert(actual==boundary,'Currency generation guard readback failed')
  end
  local path=base..'.'..((seq+1)%2)
  fs.makeDir(fs.getDir(base))
  local f=assert(fs.open(path,'w'),'Cannot persist '..path)
  f.write(textutils.serializeJSON({seq=seq+1,payload=payload,checksum=checksum(payload)})); f.close()
  local verify=assert(fs.open(path,'r')); local disk=textutils.unserializeJSON(verify.readAll()); verify.close()
  assert(disk and disk.seq==seq+1 and disk.payload==payload and disk.checksum==checksum(payload),'Persistence readback failed')
  seq=seq+1; state=M.copy(value)
 end
 function api:changeCurrency(value)
  assert(value.version==2,'Expected version 2 currency state')
  -- Preserve both exact old generations before changing the interpretation of bank.
  local tag=state.version==2 and ('v2-r'..state.currency.revision) or 'v1'
  for slot=0,1 do
   local source=base..'.'..slot
   if fs.exists(source) then
    local f=assert(fs.open(source,'r')); local bytes=f.readAll(); f.close()
    local target=base..'.backup-'..tag..'.'..slot
    if fs.exists(target) then
     f=assert(fs.open(target,'r')); local old=f.readAll(); f.close()
     assert(old==bytes,'Existing migration backup differs; archive it offline before retry')
    else
     f=assert(fs.open(target,'w')); f.write(bytes); f.close()
     f=assert(fs.open(target,'r')); local verified=f.readAll(); f.close(); assert(verified==bytes,'Backup readback failed')
    end
   end
  end
  fs.makeDir(fs.getDir(base))
  local f=assert(fs.open(marker,'w')); local boundary=textutils.serializeJSON({version=2,revision=value.currency.revision}); f.write(boundary); f.close()
  f=assert(fs.open(marker,'r')); local verified=f.readAll(); f.close(); assert(verified==boundary,'Version marker readback failed')
  -- Both generations must use the new interpretation before restart fallback is safe.
  self:save(value); self:save(value)
 end
 return api
end
return M
