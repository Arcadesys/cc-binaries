-- Headless attraction contracts. The real wallet, game event loops, rules and free
-- attraction controllers are loaded unchanged. Only display/audio and the credits
-- boundary are doubled; transport/durability are exercised by the wire suites.
-- Export: require('tests.consumer_contracts')(check, eq).
local source=debug.getinfo(1,'S').source:gsub('^@','')
local root=assert(source:match('^(.*)/tests/consumer_contracts%.lua$'),'Cannot find cc-arcade root')
local repo=root..'/..'
local noop=function() end
local bitlib=bit32
if not bitlib then
 -- Stock Lua 5.3/5.4 compatibility for CC's unsigned bit32 API. Kept in a string
 -- so this suite still parses on CC:Tweaked / CraftOS-PC (Lua 5.2).
 bitlib=assert(load([[local M={}; local function u(n) return math.floor(n)%4294967296 end
 function M.band(a,b) return u(a)&u(b) end
 function M.bor(a,b) return u(a)|u(b) end
 function M.bxor(a,b) return u(a)~u(b) end
 function M.bnot(a) return (~u(a))&0xffffffff end
 function M.btest(a,b) return M.band(a,b)~=0 end
 function M.rshift(a,b) if b>=32 then return 0 end return u(a)>>b end
 function M.lshift(a,b) if b>=32 then return 0 end return (u(a)<<b)&0xffffffff end
 return M]],'consumer bit32 shim'))()
end
local function isolated(dir)
 local env=setmetatable({bit32=bitlib},{__index=_G}); env._G=env
 env.keys=setmetatable({},{__index=function(t,k) rawset(t,k,k); return k end})
 env.colors={}
 for i,name in ipairs({'white','orange','magenta','lightBlue','yellow','lime','pink','gray','lightGray','cyan','purple','blue','brown','green','red','black'}) do env.colors[name]=2^(i-1) end
 env.os={pullEvent=function() return coroutine.yield() end,startTimer=function() return 1 end,epoch=function() return 0 end,time=function() return 0 end}
 env.os.pullEventRaw=env.os.pullEvent
 local loaded,stubs={},{}
 function env.require(name)
  if stubs[name]~=nil then return stubs[name] end
  if loaded[name]~=nil then return loaded[name] end
  local fn,err=loadfile(dir..'/'..name:gsub('%.','/')..'.lua','t',env); assert(fn,err)
  local value=fn(); loaded[name]=value==nil and true or value; return loaded[name]
 end
 return env,stubs
end
local function gameRuntime()
 local env,stubs=isolated(root)
 local runtime={env=env,stubs=stubs,now=0,frames={},ejections={}}
 env.disk={eject=function(drive) runtime.ejections[#runtime.ejections+1]=drive end}
 local renderer={slots=function() return {} end,buttons=function() return {} end,follow=function() return {} end}
 function renderer.new()
  return {draw=function(_,frame) runtime.frame=frame; runtime.frames[#runtime.frames+1]=frame end}
 end
 for _,name in ipairs({'pineslots.render','pinejack.render','pinebox.render'}) do stubs[name]=renderer end
 stubs['casino.sound']=function() return {play=noop,tick=noop} end
 function runtime:run(module,wallet,options)
  options=options or {}; options.wallet=wallet
  options.target={getSize=function() return 51,19 end}
  options.clock=function() return self.now end
  options.sound={play=noop,tick=noop}
  options.button=function(event,button) if event=='redstone' then return button end end
  options.controls=options.controls or env.require('pineslots.controls').new({},function() return false end)
  self.co=coroutine.create(function() return env.require(module).run(options) end)
  self:send(); return self
 end
 function runtime:send(...)
  assert(coroutine.status(self.co)~='dead','Game exited before the scenario finished')
  local ok,err=coroutine.resume(self.co,...); assert(ok,err)
 end
 function runtime:tick(seconds)
  for _=1,math.floor((seconds or 5)*20+.5) do self.now=self.now+.05; self:send('timer',1) end
 end
 function runtime:key(name,seconds) self:send('key',env.keys[name]); if seconds then self:tick(seconds) end end
 function runtime:quit() self:key('q'); return coroutine.status(self.co)=='dead' end
 return runtime
end
-- A recording credits adapter, not a second implementation of the house ledger.
-- It exposes errors/retries to the real wallet and records every contract argument.
local function liveFixture(game,options)
 options=options or {}
 local rt=gameRuntime(); local log={}; local balances={ann=100,bo=100}
 local inserted={path='disk',drive='drive_0',account='ann'}
 local names={ann='Ann',bo='Bo'}; local bindings={}; local pending; local count=0
 local credits={}
 local function note(op,fields) fields=fields or {}; fields.op=op; log[#log+1]=fields; return fields end
 function credits.lock(path) bindings[path]=inserted.account; note('lock',{account=inserted.account,path=path}) end
 function credits.unlock(path) bindings[path]=nil; note('unlock',{path=path}) end
 function credits.getName(path) return names[bindings[path]] end
 function credits.get(path) if options.lookupError then error('HOUSE: unavailable',0) end; return balances[bindings[path]] end
 function credits.beginRound(id,stake,maximum,path)
  note('begin',{game=id,stake=stake,maximum=maximum,path=path,account=inserted.account})
  if options.rejectBegin then return nil,'house reserve refused' end
  count=count+1; balances[inserted.account]=balances[inserted.account]-stake
  return {game=id,stake=stake,maximum=maximum,account=inserted.account,round='r'..count}
 end
 function credits.increaseRound(round,stake,maximum)
  note('increase',{round=round.round,account=round.account,stake=stake,maximum=maximum})
  if options.rejectIncrease then return false,'house increase refused' end
  balances[round.account]=balances[round.account]-stake; round.stake=round.stake+stake; round.maximum=maximum; return true
 end
 local function commit(round,amount) balances[round.account]=balances[round.account]+amount; return balances[round.account] end
 function credits.settleRound(round,amount)
  note('settle',{round=round.round,account=round.account,amount=amount})
  if options.failSettle then pending={round=round,amount=amount,request={op='settle',round=round.round,account=round.account,amount=amount}}; error('HOUSE: unavailable',0) end
  return commit(round,amount)
 end
 function credits.refundRound(round)
  note('refund',{round=round.round,account=round.account,stake=round.stake})
  if options.failRefund then pending={round=round,amount=round.stake,request={op='refund',round=round.round,account=round.account}}; error('HOUSE: unavailable',0) end
  commit(round,round.stake); return true
 end
 function credits.retry()
  note('retry')
  if options.failRetry then return false,'still unavailable',pending and pending.round.account,{pending=true,request=pending and pending.request} end
  local account=pending and pending.round.account or nil
  local context={pending=false,request=pending and pending.request}
  local balance=pending and commit(pending.round,pending.amount) or nil; pending=nil
  return true,{ok=true,balance=balance},account,context
 end
 local wallet=rt.env.require('casino.wallet').live(game,game,credits,function() return inserted end)
 local fixture={runtime=rt,wallet=wallet,credits=credits,log=log,balances=balances,options=options}
 function fixture:card(account)
  inserted=account and {path='disk',drive='drive_0',account=account} or nil
 end
 function fixture:money()
  local out={}; for _,entry in ipairs(log) do if entry.op~='lock' and entry.op~='unlock' then out[#out+1]=entry end end; return out
 end
 return fixture
end
local function stacked(ranks)
 return function()
  local shoe={cards={},next=1}
  for _,rank in ipairs(ranks) do shoe.cards[#shoe.cards+1]={rank=rank,suit='S'} end
  while #shoe.cards<312 do shoe.cards[#shoe.cards+1]={rank='2',suit='C'} end
  return shoe
 end
end
local function boxOptions(values)
 local seed=99
 return {random=function(lo,hi)
  if lo==1 and hi==6 then return assert(table.remove(values,1),'Unexpected extra dice roll') end
  seed=(seed*1103515245+12345)%2147483648; return lo+seed%(hi-lo+1)
 end}
end
-- Run actual game coroutines against actual wallet/credits/host, replacing only
-- render/audio and the physical event source. Both nested and outer API waits
-- receive the real fake-Rednet messages and transport timers.
local function wireFixture(game)
 local hub=require('tests.support.hub').new(); local node=hub:computer(3)
 node.require('derby.config').write({role='station',modem='wired',host=1})
 local state=hub:state(); state.accounts['house-2']={name='Bo',balance=60}; state.nextAccount=2
 hub.host.require('derby.store').open('/house-bank/state',{}):save(state); hub:restartHost()
 local current
 local f={hub=hub,node=node}
 function f:card(account)
  current=account and {path='/disk',drive='drive_0',account=account} or nil
  node.env.fs.makeDir('/disk')
  local file=assert(node.env.fs.open('/disk/house-card.json','w'))
  file.write(node.env.textutils.serializeJSON({account=account})); file.close()
 end
 function f:call(fn)
  hub:task(node,fn); hub:pump()
  if not node.finished then hub:timeout(node); hub:pump() end
  assert(node.finished,'Wallet fixture call did not complete'); return node.result
 end
 function f:reload()
  node=hub:computer(3,node.files); self.node=node
  self.credits=node.require('credits')
  self.wallet=node.require('casino.wallet').live(game,'WIRE '..game,self.credits,function() return current end)
 end
 f:card('house-1'); f:reload()
 function f:play(module,options)
  local rt=gameRuntime(); local rawSend=rt.send
  function rt:send(...)
   node.co=self.co; node.finished=false; hub.now=self.now
   rawSend(self,...); hub:pump()
   while coroutine.status(self.co)~='dead' do
    local earliest
    for _,at in pairs(node.timers) do if not earliest or at<earliest then earliest=at end end
    if not earliest or earliest>hub.now then break end
    hub:timeout(node); hub:pump()
   end
  end
  rt:run(module,self.wallet,options); self.runtime=rt; return rt
 end
 function f:requests(op)
  local out={}
  for _,packet in ipairs(hub.trace) do
   local q=packet.from==3 and packet.message.request
   if q and (not op or q.op==op) then out[#out+1]=q end
  end
  return out
 end
 function f:lose(op,kind)
  local token
  hub.hook=function(packet)
   local q=packet.from==3 and packet.message.request
   if q and q.op==op then token=packet.message.token; if kind=='request' then return false end end
   if kind=='reply' and packet.from==1 and packet.message.token==token then return false end
  end
 end
 return f
end
return function(check,eq)
 -- Metadata reconciliation has its own durable retry stage. Losing that read
 -- never resends the acknowledged increase, including after client recreation.
 for _,fault in ipairs({'status timeout','legacy host'}) do
  local f=wireFixture('pinejack'); f:call(function() return f.wallet:refresh() end)
  local round=f:call(function() return f.wallet:begin(4,10) end)
  f:lose('increase','reply'); check(not f:call(function() return f.wallet:increase(round,2,12) end),'Increase reply lost before '..fault)
  local token
  f.hub.hook=function(packet)
   local q=packet.from==3 and packet.message.request
   if q and q.op=='roundStatus' then token=packet.message.token end
   if packet.from==1 and packet.message.token==token then
    if fault=='status timeout' then return false end
    packet.message.result.stake=nil; packet.message.result.maximum=nil; return {packet}
   end
  end
  local result=f:call(function() return {f.wallet:retry()} end)
  check(not result[1] and result[3].pending,'Unconfirmed authoritative terms remain pending: '..fault)
  eq(round.stake,4,'No guessed increase total before authoritative terms')
  local saved=f.node.require('derby.store').open('/house-client/state',{}):get()
  check(saved.recovery~=nil,'Recovery intent is durable'); local counter=saved.counter
  check(not f:call(function() return f.credits.increaseRound(round,1,14) end),'New mutation blocked while terms unavailable')
  eq(f.node.require('derby.store').open('/house-client/state',{}):get().counter,counter,'Blocked mutation consumes no transaction ID')
  if fault=='status timeout' then f:reload(); f:call(function() return f.wallet:refresh() end) end
  f.hub.hook=nil; check(f:call(function() return f.wallet:retry() end),'Authoritative read retry recovers '..fault)
  saved=f.node.require('derby.store').open('/house-client/state',{}):get()
  eq(saved.rounds['house-1'].stake,6,'Saved stake becomes host total'); eq(saved.rounds['house-1'].maximum,12,'Saved maximum becomes host total')
  check(not saved.recovery,'Completed reconciliation clears durable marker')
  if fault=='legacy host' then eq(round.stake,6,'Bound handle updates after host upgrade'); eq(round.maximum,12,'Bound maximum updates after host upgrade') end
  local sent=#f:requests('increase'); check(f:call(function() return f.wallet:retry() end),'Repeated receipt retry stays safe')
  eq(#f:requests('increase'),sent,'Metadata retries never resend increase'); eq(f.hub:state().rounds[round.round].stake,6,'Duplicate retry cannot add stake twice')
  local reservations=#f:requests('reserve')
  check(not f:call(function() return f.wallet:begin(1,2) end),'Recreated/interrupted open hand requires review before new gameplay')
  eq(#f:requests('reserve'),reservations,'Restart cannot silently create another paid hand')
  check(f:call(function() return f.wallet:refund(saved.rounds['house-1']) end),'Recovered exact terms can be refunded')
  eq(f.wallet:session().balance,100,'Recovered refund display matches host'); eq(f.hub:state().accounts['house-1'].balance,100,'Recovered refund returns all six credits')
 end
 -- An operator can close the interrupted round. A stale increase receipt must
 -- neither resume its hand nor overwrite the authoritative refunded balance.
 do
  local f=wireFixture('pinejack'); f:call(function() return f.wallet:refresh() end)
  local round=f:call(function() return f.wallet:begin(4,10) end)
  f:lose('increase','reply'); f:call(function() return f.wallet:increase(round,2,12) end)
  local service=f.hub.host.require('derby.service').new(f.hub.host.require('derby.store').open('/house-bank/state',{}),{},function() error('No inventory needed') end)
  check(service:operator('refund',round.round).ok,'Operator refunds committed interrupted increase'); f.hub:restartHost()
  f:lose('lookup','reply')
  local result=f:call(function() return {f.wallet:retry()} end)
  check(not result[1] and result[3].pending and result[3].status=='refunded','Terminal balance lookup timeout still holds recovery')
  check(f.node.require('derby.store').open('/house-client/state',{}):get().recovery~=nil,'Terminal lookup retains durable marker')
  eq(f.wallet:session().balance,96,'Stale increase receipt cannot overwrite terminal balance while lookup pending')
  f.hub.hook=nil; result=f:call(function() return {f.wallet:retry()} end)
  check(not result[1] and not result[3].pending and result[3].status=='refunded','Terminal round cannot report a resumable raise')
  eq(f.wallet:session().balance,100,'Terminal retry reads authoritative refunded account balance')
  local saved=f.node.require('derby.store').open('/house-client/state',{}):get()
  check(not saved.recovery and not saved.rounds['house-1'],'Closed round and recovery clear only after authoritative lookup')
 end
 -- An acknowledgement for an earlier raise never masquerades as a blocked
 -- settlement acknowledgement (legacy callers fail closed for cashier review).
 do
  local f=wireFixture('pinejack'); f:call(function() return f.wallet:refresh() end)
  local round=f:call(function() return f.wallet:begin(4,10) end)
  f:lose('increase','reply'); f:call(function() return f.wallet:increase(round,2,12) end)
  check(not f:call(function() return f.wallet:settle(round,0) end),'Pending increase blocks settlement')
  f.hub.hook=nil; local result=f:call(function() return {f.wallet:retry()} end)
  check(not result[1] and result[3].matches==false,'Increase receipt cannot complete a settlement wait')
  eq(round.stake,6,'Mismatched consumer wait still reconciles authoritative stake')
  eq(f.wallet:session().balance,94,'Mismatched wait still displays its own acknowledged account balance')
  eq(f.hub:state().rounds[round.round].status,'open','No phantom settlement after increase replay')
  eq(#f:requests('settle'),0,'Blocked settlement never went on the wire')
 end
 -- Real Jack coroutine + wire: uncertain double/split holds before drawing or
 -- accepting another decision; exact retries resume the original action once.
 for _,raise in ipairs({'double','split'}) do for _,loss in ipairs({'request','reply'}) do
  local f=wireFixture('pinejack')
  local deck=raise=='double' and {'6','6','5','10','10','9'} or {'8','6','8','10','3','K','10','9'}
  local rt=f:play('pinejack.game',{newShoe=stacked(deck)}); rt:tick(1)
  if raise=='double' then rt:key('one',1) end
  rt:key('two',5)
  if raise=='split' then rt:key('three',1) end
  f:lose('increase',loss); rt:key(raise=='double' and 'three' or 'two')
  local framesBefore=#rt.frames; rt:key('q'); rt:tick(.5)
  check(coroutine.status(rt.co)~='dead','Q cannot exit while raise transport is awaiting an event')
  check(#rt.frames>framesBefore,'Rendering continues while raw transport is waiting')
  rt:tick(2.5)
  eq(rt.frame.options[1].name,'retry','Jack holds '..raise..' after lost '..loss)
  local held=rt.frame.player; local frames=#rt.frames
  rt:key('h'); rt:key('s'); rt:key('c'); rt:key('q'); rt:tick(.5)
  eq(rt.frame.player,held,'Held raise ignores hit/stand/cash/quit'); check(#rt.frames>frames,'Renderer ticks continue while raise held')
  eq(#f:requests('settle'),0,'No payout is attempted before raise acknowledged')
  rt:key('one',3); eq(rt.frame.options[1].name,'retry','Repeated timeout retains raise hold')
  local requests=f:requests('increase'); eq(#requests,2,'Second attempt is a retry')
  eq(requests[1].id,requests[2].id,'Retried increase preserves transaction ID')
  f:card('house-2'); rt:send('disk'); rt:tick(2)
  eq(f.wallet:session().account,'house-2','Replacement card can be displayed during raise hold')
  f.hub.hook=nil; rt:key('one',5)
  if raise=='split' then rt:key('three',5); rt:key('two',5) end
  local state=f.hub:state(); eq(state.accounts['house-1'].balance,raise=='double' and 108 or 106,'Recovered '..raise..' pays the original hand correctly')
  eq(state.accounts['house-2'].balance,60,'Replacement card is never charged'); eq(f.wallet:session().balance,60,'Replacement card meter stays correct')
  eq(#f:requests('settle'),1,'Recovered hand settles once')
  for _,round in pairs(state.rounds) do eq(round.status,'settled','Recovered game round reaches terminal state') end
  check(rt:quit(),'Recovered Jack hand returns to idle')
 end end
 -- The actual Jack hand must hold through the second, metadata-read stage and
 -- through a terminal account lookup; lower-level recovery alone is not enough.
 for _,terminal in ipairs({false,true}) do
  local f=wireFixture('pinejack'); local rt=f:play('pinejack.game',{newShoe=stacked({'6','6','5','10','10','9'})})
  rt:tick(1); rt:key('one',1); rt:key('two',5); f:lose('increase','reply'); rt:key('three',3)
  local roundId=f:requests('reserve')[1].round
  if terminal then
   local service=f.hub.host.require('derby.service').new(f.hub.host.require('derby.store').open('/house-bank/state',{}),{},function() error('No inventory needed') end)
   check(service:operator('refund',roundId).ok,'Operator closes pending real Jack double'); f.hub:restartHost()
   f:lose('lookup','reply')
  else f:lose('roundStatus','reply') end
  rt:key('one',3)
  eq(rt.frame.options[1].name,'retry','Actual Jack stays held while authoritative '..(terminal and 'balance' or 'terms')..' unavailable')
  local raises=#f:requests('increase'); local hand=rt.frame.player
  rt:key('h'); rt:key('s'); rt:key('q'); rt:tick(.5)
  eq(rt.frame.player,hand,'No gameplay continuation during reconciliation read hold')
  eq(#f:requests('settle'),0,'Read-stage timeout never produces payout')
  f.hub.hook=nil; rt:key('one',5)
  eq(#f:requests('increase'),raises,'Second-stage retry never resends the acknowledged raise')
  if terminal then
   eq(f.wallet:session().balance,100,'Aborted Jack hand refreshes authoritative refunded meter')
   eq(#f:requests('settle'),0,'Closed interrupted hand never resumes or settles again')
   eq(f.hub:state().rounds[roundId].status,'refunded','Operator closure preserved')
  else
   eq(f.hub:state().accounts['house-1'].balance,108,'Read-stage recovery resumes exact doubled win')
   eq(#f:requests('settle'),1,'Resumed double settles exactly once')
  end
  check(rt:quit(),'Reconciled/aborted Jack hand returns to idle')
 end
 -- A request that never reached the host may be declined on retry. This is a
 -- normal decline, not a confirmed raise: rollback the tentative double.
 do
  local f=wireFixture('pinejack'); local rt=f:play('pinejack.game',{newShoe=stacked({'6','10','5','7'})})
  rt:tick(1); rt:key('one',1); rt:key('two',5); f:lose('increase','request'); rt:key('three',3)
  local state=f.hub:state(); state.bank=166
  f.hub.host.require('derby.store').open('/house-bank/state',{}):save(state); f.hub.inventories.bank.count=166; f.hub:restartHost()
  f.hub.hook=nil; rt:key('one',3)
  eq(rt.frame.options[2].name,'stand','Definite declined retry returns to original hand decisions')
  eq(f.wallet:session().balance,96,'Declined raise costs no extra credits')
  rt:key('two',5); eq(f.hub:state().accounts['house-1'].balance,96,'Rolled-back original hand settles normally')
  eq(f:requests('settle')[1].amount,0,'Decline does not turn a losing eleven into a doubled result'); check(rt:quit(),'Declined retry does not wedge Jack')
 end
 -- Account balances are not capped at the per-transaction one-billion limit.
 do
  local f=wireFixture('pinejack'); local state=f.hub:state()
  state.accounts['house-1'].balance=1000000001; state.bank=1000000100
  f.hub.host.require('derby.store').open('/house-bank/state',{}):save(state); f.hub.inventories.bank.count=state.bank; f.hub:restartHost()
  f:call(function() return f.wallet:refresh() end); local round=f:call(function() return f.wallet:begin(4,10) end)
  f:lose('increase','reply'); f:call(function() return f.wallet:increase(round,2,12) end)
  local service=f.hub.host.require('derby.service').new(f.hub.host.require('derby.store').open('/house-bank/state',{}),{},function() error('No inventory needed') end)
  check(service:operator('refund',round.round).ok,'Large account interrupted raise refunded'); f.hub:restartHost(); f.hub.hook=nil
  local result=f:call(function() return {f.wallet:retry()} end)
  check(not result[1] and not result[3].pending and result[3].status=='refunded','Valid large account balance does not wedge recovery')
  eq(f.wallet:session().balance,1000000001,'Full large refunded balance retained')
 end
 -- Box recovers the exact first reservation or shared-card increase before
 -- accepting another ante; cancellation returns the whole acknowledged stake.
 for _,operation in ipairs({'reserve','increase'}) do for _,loss in ipairs({'request','reply'}) do
  local f=wireFixture('pinebox'); local rt=f:play('pinebox.game',boxOptions({})); rt:tick(1)
  rt:key('space',1) -- choose player count
  if operation=='increase' then rt:key('right',1) end -- three seats, cancel after two antes
  rt:key('space',1)
  if operation=='increase' then rt:key('space',1) end -- first shared-card ante
  f:lose(operation,loss); rt:key('space',3)
  eq(rt.frame.options[1].name,'retry','Box holds uncertain '..operation..' after lost '..loss)
  eq(rt.frame.players.pot,operation=='reserve' and 0 or 1,'Unacknowledged ante is not added to pot')
  rt:key('q'); rt:key('c'); rt:tick(.5); check(coroutine.status(rt.co)~='dead','Pending Box ante cannot exit/cash out')
  rt:key('space',3); eq(rt.frame.options[1].name,'retry','Repeated Box timeout retains original ante')
  local requests=f:requests(operation); eq(requests[#requests].id,requests[#requests-1].id,'Box retries exact same transaction')
  f.hub.hook=nil; rt:key('space',2)
  eq(rt.frame.players.pot,operation=='reserve' and 1 or 2,'Recovered ante enters pot exactly once')
  eq(rt.frame.players.current,operation=='reserve' and 2 or 3,'Recovered ante advances exactly one seat')
  rt:key('left',3)
  eq(#f:requests('refund'),1,'Cancelled shared account refunds once')
  eq(f.hub:state().accounts['house-1'].balance,100,'Cancellation returns all recovered antes')
  eq(f.wallet:session().balance,100,'Box refund meter uses reconciled whole stake')
  check(rt:quit(),'Recovered and cancelled Box returns to idle')
 end end
 -- A recovered shared-card raise can also finish the real match, not just cancel.
 do
  local f=wireFixture('pinebox'); local rt=f:play('pinebox.game',boxOptions({1,1,1,1,1,1,1,1})); rt:tick(1)
  for _=1,3 do rt:key('space',1) end
  f:lose('increase','reply'); rt:key('space',3); f.hub.hook=nil; rt:key('space',2)
  for _=1,6 do rt:key('space',9) end; rt:tick(6)
  eq(#f:requests('settle'),1,'Recovered shared-card Box match settles once')
  eq(f:requests('settle')[1].amount,2,'Recovered shared-card tie returns the complete pot')
  eq(f.hub:state().accounts['house-1'].balance,100,'Recovered Box tie conserves both antes'); check(rt:quit(),'Recovered shared-card match completes')
 end
 -- Box's real ante/refund path also has nested wallet transport yields.
 do
  local f=wireFixture('pinebox'); local rt=f:play('pinebox.game',boxOptions({})); rt:tick(1)
  for _,key in ipairs({'space','space','space'}) do rt:key(key,2) end
  eq(#f:requests('reserve'),1,'Real Box ante crosses wire once')
  rt:key('left',3); eq(#f:requests('refund'),1,'Real Box cancellation refunds through wire')
  eq(f.hub:state().accounts['house-1'].balance,100,'Box returns full cancelled ante'); check(rt:quit(),'Real Box coroutine returns to idle')
 end
 -- Wallet ownership survives disk removal or swapping a second account into the
 -- same mount path; a result must not overwrite the other player's display.
 do
  local f=liveFixture('pinejack'); local w=f.wallet
  check(w:refresh(),'Wallet detects house card'); eq(w:session().name,'Ann','Wallet reads host name')
  local round=assert(w:begin(2,5)); eq(w:session().balance,98,'Reserve reduces displayed balance after acknowledgement')
  f:card('bo'); w:refresh(); local ok,balance=w:settle(round,5)
  check(ok,'Original account settles with another card inserted'); eq(balance,103,'Original account paid')
  eq(w:session().account,'bo','Replacement account remains current'); eq(w:session().balance,100,'Replacement balance not overwritten')
  eq(f.balances.ann,103,'Round keeps original account ownership')
  local other=assert(w:begin(1,13)); f:card(nil); w:refresh()
  check(w:refund(other),'Refund still works after card removal'); eq(f.balances.bo,100,'Removed card gets its refund')
  f:card('ann'); w:refresh(); eq(w:cashout(),103,'Cashout reports persisted account balance')
  eq(f.runtime.ejections[1],'drive_0','Cashout ejects original drive')
  check(not w:refresh() and not w:session(),'Ejecting card is not immediately rebound')
 end
 do
  local f=liveFixture('pineslots',{rejectBegin=true}); f.wallet:refresh()
  local round=f.wallet:begin(5,206); check(not round,'Rejected reserve cannot start a round')
  eq(f.wallet:session().balance,100,'Rejected reserve leaves display unchanged')
  f.options.rejectBegin=false; round=assert(f.wallet:begin(5,206)); f.options.rejectIncrease=true
  check(not f.wallet:increase(round,5,412),'Rejected increase reported'); eq(round.stake,5,'Rejected increase leaves stake unchanged')
  eq(f.wallet:session().balance,95,'Rejected increase leaves balance unchanged')
  local bad=liveFixture('pineslots',{lookupError=true}); check(bad.wallet:refresh(),'Failed card lookup was attempted')
  check(not bad.wallet:session() and bad.wallet.problem:find('unavailable',1,true),'Failed lookup exposes problem without a session')
  eq(bad.log[#bad.log].op,'unlock','Failed lookup releases binding')
 end
 -- Regression: retry receipts update only the account that owned the failed
 -- settlement/refund. The credits receipt carries its persisted request owner.
 do
  local f=liveFixture('pinejack',{failSettle=true,failRetry=true}); local w=f.wallet; w:refresh()
  local ann=assert(w:begin(2,5)); check(not w:settle(ann,5),'Ann payout waits for acknowledgement')
  f:card('bo'); w:refresh(); check(not w:retry(),'Failed retry retains pending receipt ownership')
  eq(w:session().balance,100,'Failed retry preserves replacement card meter')
  f.options.failRetry=false; check(w:retry(),'Ann retry acknowledged with Bo inserted')
  eq(w:session().account,'bo','Retry preserves replacement session')
  eq(w:session().balance,100,'Ann retry cannot overwrite Bo meter')
  eq(f.balances.ann,103,'Retry settles original account only'); eq(f.balances.bo,100,'Retry leaves Bo host balance untouched')
  local bo=assert(w:begin(3,7)); check(not w:settle(bo,6),'Later Bo payout can also wait')
  check(w:retry(),'Later Bo retry succeeds'); eq(w:session().balance,103,'Later retry uses its own receipt account')
  f:card('ann'); w:refresh(); eq(w:session().balance,103,'Reinserted Ann card loads the paid balance')
 end
 do
  local f=liveFixture('pinebox',{failRefund=true}); local w=f.wallet; f.balances.bo=60; w:refresh()
  local ann=assert(w:begin(2,4)); check(not w:refund(ann),'Interrupted refund waits for acknowledgement')
  f:card('bo'); w:refresh(); check(w:retry(),'Ann refund retry succeeds after card swap')
  eq(f.balances.ann,100,'Refund returns Ann stake'); eq(w:session().balance,60,'Ann refund receipt cannot overwrite Bo meter')
 end
 -- The same regression through production credits, client, server and durable
 -- virtual stores: recovering Ann must leave Bo's separate open round intact.
 do
  local hub=require('tests.support.hub').new()
  local state=hub:state(); state.accounts['house-2']={name='Bo',balance=60}; state.nextAccount=2
  hub.host.require('derby.store').open('/house-bank/state',{}):save(state); hub:restartHost()
  local node=hub:computer(3); node.require('derby.config').write({role='station',modem='wired',host=1})
  node.client={call=function(_,fn) return fn() end}
  local function call(fn) return hub:call(node,'call',fn) end
  local current
  local function card(account)
   current={path='/disk',drive='drive_0',account=account}
   node.env.fs.makeDir('/disk')
   local file=assert(node.env.fs.open('/disk/house-card.json','w'))
   file.write(node.env.textutils.serializeJSON({account=account})); file.close()
  end
  local credits=node.require('credits')
  local w=node.require('casino.wallet').live('pinebox','TEST',credits,function() return current end)
  card('house-2'); call(function() return w:refresh() end)
  local bo=call(function() return w:begin(5,10) end); check(bo~=nil,'Real credits reserve Bo round')
  card('house-1'); call(function() return w:refresh() end)
  local ann=call(function() return w:begin(2,5) end); check(ann~=nil,'Real credits reserve Ann round')
  hub.hook=function(packet) if packet.from==1 then return false end end
  check(not call(function() return w:settle(ann,5) end),'Dropped real settlement reply enters pending state')
  eq(hub:state().accounts['house-1'].balance,103,'Real host paid Ann before lost acknowledgement')
  hub.hook=nil; card('house-2'); call(function() return w:refresh() end)
  eq(w:session().balance,55,'Real credits load Bo current host balance')
  check(call(function() return w:retry() end),'Real credits recover original settlement receipt')
  eq(w:session().account,'house-2','Real retry preserves newer card session')
  eq(w:session().balance,55,'Real retry keeps Bo display correct')
  local localState=node.require('derby.store').open('/house-client/state',{}):get()
  check(localState.rounds['house-1']==nil,'Real credits clear only recovered Ann round')
  eq(localState.rounds['house-2'].round,bo.round,'Real credits retain separate open Bo round')
  eq(hub:state().rounds[ann.round].status,'settled','Original host round is settled')
  eq(hub:state().rounds[bo.round].status,'open','Other host round remains open')
  eq(hub:state().accounts['house-1'].balance,103,'Lost reply retry does not duplicate Ann payout')
  eq(hub:state().accounts['house-2'].balance,55,'Lost reply retry does not pay Bo')
  check(call(function() return w:refund(bo) end),'Bo can still refund its own reserved stake')
  eq(w:session().balance,60,'Bo refund refreshes its own meter')
  -- Non-terminal operations also identify their receipt account; the wallet
  -- does not need transient knowledge of which call failed to update safely.
  hub.hook=function(packet) if packet.from==1 then return false end end
  check(not call(function() return w:begin(4,10) end),'Lost begin reply returns no acknowledged round')
  eq(w:session().balance,60,'Unacknowledged begin leaves old meter pending')
  hub.hook=nil; check(call(function() return w:retry() end),'Lost begin receipt can be recovered')
  eq(w:session().balance,56,'Recovered begin updates correct current account')
  local recovered=node.require('derby.store').open('/house-client/state',{}):get().last.request
  check(not call(function() return w:begin(4,10) end),'Recovered interrupted reservation cannot silently start another round')
  check(call(function() return w:refund(recovered) end),'Exact recovered reservation can be refunded')
  local raised=call(function() return w:begin(4,10) end); check(raised~=nil,'New round after refund')
  hub.hook=function(packet) if packet.from==1 then return false end end
  check(not call(function() return w:increase(raised,2,12) end),'Lost increase acknowledgement reported')
  eq(w:session().balance,56,'Unacknowledged increase preserves old display')
  hub.hook=nil; check(call(function() return w:retry() end),'Increase receipt recovered')
  eq(w:session().balance,54,'Recovered increase refreshes correct account balance')
  -- Recreate the complete client/wallet from its persisted virtual files, then
  -- replay that increase receipt with the other card inserted.
  node=hub:computer(3,node.files); node.client={call=function(_,fn) return fn() end}
  credits=node.require('credits'); card('house-1')
  w=node.require('casino.wallet').live('pinebox','TEST',credits,function() return current end)
  call(function() return w:refresh() end)
  local receipt=call(function() return {credits.retry()} end)
  eq(receipt[3],'house-2','Receipt owner survives client and wallet recreation')
  check(call(function() return w:retry() end),'Recreated wallet safely replays persisted receipt')
  eq(w:session().balance,103,'Recreated wallet leaves unrelated current card balance alone')
  card('house-2'); call(function() return w:refresh() end)
  check(call(function() return w:retry() end),'Recreated wallet can retry original account receipt')
  eq(w:session().balance,54,'Recreated wallet retains correct original account meter')
 end
 -- Actual Slots loop: commit before animation, lock input during spin, then recover
 -- a missing settlement acknowledgement without charging for a second round.
 do
  local f=liveFixture('pineslots',{failSettle=true,failRetry=true}); local rt=f.runtime
  rt:run('pineslots.machine',f.wallet,{random=function(lo) return lo end})
  rt:key('m'); rt:key('space')
  local calls=f:money(); eq(calls[1].game,'pineslots','Slots identifies the real game')
  eq(calls[1].stake,5,'Slots MAX stakes five'); eq(calls[1].maximum,206,'Slots reserves all-line maximum')
  eq(calls[2].op,'settle','Slots settles immediately before animation time advances')
  eq(rt.now,0,'Settlement attempted before first animation frame')
  rt:key('space'); eq(#f:money(),2,'Spinning slots ignores repeated pull')
  rt:tick(4); rt:key('c'); eq(#rt.ejections,0,'Slots blocks cashout while payout pending')
  rt:key('space'); eq(f:money()[3].op,'retry','Next pull retries the original request')
  rt:key('c'); eq(#rt.ejections,0,'Failed retry keeps cashout blocked')
  f.options.failSettle=false; f.options.failRetry=false; rt:key('space')
  eq(f:money()[4].op,'retry','A second retry does not reserve again')
  eq(f.wallet:session().balance,f.balances.ann,'Confirmed retry refreshes visible balance')
  rt:key('c'); eq(#rt.ejections,1,'Cashout becomes available after acknowledgement'); check(rt:quit(),'Slots exits after settlement')
 end
 -- Actual Jack loop: open, double and split reservations use total worst-case
 -- return, and a denied raise rolls back the hand before normal settlement.
 do
  local f=liveFixture('pinejack'); local rt=f.runtime
  rt:run('pinejack.game',f.wallet,{newShoe=stacked({'6','6','5','10','10','9'})}); rt:tick()
  rt:key('one',5); rt:key('two',5); rt:key('three',5)
  local calls=f:money(); eq(#calls,3,'Jack double has reserve, increase, one settlement')
  eq(calls[1].game,'pinejack','Jack game ID'); eq(calls[1].stake,4,'Jack selected stake')
  eq(calls[1].maximum,10,'Jack opening reservation covers 3:2 blackjack')
  eq(calls[2].stake,4,'Jack double adds original stake'); eq(calls[2].maximum,16,'Jack double maximum covers both stakes')
  eq(calls[3].amount,16,'Jack pays doubled win'); eq(f.balances.ann,108,'Jack double conserves expected account balance')
  check(rt:quit(),'Jack quits after settlement')
 end
 do
  local f=liveFixture('pinejack'); local rt=f.runtime
  rt:run('pinejack.game',f.wallet,{newShoe=stacked({'8','6','8','10','3','K','10','9'})}); rt:tick()
  for _,key in ipairs({'two','three','two','three','two'}) do rt:key(key,5) end
  local calls=f:money(); eq(#calls,4,'Split then double settles the combined round once')
  eq(calls[2].maximum,8,'Split reserves both hands'); eq(calls[3].maximum,12,'Double after split raises combined maximum')
  eq(calls[4].amount,12,'Both winning hands paid together'); eq(f.balances.ann,106,'Split and double balance')
  check(rt:quit(),'Split table returns to idle')
 end
 do
  local f=liveFixture('pinejack',{rejectIncrease=true}); local rt=f.runtime
  rt:run('pinejack.game',f.wallet,{newShoe=stacked({'6','10','5','7'})}); rt:tick(); rt:key('two',5); rt:key('three',5)
  eq(f.wallet:session().balance,98,'Denied double leaves original stake reserved')
  rt:key('two',5); local calls=f:money(); eq(calls[3].amount,0,'Denied double returns to normal decision and settlement')
  eq(f.balances.ann,98,'Denied double never charged'); check(rt:quit(),'Denied raise does not wedge Jack')
 end
 -- Actual Box loop: solo reserves 13x; shared seats increase one account round;
 -- cancellation refunds the ante, while separate cards settle their own accounts.
 do
  local f=liveFixture('pinebox'); local rt=f.runtime
  rt:run('pinebox.game',f.wallet,boxOptions({1,1,1,1})); rt:tick()
  for _,key in ipairs({'space','left','space','space','space','space','space'}) do rt:key(key,9) end
  local calls=f:money(); eq(#calls,2,'Box solo reserves and settles once')
  eq(calls[1].game,'pinebox','Box game ID'); eq(calls[1].stake,1,'Box solo stake'); eq(calls[1].maximum,13,'Box reserves 13x grand prize')
  eq(calls[2].amount,0,'Dead roll settles zero'); eq(f.balances.ann,99,'Box solo loss debited once'); check(rt:quit(),'Solo Box returns to idle')
 end
 do
  local f=liveFixture('pinebox'); local rt=f.runtime
  rt:run('pinebox.game',f.wallet,boxOptions({})); rt:tick()
  for _,key in ipairs({'space','space','space','left'}) do rt:key(key,9) end
  local calls=f:money(); eq(#calls,2,'Cancelled match makes no settlement request')
  eq(calls[1].maximum,2,'Match ante reserves full two-seat pot'); eq(calls[2].op,'refund','Cancelling match refunds first ante')
  eq(f.balances.ann,100,'Cancelled ante restored'); check(rt:quit(),'Cancelled Box returns to idle')
 end
 do
  local f=liveFixture('pinebox'); local rt=f.runtime
  rt:run('pinebox.game',f.wallet,boxOptions({1,1,1,1,1,1,1,1})); rt:tick()
  for _=1,10 do rt:key('space',9) end; rt:tick(6)
  local calls=f:money(); eq(#calls,3,'Shared-card seats use one reservation and one settlement')
  eq(calls[2].op,'increase','Second shared-card seat raises the existing round')
  eq(calls[2].maximum,2,'Shared-card increase retains whole-pot cover')
  eq(calls[3].amount,2,'Tied shared seats receive their combined pot'); eq(f.balances.ann,100,'Shared-card tie returns both antes')
  check(rt:quit(),'Shared-card match completes')
 end
 do
  local f=liveFixture('pinebox'); local rt=f.runtime
  rt:run('pinebox.game',f.wallet,boxOptions({1,1,1,1,1,1,1,1})); rt:tick()
  for _=1,3 do rt:key('space',9) end
  f:card('bo'); rt:send('disk'); rt:tick(2)
  for _=1,7 do rt:key('space',9) end; rt:tick(6)
  local calls=f:money(); eq(#calls,4,'Two-card match reserves and settles two account rounds')
  eq(calls[1].account,'ann','First ante belongs to first card'); eq(calls[2].account,'bo','Second ante belongs to replacement card')
  local paid={}; for _,call in ipairs(calls) do if call.op=='settle' then paid[call.account]=call.amount end end
  eq(paid.ann,1,'First tied account receives one'); eq(paid.bo,1,'Second tied account receives one')
  eq(f.balances.ann,100,'First account breaks even'); eq(f.balances.bo,100,'Second account breaks even'); check(rt:quit(),'Two-card match completes')
 end
 -- Exhibition selection is the production launcher decision, not a test-only
 -- switch. --demo overrides a configured station and never loads credits.
 do
  for _,game in ipairs({'pineslots','pinejack','pinebox'}) do
   for _,role in ipairs({'absent','host','station','cashier'}) do
    local env,stubs=isolated(root); local moneyLoads=0
    stubs['derby.config']={read=function() return role~='absent' and {role=role} or nil end}
    stubs['credits']=setmetatable({},{__index=function() moneyLoads=moneyLoads+1; error('Unexpected exhibition credits use') end})
    stubs['derby.ui']={card=function() return nil end}
    local w=env.require('casino.app').wallet({},game,'TEST')
    eq(w.mode,(role=='station' or role=='cashier') and 'live' or 'exhibition',game..' selects wallet for '..role)
    for _,flag in ipairs({'--demo','demo'}) do
     local demo=env.require('casino.app').wallet({flag},game,'TEST')
     eq(demo.mode,'exhibition',game..' explicit demo overrides '..role)
     local round=assert(demo:begin(5,206)); assert(demo:settle(round,12)); eq(demo:session().balance,107,'Practice meter uses local balance')
     eq(demo:cashout(),107,'Practice cashout reports practice total'); eq(demo:session().balance,100,'Practice cashout resets meter')
    end
    eq(moneyLoads,0,'Wallet selection/exhibition does not call credits')
   end
  end
 end
 -- Attract animation with no card is free, even on a live Slots cabinet.
 do
  local f=liveFixture('pineslots'); f:card(nil); local rt=f.runtime
  rt:run('pineslots.machine',f.wallet,{random=function(lo) return lo end}); rt:tick(10)
  check(#rt.frames>0,'Attract mode advances real animation frames'); eq(#f:money(),0,'Attract spin creates no reservation or payout')
  rt:key('space'); eq(#f:money(),0,'Pull without a card creates no paid round'); check(rt:quit(),'Attract can exit')
 end
 -- Free attractions currently have no house contract. Exercise an actual roll,
 -- shot, baseball outcome and dungeon turn with fail-fast network/money APIs.
 local function free(name)
  local env,stubs=isolated(repo..'/computercraft_scripts/'..name); local forbidden=0
  local poison=setmetatable({},{__index=function(_,key) forbidden=forbidden+1; error(name..' touched forbidden paid/network API '..tostring(key)) end})
  env.rednet=poison; env.http=poison; env.credits=poison; env.wallet=poison; env.disk=poison; env.fs=poison
  -- A speaker is neither paid nor networked: looking one up finds none, and every other
  -- peripheral call is still forbidden.
  env.peripheral=setmetatable({find=function(kind,...)
   if kind=='speaker' then return nil end
   forbidden=forbidden+1; error(name..' looked for peripheral '..tostring(kind))
  end},{__index=poison})
  local requireLocal=env.require
  env.require=function(module)
   if module=='credits' or module=='casino.wallet' or module:match('^derby%.') then forbidden=forbidden+1; error(name..' unexpectedly requires house module '..module) end
   return requireLocal(module)
  end
  return env.require('lib.app'),function() eq(forbidden,0,name..' gameplay stays free and offline') end
 end
 do
  local App,verify=free('pine-lanes'); local app=App.new({seed=7})
  app:action('start'); app:action('mascot_confirm'); eq(app.phase,'AIM','Free bowling starts without card')
  app:action('roll'); app:action('skip')
  for _=1,100 do if app.phase=='RESULT' then break end; app:tick(.1) end
  eq(app.phase,'RESULT','Free bowling completes real simulated roll'); check(app.rollSummary~=nil,'Bowling records scored roll')
  app:action('pause'); app:action('quit'); check(not app.running,'Bowling can exit'); verify()
 end
 do
  local App,verify=free('pine-links'); local app=App.new()
  app:action('start'); eq(app.phase,'AIM','Free golf starts without card')
  app:action('swing'); app:action('skip'); app:tick(.1)
  check(app.phase=='AIM' or app.phase=='SCORECARD','Free golf finishes real shot')
  check(app:state().strokes>=1,'Golf scores the shot'); app:action('quit'); check(not app.running,'Golf can exit'); verify()
 end
 do
  local App,verify=free('pine-ball'); local commits=0
  local app=App.new({seed=7,record=function(kind) if kind=='commit' then commits=commits+1 end end})
  app:action('start'); app:action('swing')
  for _=1,2000 do if commits>0 then break end; app:advance(20) end
  check(commits>0,'Free baseball completes actual pitch outcome'); app:action('pause'); app:action('quit'); check(not app.running,'Baseball can exit'); verify()
 end
 do
  local App,verify=free('pine-dungeon'); local app=App.new(); local turn=app.state.turn
  app:action('wait'); check(app.state.turn>turn,'Free dungeon consumes a real turn without card')
  app:action('quit'); check(not app.running,'Dungeon can exit'); verify()
 end
end
