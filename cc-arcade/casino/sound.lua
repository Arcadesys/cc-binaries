-- Speaker notes scheduled ahead of time and played from the frame loop, so sound never
-- sleeps (sleeping would swallow button and redstone events).
return function()
 local speaker=peripheral.find and peripheral.find('speaker')
 local queue={}; local api={}
 function api:play(at,instrument,volume,pitch) queue[#queue+1]={at=at,i=instrument,v=volume,p=pitch} end
 function api:tick(now)
  for n=#queue,1,-1 do
   local q=queue[n]
   if q.at<=now then table.remove(queue,n); if speaker then pcall(speaker.playNote,q.i,q.v,q.p) end end
  end
 end
 return api
end
