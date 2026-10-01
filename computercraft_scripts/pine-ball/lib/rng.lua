-- Deterministic PRNG (mulberry32), bit-for-bit with furball-simulator src/sim/rng.ts.
-- All arithmetic stays in unsigned 32-bit space; bit32 is available in CC:Tweaked and CraftOS-PC.
local rng = {}
local band, bxor, bor, rshift = bit32.band, bit32.bxor, bit32.bor, bit32.rshift
local TWO32 = 4294967296

local function u32(n) return n % TWO32 end

-- Math.imul for unsigned operands: split b so every partial product stays exact in a double.
local function imul(a, b)
  local hi, lo = rshift(b, 16), band(b, 0xffff)
  return u32(u32(a * hi) * 65536 + a * lo)
end
rng.imul = imul

function rng.create(seed)
  local a = u32(math.floor(tonumber(seed) or 0))
  return function()
    a = u32(a + 0x6d2b79f5)
    local t = a
    t = imul(bxor(t, rshift(t, 15)), bor(t, 1))
    t = bxor(t, u32(t + imul(bxor(t, rshift(t, 7)), bor(t, 61))))
    return bxor(t, rshift(t, 14)) / TWO32
  end
end

function rng.pick(next, items)
  local item = items[math.floor(next() * #items) + 1]
  if item == nil then error("pick() from empty list") end
  return item
end

-- Weight tables are ordered arrays of {key, weight} so iteration order matches the TS object.
function rng.weighted(next, entries)
  local total = 0
  for _, e in ipairs(entries) do total = total + math.max(0, e[2]) end
  local roll = next() * total
  for _, e in ipairs(entries) do
    roll = roll - math.max(0, e[2])
    if roll < 0 then return e[1] end
  end
  local last = entries[#entries]
  if not last then error("weighted() from empty table") end
  return last[1]
end

return rng
