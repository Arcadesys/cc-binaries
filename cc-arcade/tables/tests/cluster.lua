-- Runs on every computer in a CraftOS-PC cluster started by tables/tools/cluster.py.
-- Computer 0 is the table; computers 1..N are seats, each with a wired modem and a
-- disk drive holding a house card. Everything below the startup glue is the real
-- table and seat code talking over real rednet.
--
-- mode 'test': scripted seats play two hands. In hand 2, seat 2 pulls its card
-- mid-hand and seat 3 powers off before flipping. Computer 0 checks the result.
-- mode 'gui': nothing is scripted; play the seats in their own windows.
local cfg=_G.TABLES_CLUSTER or {mode='test',seats=3}
local me=os.getComputerID()
local TEST='pine-table-cluster-test'
local function write(name,text)
 local f=fs.open('/results/'..name,'w'); f.write(text); f.close()
end
local function waitFor(pred,seconds,what)
 local deadline=os.epoch('utc')+seconds*1000
 while not pred() do
  if os.epoch('utc')>deadline then error('Timed out waiting for '..what,0) end
  sleep(.1)
 end
end
periphemu.create('back','modem')

if me==0 then
 local c={role='table',modem='back',seats={},game='highcard',exhibition=true}
 for i=1,cfg.seats do c.seats[i]=i end
 if cfg.mode=='gui' then pcall(periphemu.create,'top','monitor') end
 local function spawn()
  -- CraftOS-PC crashes if two computers load their BIOS at the same moment.
  for i=1,cfg.seats do periphemu.create(i,'computer'); sleep(.5) end
 end
 if cfg.mode=='gui' then
  require('tables.host').run(c,function() spawn(); while true do os.pullEvent('never') end end)
  return
 end
 local lines={}
 local host
 local ok,err=pcall(require('tables.host').run,c,function(h)
  host=h
  local function count(entry) local n=0; for _,l in ipairs(h.log) do if l:match(entry) then n=n+1 end end; return n end
  spawn()
  waitFor(function() for i=1,cfg.seats do if not h.seats[i].account then return false end end return true end,20,'all seats to present cards')
  lines[#lines+1]='seated: '..cfg.seats
  rednet.broadcast('go',TEST)
  waitFor(function() return count('^lobby')>=1 end,30,'hand 1')
  lines[#lines+1]='hand 1 done'
  waitFor(function() return count('^payout')>=6 end,40,'hand 2')
  local log=table.concat(h.log,'\n')
  assert(log:find('start 1,2,3\n',1,true),'hand 1 dealt to all three seats')
  assert(select(2,log:gsub('start 1,2,3',''))==2,'both hands dealt to all three seats')
  assert(count('^auto 3$')==1,'powered-off seat 3 auto-flipped')
  assert(count('^auto [12]$')==0,'live seats flipped for themselves')
  assert(count('^press [12] flip$')==4,'every live flip arrived over rednet')
  local total=0; for i=1,cfg.seats do total=total+h.bank:balance('house-'..i) end
  assert(total==100*cfg.seats,'credits conserved across the cluster: '..total)
  lines[#lines+1]='log:\n'..log
  lines[#lines+1]='balances: '..h.bank:balance('house-1')..' '..h.bank:balance('house-2')..' '..h.bank:balance('house-3')
  -- Give scripted seats a moment to write their transcripts.
  waitFor(function() return fs.exists('/results/seat-1.txt') and fs.exists('/results/seat-2.txt') end,15,'seat transcripts')
 end)
 if not ok and host then lines[#lines+1]='table log:\n'..table.concat(host.log,'\n') end
 lines[#lines+1]=ok and 'PASS' or ('FAIL '..tostring(err))
 write('result.txt',table.concat(lines,'\n'))
 os.shutdown()
end

-- A seat: wired modem, a drive with this seat's house card, then the real seat program.
periphemu.create('left','drive')
peripheral.call('left','insertDisk',100+me)
local f=fs.open(disk.getMountPath('left')..'/house-card.json','w'); f.write(textutils.serializeJSON({account='house-'..me})); f.close()
local c={role='seat',modem='back',table=0}
if cfg.mode=='gui' then return require('tables.seat').run(c) end
local seen={}
local function note(s) local v=s:current(); local l=(v.status or '')..' | '..table.concat((function() local o={} for _,b in ipairs(v.buttons or {}) do o[#o+1]=b.id end return o end)(),','); if seen[#seen]~=l then seen[#seen+1]=l end end
local function result(s) local st=s:current().status or ''; return st:find('^YOU WIN') or st:find('^PUSH') or st=='No win this hand' end
local function button(s,id) for _,b in ipairs(s:current().buttons or {}) do if b.id==id then return true end end return false end
local ok,err=pcall(require('tables.seat').run,c,function(s)
 local function press(id,seconds)
  waitFor(function() note(s); return button(s,id) end,seconds or 20,id..' button'); s:press(id)
 end
 rednet.receive(TEST,30)
 -- Hand 1: everyone readies and flips.
 press('ready'); press('flip')
 waitFor(function() note(s); return result(s) end,20,'hand 1 result')
 -- Hand 2.
 press('ready',30)
 waitFor(function() note(s); return button(s,'flip') end,20,'hand 2 deal')
 if me==3 then
  write('seat-3.txt',table.concat(seen,'\n')..'\npowering off before flip'); os.shutdown()
 elseif me==2 then
  peripheral.call('left','ejectDisk'); sleep(1.5); note(s)
 end
 press('flip')
 waitFor(function() note(s); return result(s) end,20,'hand 2 result')
end)
seen[#seen+1]=ok and 'done' or ('FAIL '..tostring(err))
write('seat-'..me..'.txt',table.concat(seen,'\n'))
os.shutdown()
