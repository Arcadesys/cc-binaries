-- High Card: every player antes and flips one card. Alone you play the house
-- (win pays 2x, tie pushes); with company the highest card takes the pot.
--
-- Game interface used by tables.host:
--  new(players,rng)      players = {{seat=,name=},...} in seat order
--  view(s,seat)          seat view, or the public table view when seat is nil
--  press(s,seat,button)  a player's button; returns true when it changed state
--  pending(s,seat)       true while the table waits on this seat
--  auto(s,seat)          the default move for an absent or idle seat
--  payouts(s)            nil while playing, then {[seat]=credits returned}
--  maximum(s)            the most the hand can return in total (the host enforces it)
local M={id='highcard',title='HIGH CARD',ante=5}
local RANKS={'2','3','4','5','6','7','8','9','10','J','Q','K','A'}
local SUITS={'S','H','D','C'}
local function name(c) return RANKS[c.rank]..SUITS[c.suit] end
function M.new(players,rng)
 local deck={}
 for s=1,4 do for r=1,13 do deck[#deck+1]={rank=r,suit=s} end end
 for i=#deck,2,-1 do local j=rng(i); deck[i],deck[j]=deck[j],deck[i] end
 local s={players={},house=#players==1,pot=M.ante*#players}
 for _,p in ipairs(players) do s.players[p.seat]={name=p.name,card=table.remove(deck),shown=false} end
 if s.house then s.dealer=table.remove(deck) end
 return s
end
function M.pending(s,seat) local p=s.players[seat]; return p~=nil and not p.shown end
function M.press(s,seat,button)
 if button~='flip' or not M.pending(s,seat) then return false end
 s.players[seat].shown=true; return true
end
function M.maximum(s) return s.house and 2*M.ante or s.pot end
M.auto=function(s,seat) return M.press(s,seat,'flip') end
local function done(s) for seat in pairs(s.players) do if M.pending(s,seat) then return false end end return true end
function M.payouts(s)
 if not done(s) then return nil end
 local out={}
 if s.house then
  local seat,p=next(s.players)
  out[seat]=p.card.rank>s.dealer.rank and 2*M.ante or p.card.rank==s.dealer.rank and M.ante or 0
  return out
 end
 local best=0; local winners={}
 for seat,p in pairs(s.players) do
  if p.card.rank>best then best=p.card.rank; winners={seat} elseif p.card.rank==best then winners[#winners+1]=seat end
 end
 table.sort(winners)
 -- Split ties; the lowest seat keeps any odd credit so the pot is paid exactly.
 local share=math.floor(s.pot/#winners)
 for seat in pairs(s.players) do out[seat]=0 end
 for _,seat in ipairs(winners) do out[seat]=share end
 out[winners[1]]=out[winners[1]]+s.pot-share*#winners
 return out
end
function M.view(s,seat)
 local lines={}
 local over=done(s)
 if s.house then lines[#lines+1]={'House: '..(over and name(s.dealer) or '??'),colors.orange} else lines[#lines+1]={'Pot: '..s.pot..' credits',colors.yellow} end
 local seats={}; for k in pairs(s.players) do seats[#seats+1]=k end; table.sort(seats)
 for _,k in ipairs(seats) do
  local p=s.players[k]
  local card=(p.shown or k==seat) and name(p.card) or '??'
  lines[#lines+1]={(k==seat and '> ' or '  ')..'Seat '..k..' '..p.name..': '..card..(p.shown and '' or ' (hidden)'),k==seat and colors.white or colors.lightGray}
 end
 local buttons={}
 if seat and M.pending(s,seat) then buttons[1]={id='flip',label='FLIP YOUR CARD'} end
 return {lines=lines,buttons=buttons}
end
return M
