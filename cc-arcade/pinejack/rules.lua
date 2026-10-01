-- Blackjack rules: six-deck shoe, dealer stands on soft 17 and peeks for blackjack,
-- blackjack pays 3:2, double on any first two cards (also after a split), one split,
-- split aces take one card each. All amounts are whole credits; bets are even.
local M={}
M.decks=6
M.cut=.75
M.bets={2,4,10,20,50}
M.ranks={'A','2','3','4','5','6','7','8','9','10','J','Q','K'}
M.suits={'S','H','D','C'}
M.red={H=true,D=true}
function M.value(rank)
 if rank=='A' then return 1 end
 if rank=='J' or rank=='Q' or rank=='K' then return 10 end
 return tonumber(rank)
end
function M.newShoe(random)
 random=random or math.random
 local s={cards={},next=1}
 for _=1,M.decks do for _,su in ipairs(M.suits) do for _,r in ipairs(M.ranks) do s.cards[#s.cards+1]={rank=r,suit=su} end end end
 for i=#s.cards,2,-1 do local j=random(1,i); s.cards[i],s.cards[j]=s.cards[j],s.cards[i] end
 return s
end
function M.draw(shoe) local c=shoe.cards[shoe.next]; shoe.next=shoe.next+1; return {rank=c.rank,suit=c.suit} end
function M.needsShuffle(shoe) return shoe.next>#shoe.cards*M.cut end
-- Total and whether an ace is counted as 11.
function M.total(cards)
 local t,aces=0,0
 for _,c in ipairs(cards) do t=t+M.value(c.rank); if c.rank=='A' then aces=aces+1 end end
 if aces>0 and t+10<=21 then return t+10,true end
 return t,false
end
function M.blackjack(hand) return #hand.cards==2 and not hand.split and M.total(hand.cards)==21 end
function M.bust(cards) return M.total(cards)>21 end
function M.canDouble(hand) return #hand.cards==2 and not hand.doubled and not hand.aces end
function M.canSplit(hands,hand)
 return #hands==1 and #hand.cards==2 and M.value(hand.cards[1].rank)==M.value(hand.cards[2].rank)
end
function M.dealerHits(cards)
 local t=M.total(cards)
 return t<17
end
-- What one hand returns to the player (stake included) against the dealer's final cards.
function M.handReturn(hand,dealer)
 local mine=M.total(hand.cards)
 if mine>21 then return 0,'BUST' end
 local bj,dbj=M.blackjack(hand),#dealer==2 and M.total(dealer)==21
 if bj and dbj then return hand.stake,'PUSH' end
 if bj then return hand.stake+math.floor(hand.stake*3/2),'BLACKJACK' end
 if dbj then return 0,'LOSE' end
 local theirs=M.total(dealer)
 if theirs>21 or mine>theirs then return hand.stake*2,'WIN' end
 if mine==theirs then return hand.stake,'PUSH' end
 return 0,'LOSE'
end
-- The most the current hands could still return: what the house must reserve.
function M.maximum(hands)
 local n=0
 for _,h in ipairs(hands) do
  if #h.cards<=2 and not h.split and not h.doubled then n=n+h.stake+math.floor(h.stake*3/2)
  else n=n+h.stake*2 end
 end
 return n
end
function M.describe(c) return c.rank..({S='\6',H='\3',D='\4',C='\5'})[c.suit] end
return M
