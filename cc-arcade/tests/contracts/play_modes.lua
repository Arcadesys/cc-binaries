-- Proposed-mode acceptance oracle, NOT a deployed protocol/wallet implementation.
local M={capabilities={
 single_house={ledger=true,productionAdmission=true,targetRTP=.98,certified=false},
 multiplayer_vs={ledger=false,productionAdmission=false,rake=1},
 multiplayer_house_blackjack={ledger=false,productionAdmission=false},
 arcade_entry={ledger=true,productionAdmission=false},
}}
local function integer(n) return type(n)=='number' and n>=0 and n%1==0 end
function M.validateReceipt(match,receipt)
 if type(match.id)~='string' or receipt.match~=match.id then return false end
 local paid,total=0,0
 for id,ante in pairs(match.antes) do
  if not integer(ante) then return false end
  total=total+ante
  local amount=receipt.payouts[id] or 0
  if not integer(amount) or (not match.winners[id] and amount~=0) then return false end
 end
 for id,amount in pairs(receipt.payouts) do
  if match.antes[id]==nil or not integer(amount) then return false end
  paid=paid+amount
 end
 return receipt.rake==1 and total>=1 and paid+receipt.rake==total
end
M.matches={
 {name='two players one winner',match={id='m1',antes={a=5,b=5},winners={a=true}},receipt={match='m1',rake=1,payouts={a=9,b=0}}},
 {name='four players one winner',match={id='m2',antes={a=5,b=5,c=5,d=5},winners={c=true}},receipt={match='m2',rake=1,payouts={c=19}}},
 -- Conservation only: deciding who gets an odd tie credit is still a policy choice.
 {name='tied winners preserve odd credit',match={id='m3',antes={a=5,b=5},winners={a=true,b=true}},receipt={match='m3',rake=1,payouts={a=5,b=4}}},
}
function M.test(check,eq)
 for _,case in ipairs(M.matches) do
  check(M.validateReceipt(case.match,case.receipt),case.name)
  case.receipt.rake=2; check(not M.validateReceipt(case.match,case.receipt),'Exactly one-credit rake'); case.receipt.rake=1
 end
 check(not M.validateReceipt(M.matches[3].match,{match='m3',rake=1,payouts={a=4,b=4}}),'Tie rounding cannot lose credits')
 check(not M.validateReceipt(M.matches[1].match,{match='m1',rake=1,payouts={a=8,b=1}}),'Loser cannot receive winning pot')
 check(not M.validateReceipt(M.matches[1].match,{match='other',rake=1,payouts={a=9}}),'Receipt bound to match')
 eq(M.capabilities.multiplayer_vs.ledger,false,'No atomic multi-account pot primitive in current v1')
 eq(M.capabilities.arcade_entry.productionAdmission,false,'Freeplay attractions still need admission wiring')
 eq(M.capabilities.single_house.certified,false,'Target RTP is not measured house edge')
end
return M
