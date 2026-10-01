local sim=require('derby.sim')
local ledger=require('derby.ledger')
local house=require('derby.house')
local store=require('derby.store')
local service=require('derby.service')
local odds=require('derby.odds')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..' expected '..tostring(b)..', got '..tostring(a)) end
-- Actual source compilation, including all migrated consumers, without running them.
local function syntax(path)
 for _,f in ipairs(fs.list(path)) do
  local p=fs.combine(path,f)
  if fs.isDir(p) then syntax(p) elseif p:match('%.lua$') then check(loadfile(p),'Lua syntax: '..p) end
 end
end
syntax('/arcade')
for seed=1,150 do
 local a=sim.run(seed); local b=sim.new(seed)
 for _=1,173 do sim.step(b) end
 b=store.copy(b)
 while #b.order<3 do sim.step(b) end
 for i=1,3 do eq(a.horses[i].finish,b.horses[i].finish,'Restart deterministic'); eq(a.order[i],b.order[i],'Same finish order') end
 check(a.horses[a.order[1]].finish<=a.horses[a.order[2]].finish,'Crossing time order')
end
local function fakeInventory(items)
 local api={items=items or {},moves=0}; local all
 function api.connect(map) all=map end
 function api.list() return store.copy(api.items) end
 function api.getItemDetail(slot) return api.items[slot] and store.copy(api.items[slot]) end
 function api.pushItems(dest,slot,limit)
  if api.breakTransfer then error('Peripheral disconnected') end
  local target=assert(all[dest]); local item=api.items[slot]
  local moved=math.min(limit,item.count,target.capacity or 100000)
  api.moves=api.moves+1
  if moved>0 then
   target.items[1]=target.items[1] or {name=item.name,count=0}; target.items[1].count=target.items[1].count+moved
   item.count=item.count-moved; if item.count==0 then api.items[slot]=nil end
  end
  return moved
 end
 return api
end
local bank=fakeInventory({[1]={name='minecraft:diamond',count=1000}})
local intake=fakeInventory({[1]={name='minecraft:diamond',count=100},[3]={name='minecraft:obsidian',count=64}})
local output=fakeInventory()
local inventories={bank=bank,intake=intake,output=output}
for _,v in pairs(inventories) do v.connect(inventories) end
local initial=house.new(odds); house.nextRace(initial,743)
local db=store.open('/results/bank',initial)
local cfg={bank='bank',intake='intake',payout='output'}
local function host() return service.new(db,cfg,function(name) return inventories[name] end) end
local server=host(); check(server:operator('fund').ok,'fund bank')
local n=0
local function request(op,fields,role,owner)
 n=n+1; local q=fields or {}; q.op=op; q.id=tostring(owner or 2)..':'..n
 return server:request(q,role or 'cashier',owner or 2),q
end
local a=request('create',{name='A'}); local b=request('create',{name='B'})
check(a.ok and b.ok,'Issue zero-balance accounts')
eq(server:state().accounts[a.account].balance,0,'Zero opening balance')
local deposit,q=request('deposit',{account=a.account,amount=20})
eq(deposit.moved,20,'Deposit confirmed amount')
eq(intake.items[3].count,64,'Wrong item untouched')
local calls=intake.moves
local repeatReceipt=server:request(q,'cashier',2)
eq(repeatReceipt.balance,20,'Duplicate deposit receipt'); eq(intake.moves,calls,'No second item transfer')
q.amount=21; check(not server:request(q,'cashier',2).ok,'Reject changed retry')
local winner=sim.run(743).order[1]
local bet,ticket=request('bet',{account=a.account,race='race-1',horse=winner,stake=5},'station',3)
check(bet.ok,'Accept shared race bet')
local dup=request('bet',{account=a.account,race='race-1',horse=1,stake=5},'station',4)
check(not dup.ok,'One ticket across stations')
for _=1,651 do server:tick(800) end
server=host() -- persist/reload locked race with the original seed
local r=server:state().race; eq(r.seed,743,'Seed survives restart')
local late=request('bet',{account=b.account,race='race-1',horse=1,stake=5},'station',4)
check(not late.ok,'Late bet rejected')
check(server:request(ticket,'station',3).ok,'Lost betting reply retried after lock')
for _=1,650 do server:tick(800); if server:state().race.phase=='RESULT' then break end end
local state=server:state(); eq(state.race.sim.order[1],winner,'Shared winner')
local returns=odds.payouts[winner]['5']; eq(state.accounts[a.account].balance,15+returns,'Settled winnings')
local withdraw,wq=request('withdraw',{account=a.account,amount=15+returns})
eq(withdraw.moved,15+returns,'Diamond withdrawal')
eq(server:state().accounts[a.account].balance,0,'Round trip leaves zero balance')
local before=output.items[1].count; server:request(wq,'cashier',2); eq(output.items[1].count,before,'Withdrawal retry moves nothing')
eq(server:state().bank,bank.items[1].count,'Physical bank reconciles')
check(ledger.available(server:state())>=0,'All liabilities covered')
check(not request('create',{},'station',3).ok,'Stations cannot mint accounts')
check(not request('reserve',{account=a.account,stake=0,maximum=999999,round='bad',game='slots'},'station',3).ok,'Unfunded reservation rejected')
-- Partial and full-output transfers refund the untransferred part.
request('deposit',{account=a.account,amount=20}); output.capacity=3
local partial=request('withdraw',{account=a.account,amount=10}); eq(partial.moved,3,'Partial withdrawal'); eq(partial.balance,17,'Unmoved credit returned')
output.capacity=0; local full=request('withdraw',{account=a.account,amount=10}); eq(full.moved,0,'Full output'); eq(full.balance,17,'Full output debits nothing')
output.capacity=nil
-- Interrupted physical operation is not repeated, including after restart.
intake.breakTransfer=true
local uncertain,uq=request('deposit',{account=a.account,amount=5}); check(not uncertain.ok,'Disconnected transfer')
server=host(); check(server:state().pending[uq.id]~=nil,'Transfer intent persisted')
intake.breakTransfer=false; local moves=intake.moves
local pending=server:request(uq,'cashier',2); check(pending.pending,'Retry remains pending'); eq(intake.moves,moves,'No automatic physical retry')
check(not request('reserve',{account=a.account,stake=5,maximum=5,game='track',round='pending'},'station',3).ok,'Financial actions freeze')
check(server:operator('reconcile',uq.id,0).ok,'Operator reconciles zero moved')
-- Crash after physical transfer but before receipt commit: durable intent survives.
local crashDB={get=function() return db:get() end,save=function(_,value)
 if not next(value.pending) and value.bank>db:get().bank then error('Injected receipt write failure') end
 db:save(value)
end}
server=service.new(crashDB,cfg,function(name) return inventories[name] end)
local crashRequest={op='deposit',id='2:crash-after-transfer',account=a.account,amount=5}
local previousBank=bank.items[1].count
check(not pcall(function() server:request(crashRequest,'cashier',2) end),'Receipt persistence failure stops response')
eq(bank.items[1].count,previousBank+5,'Physical transfer really occurred')
server=host(); check(server:state().pending[crashRequest.id]~=nil,'Restart retains uncertain intent')
check(server:request(crashRequest,'cashier',2).pending,'Crash retry does not transfer again')
check(server:operator('reconcile',crashRequest.id,5).ok,'Reconcile actual moved count')
local corrected=server:request(crashRequest,'cashier',2); eq(corrected.moved,5,'Reconciled receipt returned')
-- Restore original test balance after the extra crash-test deposit.
request('withdraw',{account=a.account,amount=5})
-- Settlement duplicate, concurrent spend and reserved liabilities for each migrated game.
for _,game in ipairs({'slots','blackjack','rps_rogue','track'}) do
 local max=game=='slots' and 100 or 15
 local rr,rq=request('reserve',{account=a.account,stake=5,maximum=max,round=game..'-test',game=game},'station',3)
 check(rr.ok,game..' reserve')
 local wrong=request('settle',{account=a.account,round=game..'-test',amount=5},'station',4)
 check(not wrong.ok,'Other station cannot settle '..game)
 local paid,pq=request('settle',{account=a.account,round=game..'-test',amount=5},'station',3)
 check(paid.ok,game..' settle')
 local balance=server:state().accounts[a.account].balance
 check(server:request(pq,'station',3).ok,'Settlement retry'); eq(server:state().accounts[a.account].balance,balance,'No duplicate winnings')
end
local reserve=request('reserve',{account=a.account,stake=15,maximum=15,round='concurrent',game='track'},'station',3)
check(reserve.ok,'First spend accepted')
check(not request('reserve',{account=a.account,stake=5,maximum=5,round='concurrent2',game='track'},'station',4).ok,'Second spend rejected')
check(server:operator('refund','concurrent').ok,'Interrupted arcade refund')
-- Two-slot durability: corrupt newest generation and retain older committed state.
local d=store.open('/results/durability',{value=1}); d:save({value=2}); d:save({value=3})
local f=fs.open('/results/durability.0','w'); f.write('{partial'); f.close()
eq(store.open('/results/durability',{}):get().value,2,'Partial write retains prior state')
f=fs.open('/results/durability.1','w'); f.write('{partial'); f.close()
check(not pcall(store.open,'/results/durability',{}),'Corrupt state never creates a fresh bank')
print('PASS '..passed..' assertions: simulation, transactions, inventory, persistence, migrated game contracts')
