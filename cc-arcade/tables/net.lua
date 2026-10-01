-- Seat <-> table messages over a private wired rednet network.
-- Only the table computer runs the game and holds money; seats are thin terminals
-- that send their card and button presses and draw whatever view the table sends.
--
-- seat -> table  {t='hello',card={account=,diskID=}|nil}   every HEARTBEAT seconds
--                {t='press',seq=<view seq>,button=<id>}  (acted on only if offered now)
-- table -> seat  {t='view',seq=<n>,view={title,status,lines,buttons}}
--                sent on every change and in reply to every hello, so a lost
--                message heals within one heartbeat.
local M={protocol='pine-table-v1',HEARTBEAT=1,TIMEOUT=4,path='/table-config.json'}
function M.read()
 if not fs.exists(M.path) then return nil end
 local f=assert(fs.open(M.path,'r')); local c=textutils.unserializeJSON(f.readAll()); f.close(); return c
end
function M.write(c)
 local f=assert(fs.open(M.path,'w')); f.write(textutils.serializeJSON(c)); f.close()
end
function M.open(c)
 assert(c and c.modem,'Run tables setup first')
 local modem=assert(peripheral.wrap(c.modem),'Configured modem missing: '..tostring(c.modem))
 assert(modem.isWireless and not modem.isWireless(),'Use a wired modem for the table network')
 rednet.open(c.modem)
 return {
  send=function(id,msg) rednet.send(id,msg,M.protocol) end,
  -- Returns sender and message for a table-network event, nil for anything else.
  parse=function(e,from,msg,protocol)
   if e=='rednet_message' and protocol==M.protocol and type(msg)=='table' and type(msg.t)=='string' then return from,msg end
  end,
 }
end
-- tables setup table <modem> <seat-id> [<seat-id> ...]   (seat order = seat numbers)
-- tables setup seat <modem> <table-id>
function M.setup(args)
 local role,modem=args[1],args[2]
 assert(role=='table' or role=='seat','Use: tables setup table <modem> <seat ids...> | tables setup seat <modem> <table id>')
 assert(not M.read(),'Configuration exists; remove '..M.path..' to reconfigure')
 local c={role=role,modem=assert(modem,'Wired modem name required')}
 if role=='table' then
  c.seats={}
  for i=3,#args do c.seats[#c.seats+1]=assert(tonumber(args[i]),'Seat IDs are computer numbers') end
  assert(#c.seats>=1 and #c.seats<=4,'A table has 1 to 4 seats')
  c.game=settings.get('tables.game','highcard')
  c.exhibition=true
 else c.table=assert(tonumber(args[3]),'Table computer ID required') end
 M.open(c); M.write(c)
 print('Saved '..M.path..'. Run: tables '..role)
end
return M
