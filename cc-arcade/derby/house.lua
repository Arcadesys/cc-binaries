local ledger=require('derby.ledger')
local sim=require('derby.sim')
local M={}
function M.new(odds)
 local s=ledger.new(); s.raceNumber=0; s.paused=false; s.odds=odds
 return s
end
function M.nextRace(s,seed)
 s.raceNumber=s.raceNumber+1
 s.race={id='race-'..s.raceNumber,phase='OPEN',elapsed=0,seed=seed,tickets={},payouts=s.odds.payouts,oddsVersion=s.odds.version}
end
function M.bet(s,q)
 s.ticketReceipts=s.ticketReceipts or {}
 local receipt=s.ticketReceipts[q.id]
 if receipt then
  if receipt.account==q.account and receipt.race==q.race and receipt.horse==q.horse and receipt.stake==q.stake then return {ok=true,ticket=receipt.ticket} end
  return {ok=false,error='Transaction reused with different ticket'}
 end
 local race=s.race
 if not race or race.id~=q.race or race.phase~='OPEN' or s.paused then return {ok=false,error='Betting is closed'} end
 local old=race.tickets[q.account]
 if old then
  if old.transaction==q.id and old.horse==q.horse and old.stake==q.stake then return {ok=true,ticket=old} end
  return {ok=false,error='One confirmed ticket per account per race'}
 end
 if q.horse~=1 and q.horse~=2 and q.horse~=3 then return {ok=false,error='Choose a horse'} end
 if q.stake~=5 and q.stake~=10 and q.stake~=20 then return {ok=false,error='Choose 5, 10 or 20 credits'} end
 local payout=race.payouts[q.horse][tostring(q.stake)]
 local round=race.id..':'..q.account
 local r=ledger.apply(s,{op='reserve',id=q.id,round=round,account=q.account,stake=q.stake,maximum=math.max(q.stake,payout),game='derby',owner='host'})
 if not r.ok then return r end
 local ticket={horse=q.horse,stake=q.stake,returns=payout,round=round,transaction=q.id}
 race.tickets[q.account]=ticket
 s.ticketReceipts[q.id]={account=q.account,race=q.race,horse=q.horse,stake=q.stake,ticket=ticket}
 return {ok=true,ticket=ticket,balance=r.balance}
end
local function settle(s,cancel)
 local race=s.race
 for account,t in pairs(race.tickets) do
  local r=ledger.apply(s,{op=cancel and 'refund' or 'settle',id=race.id..':result:'..account,round=t.round,account=account,
   amount=not cancel and race.sim.order[1]==t.horse and t.returns or 0,owner='host'})
  assert(r.ok,r.error)
  t.paid=r.paid
 end
 race.phase=cancel and 'CANCELLED' or 'RESULT'; race.elapsed=0
end
function M.cancel(s)
 if not s.race or (s.race.phase~='OPEN' and s.race.phase~='LOCKED') then return {ok=false,error='Only unstarted races can be cancelled'} end
 if next(s.pending) then return {ok=false,error='Reconcile cashier first'} end
 settle(s,true); return {ok=true}
end
function M.tick(s,seed)
 if s.paused or next(s.pending) then return end
 if not s.race then M.nextRace(s,seed); return end
 local r=s.race
 r.elapsed=r.elapsed+1 -- tenths, advanced by the host only
 if r.phase=='OPEN' and r.elapsed>=600 then r.phase='LOCKED'; r.elapsed=0; r.sim=sim.new(r.seed)
 elseif r.phase=='LOCKED' and r.elapsed>=50 then r.phase='RUNNING'; r.elapsed=0
 elseif r.phase=='RUNNING' then sim.step(r.sim); if #r.sim.order==3 then settle(s,false) end
 elseif (r.phase=='RESULT' or r.phase=='CANCELLED') and r.elapsed>=150 then M.nextRace(s,seed) end
end
function M.snapshot(s,account)
 local r=s.race
 if not r then return {ok=true,paused=s.paused} end
 local seconds=r.phase=='OPEN' and math.ceil((600-r.elapsed)/10) or r.phase=='LOCKED' and math.ceil((50-r.elapsed)/10) or 0
 return {ok=true,id=r.id,phase=r.phase,paused=s.paused or next(s.pending)~=nil,seconds=seconds,payouts=r.payouts,
  positions=r.sim and sim.positions(r.sim) or {0,0,0},tick=r.sim and r.sim.tick or 0,
  order=r.sim and r.sim.order or {},ticket=account and r.tickets[account] or nil,oddsVersion=r.oddsVersion}
end
return M
