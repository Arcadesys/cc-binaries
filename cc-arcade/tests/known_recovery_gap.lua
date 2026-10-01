-- Non-default release gate for the existing interrupted-increase recovery gap.
-- Run from repository root:
--   python3 cc-arcade/tools/test_contracts.py --suite tests/known_recovery_gap.lua
-- EXPECTED TODAY: exit 1. Do not suppress this failure or count it as readiness.
-- This executes the actual wallet, credits, client, server and store over the
-- isolated fake-Rednet hub. No copied ledger, invented paid APIs or live hardware.
local hub=require('tests.support.hub').new()
local node=hub:computer(3)
node.require('derby.config').write({role='station',modem='wired',host=1})
node.env.fs.makeDir('/disk')
local file=assert(node.env.fs.open('/disk/house-card.json','w'))
file.write(node.env.textutils.serializeJSON({account='house-1'})); file.close()
local function run(fn)
 hub:task(node,fn); hub:pump()
 if not node.finished then hub:timeout(node); hub:pump() end
 assert(node.finished,'Fixture operation did not finish')
 return node.result
end
local credits=node.require('credits')
local wallet=node.require('casino.wallet').live('pinejack','RECOVERY GATE',credits,function()
 return {path='/disk',drive='drive_0',account='house-1'}
end)
assert(run(function() return wallet:refresh() end),'Fixture card was not read')
-- 1. Reserve 4 with a maximum of 10, acknowledged normally.
local round=assert(run(function() return wallet:begin(4,10) end))
-- 2. Host commits +2 stake / maximum 12, but its acknowledgement is lost.
hub.hook=function(packet) if packet.from==1 then return false end end
assert(not run(function() return wallet:increase(round,2,12) end),'Fault must lose the increase acknowledgement')
local raised=hub:state().rounds[round.round]
assert(raised.stake==6 and raised.maximum==12,'Fixture host must have committed the increase')
-- 3. A subsequent settlement cannot be sent while that increase is pending.
--    This is a real wallet/credits call sequence, not a full Jack event-loop test.
assert(not run(function() return wallet:settle(round,0) end),'Pending increase must block the settlement request')
-- 4. Retry acknowledges the original increase; it must preserve authoritative
--    round metadata for subsequent gameplay/refund recovery.
hub.hook=nil
assert(run(function() return wallet:retry() end),'Fixture retry must recover the increase receipt')
local saved=node.require('derby.store').open('/house-client/state',{}):get()
local persisted=assert(saved.rounds[round.account],'Saved open round disappeared')
local host=hub:state().rounds[round.round]
print(('DIAGNOSTIC: settlement was blocked; retry acknowledged %s; host round remains %s')
 :format(saved.last.request.op,host.status))
-- The diagnostic above also identifies why a game's generic payout-retry loop
-- cannot treat every successful retry as a completed settlement. Its continuation
-- needs an additional actual-game regression in the separately reviewed fix.
local failures={}
local function same(label,actual,expected)
 if actual~=expected then failures[#failures+1]=label..'='..tostring(actual)..', host='..tostring(expected) end
end
same('captured stake',round.stake,host.stake)
same('persisted stake',persisted.stake,host.stake)
same('captured maximum',round.maximum,host.maximum)
same('persisted maximum',persisted.maximum,host.maximum)
assert(#failures==0,'KNOWN RECOVERY GAP: interrupted increase metadata did not converge: '..table.concat(failures,'; '))
print('PASS interrupted increase metadata release gate')
return true
