-- Where a table's credits come from. Exhibition keeps practice balances on the
-- table computer and never touches the house. House play (reserve per seat,
-- settle the whole table at once) needs a ledger operation that is not built yet.
local M={}
local STARTING=100
function M.exhibition()
 local balances={}
 local b={mode='exhibition'}
 function b:balance(account) if balances[account]==nil then balances[account]=STARTING end return balances[account] end
 function b:stake(account,amount)
  if b:balance(account)<amount then return false,'Not enough credits' end
  balances[account]=balances[account]-amount; return true
 end
 function b:pay(account,amount) balances[account]=b:balance(account)+amount end
 return b
end
return M
