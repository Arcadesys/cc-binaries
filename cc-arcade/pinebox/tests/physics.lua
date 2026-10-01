local dice=require('pinebox.dice')
local n,slow,maxT,sum=200,0,0,0
local landedCount={}
for s=1,n do
 local seed=s*7919; local function rng() seed=(seed*1103515245+12345)%2147483648; return seed/2147483648 end
 local want={(s%6)+1,((s*5)%6)+1}
 local th=dice.throw(rng,want)
 maxT=math.max(maxT,th.duration); sum=sum+th.duration
 if th.duration>=dice.maxTime then slow=slow+1 end
 for i=1,2 do
  local pos,m=dice.pose(th,i,th.duration+1)
  assert(pos[1]>dice.tray.xmin and pos[1]<dice.tray.xmax and pos[3]>dice.tray.zmin and pos[3]<dice.tray.zmax,'Die inside tray')
  assert(math.abs(pos[2]-dice.half)<1e-6,'Die resting on floor')
  -- The face shown on top is the drawn value.
  local top,val=-2
  for value,normal in pairs(dice.faces) do local up=dice.apply(m,normal)[2]; if up>top then top,val=up,value end end
  assert(val==want[i] and top>.9999,'Shows drawn value flat: '..tostring(val)..' '..top)
  landedCount[th.landed[i]]=(landedCount[th.landed[i]] or 0)+1
 end
end
print(('throws %d, avg %.2fs, max %.2fs, unsettled %d'):format(n,sum/n,maxT,slow))
for k=1,6 do io.write(k,':',landedCount[k] or 0,' ') end print()
assert(slow<=n*.02,'Dice settle')
print('PASS physics')
