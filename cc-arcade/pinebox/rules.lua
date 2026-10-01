-- Shut the Box, played as a grand prize round: tiles 1-9, always two dice, remove any
-- tiles that add up to the roll. A roll that no remaining tiles can make ends the round;
-- clearing all nine wins the grand prize. The board is a 9-bit mask (bit i = tile i+1).
local M={}
M.full=511
M.bets={1,2,5,10}
-- With perfect play the board clears 7.14% of the time; 13x returns about 93%.
M.prize=13
local sums={}
for m=0,M.full do local s=0; for i=0,8 do if bit32.btest(m,2^i) then s=s+i+1 end end; sums[m]=s end
function M.sum(m) return sums[m] end
function M.has(m,tile) return bit32.btest(m,2^(tile-1)) end
function M.tiles(m) local out={}; for i=1,9 do if M.has(m,i) then out[#out+1]=i end end; return out end
-- Every set of remaining tiles adding up to the roll, as masks, fewest tiles first.
function M.moves(board,roll)
 local out={}
 local sub=board
 while sub>0 do
  if sums[sub]==roll then out[#out+1]=sub end
  sub=bit32.band(sub-1,board)
 end
 local function count(m) return #M.tiles(m) end
 table.sort(out,function(a,b) if count(a)~=count(b) then return count(a)<count(b) end return a>b end)
 return out
end
-- Chance of clearing the board from each position with perfect play, and the best move.
local chance,best
local function solve()
 chance={[0]=1}; best={}
 -- Removing tiles only lowers the mask, so solve from small masks upward.
 for m=1,M.full do
  local p=0; best[m]={}
  for roll=2,12 do
   local ways=6-math.abs(roll-7)
   local top,choice=0,nil
   local sub=m
   while sub>0 do
    if sums[sub]==roll then
     local q=chance[bit32.band(m,bit32.bnot(sub))]
     if q>top or not choice then top,choice=q,sub end
    end
    sub=bit32.band(sub-1,m)
   end
   best[m][roll]=choice; p=p+ways*top
  end
  chance[m]=p/36
 end
end
function M.chance(board) if not chance then solve() end return chance[board] end
function M.best(board,roll) if not best then solve() end return board>0 and best[board][roll] or nil end
return M
