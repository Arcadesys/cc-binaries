-- Reproducible proposed payout analysis. No production tables/files are changed.
-- Run: python3 cc-arcade/tools/test_contracts.py --suite tests/payout_analysis.lua
-- Slots are exhaustively enumerated. PineBox assumes fair independent two-die
-- rolls and optimal decisions: it does NOT promise a fixed edge for all players.
local reels = require('pineslots.reels')
local checkCount = 0
local function check(condition, message)
 checkCount = checkCount + 1; assert(condition, message)
end
local function close(a, b, message) check(math.abs(a - b) < 1e-12, message) end

-- Load unmodified CC rules with just their required bit32 API. The arithmetic
-- fallback keeps this report compatible with stock Lua 5.4 and CC's Lua 5.2.
local bitlib = bit32
if not bitlib then
 bitlib = {}
 function bitlib.band(a, b)
  a, b = a % 4294967296, b % 4294967296
  local result, place = 0, 1
  while a > 0 and b > 0 do
   if a % 2 == 1 and b % 2 == 1 then result = result + place end
   a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
  end
  return result
 end
 function bitlib.bnot(a) return 4294967295 - a % 4294967296 end
 function bitlib.btest(a, b) return bitlib.band(a, b) ~= 0 end
end
local rules = assert(loadfile('pinebox/rules.lua', 't', setmetatable({bit32 = bitlib}, {__index = _G})))()

local proposal = {D = 300, S = 100, R = 30, B = 15, P = 10, C = 10}
local cherries = {1, 3}
local function linePay(a, b, c, tableOfThree, tableOfCherries)
 if a == b and b == c then return tableOfThree[a] end
 if a == 'C' then return b == 'C' and tableOfCherries[2] or tableOfCherries[1] end
 return 0
end
local function evaluate(stops, bet, tableOfThree, tableOfCherries)
 local total = 0
 for line = 1, bet do
  local symbols = {}
  for reel = 1, 3 do symbols[reel] = reels.symbol(reel, stops[reel] + reels.lines[line][reel]) end
  total = total + linePay(symbols[1], symbols[2], symbols[3], tableOfThree, tableOfCherries)
 end
 return total
end

local current, proposed, outcomeCount, categories = {}, {}, 0, {}
for bet = 1, reels.maxBet do
 current[bet] = {paid = 0, maximum = 0, hits = 0}
 proposed[bet] = {paid = 0, maximum = 0, hits = 0}
end
for a = 0, reels.size - 1 do for b = 0, reels.size - 1 do for c = 0, reels.size - 1 do
 local stops = {a, b, c}; outcomeCount = outcomeCount + 1
 local x, y, z = reels.symbol(1, a), reels.symbol(2, b), reels.symbol(3, c)
 local category = x == y and y == z and x or x == 'C' and (y == 'C' and 'CC' or 'C1') or 'loss'
 categories[category] = (categories[category] or 0) + 1
 for bet = 1, reels.maxBet do
  local existing = reels.evaluate(stops, bet)
  check(existing == evaluate(stops, bet, reels.three, reels.cherry), 'Independent evaluation differs from production slots')
  local candidate = evaluate(stops, bet, proposal, cherries)
  for _, entry in ipairs({{current[bet], existing}, {proposed[bet], candidate}}) do
   local stats, amount = entry[1], entry[2]
   stats.paid = stats.paid + amount; stats.maximum = math.max(stats.maximum, amount)
   if amount > 0 then stats.hits = stats.hits + 1 end
  end
 end
end end end
check(outcomeCount == 4096, 'Expected source reel geometry changed; re-evaluate proposal')
check(current[1].paid == 3894, 'Current payout changed; update this analysis deliberately')
check(proposed[1].paid == 4014, 'Proposed payout total')
for bet = 1, reels.maxBet do
 close(current[bet].paid / (outcomeCount * bet), reels.stats().rtp, 'Per-line current RTP')
 check(current[bet].maximum == reels.maxReturn(bet), 'Current reservation maximum')
 check(proposed[bet].paid == 4014 * bet, 'Proposed RTP differs by line count')
 check(proposed[bet].maximum == ({300, 303, 304, 305, 306})[bet], 'Proposed reservation maximum')
end
-- 98% = 49/50. A deterministic integer return summed over 4096 outcomes cannot
-- equal 4096*49/50; 4014 is the closest representable total below the target.
check(outcomeCount * 49 % 50 ~= 0, 'Recheck exact 98% representability')
check(4014 == math.floor(outcomeCount * .98), 'Nearest deterministic integer-return total')

-- Independent optimal-clear dynamic program. Enumerate all removal masks by sum,
-- then choose the largest continuation value for each two-die total. The source
-- rules' chance and best move are checked for EVERY board, not only the start.
local sums, byTotal = {}, {}
for mask = 1, rules.full do
 local total = 0
 for tile = 1, 9 do if math.floor(mask / 2^(tile - 1)) % 2 == 1 then total = total + tile end end
 sums[mask] = total; byTotal[total] = byTotal[total] or {}
 byTotal[total][#byTotal[total] + 1] = mask
end
local probability = {[0] = 1}
for board = 1, rules.full do
 local expected = 0
 for total = 2, 12 do
  local best = 0
  for _, removal in ipairs(byTotal[total] or {}) do
   if bitlib.band(board, removal) == removal then best = math.max(best, probability[board - removal]) end
  end
  local sourceChoice = rules.best(board, total)
  if sourceChoice then
   check(sums[sourceChoice] == total and bitlib.band(board, sourceChoice) == sourceChoice, 'Production choice is legal')
   close(probability[board - sourceChoice], best, 'Production choice maximizes clearance')
  else
   check(#rules.moves(board, total) == 0, 'No production choice only when no legal move exists')
  end
  expected = expected + (6 - math.abs(total - 7)) * best / 36
 end
 probability[board] = expected
 close(expected, rules.chance(board), 'Production clear probability agrees for every board')
end
local optimal = probability[rules.full]
close(optimal, 0.071431622305606, 'Optimal probability regression')
local grossMultiplier = .98 / optimal
local pinebox = {}
for _, stake in ipairs(rules.bets) do
 local ideal = stake * grossMultiplier
 local low = math.floor(ideal)
 local entry = {stake = stake, currentGross = stake * rules.prize, proposedGross = low,
  idealGross = ideal, optimalRtp = optimal * low / stake,
  optionalBonusChance = ideal - low}
 check(entry.optimalRtp <= .98, 'Whole-credit proposal exceeds optimal-play 98%')
 check(optimal * (low + 1) / stake > .98, 'Whole-credit proposal unnecessarily low')
 pinebox[#pinebox + 1] = entry
end

print('PineSlots: all ' .. outcomeCount .. ' equally likely stop triples, unchanged strips and paylines')
print(('  Current single-line gross return: %d/%d = %.9f%%; house edge %.9f%%'):format(
 current[1].paid, outcomeCount, 100 * current[1].paid / outcomeCount, 100 * (1 - current[1].paid / outcomeCount)))
print('  Proposed triples: DIAMOND=300 SEVEN=100 BAR=30 BELL=15 PLUM=10 CHERRY=10; left cherries=1/3')
print(('  Proposed gross return: 4014/4096 = %.9f%%; house edge %.9f%%'):format(100 * 4014 / 4096, 100 * (1 - 4014 / 4096)))
print('  Exact 98% is not representable by deterministic whole-credit payouts on these strips')
for bet = 1, reels.maxBet do
 print(('  Bet %d: reserve maximum gross %d (current %d), unchanged hit rate %.6f%%'):format(
  bet, proposed[bet].maximum, current[bet].maximum, 100 * current[bet].hits / outcomeCount))
end
print(('PineBox: optimal clear probability %.15f (%.12f%%), current 13x RTP %.12f%%'):format(optimal, optimal * 100, optimal * rules.prize * 100))
print(('  Exact optimal-play 98%% benchmark requires %.12fx GROSS return (stake already debited)'):format(grossMultiplier))
print('  Conservative deterministic whole-credit proposal (at least 2% edge under optimal play):')
for _, entry in ipairs(pinebox) do
 print(('  Stake %d: clear pays %d total; ideal %.12f; optimal RTP %.9f%%, edge %.9f%%'):format(
  entry.stake, entry.proposedGross, entry.idealGross, 100 * entry.optimalRtp, 100 * (1 - entry.optimalRtp)))
end
print('  Optional exact expected benchmark requires fractional credits or a disclosed host-side randomized clear bonus')
print('  For a randomized bonus: pay floor(ideal) plus 1 with probability fractional_part(ideal), ONLY on clearance')
print('  Less-than-optimal decisions reduce clear chance and RTP; no fixed 2% edge is promised for skill play')
print('  Multiplayer remains a player-funded pot; these solo house payouts do not imply a match fee')
print(('PASS payout analysis (%d assertions); proposals only, no production mutation'):format(checkCount))
return {slots = {current = current, proposed = proposed, outcomes = outcomeCount, categories = categories},
 pinebox = {optimalClear = optimal, grossMultiplier = grossMultiplier, payouts = pinebox}, assertions = checkCount}
