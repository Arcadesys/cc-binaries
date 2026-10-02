-- The v2 exchange operation is explicitly gated inside the existing credit wire
-- protocol: games retain whole-credit reserve/settle semantics unchanged.
local Hub=require('tests.support.hub')
local currency=require('derby.currency')
local passed=0
local function check(v,m) assert(v,m); passed=passed+1 end
local function eq(a,b,m) check(a==b,(m or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local function setup()
 local h=Hub.new()
 local state=h:state(); state.paused=true
 local db=h.host.require('derby.store').open('/house-bank/state',{})
 db:save(state)
 local svc=h.host.require('derby.service').new(db,{bank='bank',intake='intake',payout='output'},function(n) return h.inventories[n] end)
 check(svc:operator('currency').ok,'migrate real persisted host')
 h:restartHost()
 return h,h:client(2)
end
local function deposit()
 local p=currency.default()
 return {op='exchange',apiVersion=2,account='house-1',entryId='diamond',direction='deposit',requestedItems=5,policyId=p.policyId,policyRevision=p.revision}
end
local h,c=setup()
local policy=h:call(c,'read',{op='currency'}); eq(policy.apiVersion,2); eq(policy.policy.entries.diamond.unitsPerItem,1)
local r=h:call(c,'mutate',deposit()); eq(r.confirmedItems,5); eq(r.balance,105)
eq(h:state().version,2)
local old=h:call(c,'mutate',{op='deposit',account='house-1',amount=5}); check(not old.ok,'v1 quantity path rejected after migration')
local station=h:client(3); check(not h:call(station,'mutate',deposit()).ok,'station cannot exchange')
local display=h:client(5); check(not h:call(display,'mutate',deposit()).ok,'display cannot exchange')
-- Loss, reboot, identical replay returns one receipt, no double movement.
h,c=setup()
h.hook=function(packet) if packet.from==1 then return false end end
r=h:call(c,'mutate',deposit()); check(r.offline,'drop receipt')
local moves=h.inventories.intake.moves
h.hook=nil; h:restartHost(); c=h:restartClient(c)
r=h:call(c,'retry'); eq(r.confirmedItems,5); eq(r.balance,105); eq(h.inventories.intake.moves,moves)
-- Unknown physical outcome retains the client request as well as host intent.
h,c=setup(); h.inventories.intake.failAfterMove=true
r=h:call(c,'mutate',deposit()); check(r.pending,'client sees pending uncertainty'); check(c.client:localState().pending,'client retains original request')
local id=c.client:localState().pending.id; moves=h.inventories.intake.moves
h.inventories.intake.failAfterMove=false; h:restartHost(); c=h:restartClient(c)
r=h:call(c,'retry'); check(r.pending); eq(h.inventories.intake.moves,moves,'never replay uncertain push')
local db=h.host.require('derby.store').open('/house-bank/state',{})
local svc=h.host.require('derby.service').new(db,{bank='bank',intake='intake',payout='output'},function(n) return h.inventories[n] end)
check(svc:operator('reconcile',id,5).ok); h:restartHost()
r=h:call(c,'retry'); eq(r.balance,105); eq(r.confirmedItems,5); check(not c.client:localState().pending)
-- A new host still accepts unchanged whole-credit game reservations and payouts.
station=h:client(3)
r=h:call(station,'mutate',{op='reserve',account='house-1',game='fixture',round='round-v2',stake=5,maximum=10}); check(r.ok,'existing game credit request')
r=h:call(station,'mutate',{op='settle',account='house-1',round='round-v2',amount=10}); eq(r.balance,110)
print('PASS '..passed..' production currency wire assertions')
