local M={path='/house-config.json'}
function M.read()
 if not fs.exists(M.path) then return nil end
 local f=assert(fs.open(M.path,'r')); local c=textutils.unserializeJSON(f.readAll()); f.close(); return c
end
function M.write(c)
 local f=assert(fs.open(M.path,'w')); f.write(textutils.serializeJSON(c)); f.close()
end
function M.network(c)
 assert(c and c.modem,'Run house setup first')
 local modem=assert(peripheral.wrap(c.modem),'Configured modem missing')
 assert(modem.isWireless and not modem.isWireless(),'Use the house wired modem')
 rednet.open(c.modem)
end
function M.setup(role,modem,host)
 assert(role=='host' or role=='station' or role=='display' or role=='cashier','Role: host, station, display or cashier')
 assert(not M.read(),'Configuration exists; back up and remove /house-config.json to reconfigure')
 local function ask(label) write(label..': '); return read() end
 local c={role=role,modem=modem or ask('Wired modem name')}
 M.network(c)
 if role=='host' then
  c.bank=ask('Bank inventory peripheral'); c.intake=ask('Cashier intake inventory'); c.payout=ask('Cashier output inventory')
  assert(c.bank~=c.intake and c.bank~=c.payout and c.intake~=c.payout,'Inventories must be separate')
  for _,name in ipairs({c.bank,c.intake,c.payout}) do
   local p=assert(peripheral.wrap(name),'Inventory unavailable: '..name); assert(p.list and p.pushItems,'Not an inventory: '..name)
  end
  c.clients={}
  for _,r in ipairs({'station','display','cashier'}) do
   local ids=ask(r..' computer IDs (comma separated)')
   for id in ids:gmatch('%d+') do assert(not c.clients[id],'Duplicate client ID'); c.clients[id]=r end
  end
  c.enabled=false
  c.currency=require('derby.currency').default()
 else c.host=assert(tonumber(host or ask('House host computer ID')),'Host ID required') end
 M.write(c); print('Saved '..M.path..'. Run house '..role)
end
return M
