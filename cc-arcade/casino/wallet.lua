-- Where credits come from, shared by the Pine3D casino games. Live play uses the house:
-- the card in the drive names an account, each round reserves its stake and largest
-- possible return, then settles.
-- Exhibition play uses a local practice meter and never touches the house.
local M={}
local STARTING=100
function M.exhibition(name)
 local w={mode='exhibition',title=(name or 'PINE CASINO')..' | EXHIBITION - NO MONEY'}
 local s={name='PRACTICE',balance=STARTING}
 function w:refresh() return false end
 function w:session() return s end
 function w:begin(stake)
  if s.balance<stake then return nil,'Not enough credits' end
  s.balance=s.balance-stake; return {stake=stake}
 end
 function w:increase(round,stake)
  if s.balance<stake then return false,'Not enough credits' end
  s.balance=s.balance-stake; round.stake=round.stake+stake; return true
 end
 function w:settle(_,amount) s.balance=s.balance+amount; return true,s.balance end
 function w:refund(round) s.balance=s.balance+round.stake; return true end
 function w:retry() return true end
 function w:cashout() local had=s.balance; s.balance=STARTING; return had end
 return w
end
-- game: ledger game id; name: title; credits: the arcade credits module;
-- card: returns the inserted disk, if any.
function M.live(game,name,credits,card)
 credits=credits or require('credits')
 card=card or require('derby.ui').card
 local w={mode='live',title=name or 'PINE CASINO'}
 local current,ejecting,waiting
 local function same(a,b) return a and b and a.path==b.path and a.account==b.account end
 -- Re-reads the drive. Returns true when the inserted card changed.
 function w:refresh()
  local c=card()
  if ejecting then if c and c.drive==ejecting then c=nil else ejecting=nil end end
  if same(c,current) or (not c and not current) then return false end
  if current then credits.unlock(current.path) end
  current=nil; w.problem=nil
  if c and c.account then
   local ok,err=pcall(function()
    credits.lock(c.path); c.name=credits.getName(c.path) or 'PLAYER'; c.balance=credits.get(c.path)
   end)
   if ok then current=c else credits.unlock(c.path); w.problem=tostring(err):gsub('^HOUSE: ','') end
  elseif c then w.problem='Not a house card. Visit the cashier.' end
  return true
 end
 function w:session() return current end
 function w:begin(stake,maximum)
  if not current then return nil,'Insert your house card' end
  local round,err,context=credits.beginRound(game,stake,maximum,current.path)
  if not round then waiting=context and context.request; return nil,err,context end
  waiting=nil
  current.balance=current.balance-stake
  return round
 end
 -- Raise the stake mid-round (double down, split); maximum covers the new best case.
 function w:increase(round,stake,maximum)
  local ok,err,context=credits.increaseRound(round,stake,maximum)
  if not ok then
   waiting=context and context.request or {op='increase',account=round.account,round=round.round,stake=stake,maximum=maximum}
   return false,err,context
  end
  waiting=nil
  if current and current.account==round.account then current.balance=current.balance-stake end
  return true
 end
 -- Settles even if the card was pulled mid-spin: the round names its own account.
 function w:settle(round,amount)
  local ok,balance=pcall(credits.settleRound,round,amount)
  if not ok then waiting={op='settle',round=round.round,account=round.account,amount=amount}; return false,tostring(balance) end
  waiting=nil
  if current and current.account==round.account then current.balance=balance end
  return true,balance
 end
 -- Hands a round's whole stake back (a cancelled table).
 function w:refund(round)
  local ok,err=pcall(credits.refundRound,round)
  if not ok then waiting={op='refund',round=round.round,account=round.account}; return false,tostring(err) end
  waiting=nil
  if current and current.account==round.account then current.balance=current.balance+round.stake end
  return true
 end
 function w:retry()
  local ok,r,account,context=credits.retry()
  local request=context and context.request
  local matches=true
  if waiting then
   matches=request~=nil
   for key,value in pairs(waiting) do if not request or request[key]~=value then matches=false end end
  end
  context=context or {}; context.matches=matches
  -- The durable request identifies this receipt's account, including retries
  -- after a restart. The card currently in the drive may belong to someone else.
  if current and current.account==account then
   if context.balance~=nil then current.balance=context.balance
   elseif ok and r and r.balance then current.balance=r.balance end
  end
  -- Its balance is valid for its own account, but a recovered increase is not
  -- acknowledgement of a later blocked settlement. Keep that wait unresolved.
  if not matches then return false,'Recovered a different operation; cashier review is required',context end
  if ok or (context.status and context.status~='open' and not context.pending) then waiting=nil end
  return ok,r,context
 end
 -- Hands the card back. The balance stays on the account for the cashier or another game.
 function w:cashout()
  local c=current; if not c then return nil end
  credits.unlock(c.path); current=nil; ejecting=c.drive
  if c.drive then pcall(disk.eject,c.drive) end
  return c.balance
 end
 return w
end
return M
