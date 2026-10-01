-- Renders the stage and a full throw, frame by frame, for review.
local render=require('pinebox.render')
local dice=require('pinebox.dice')
local dump=require('casino.tests.screen')
local seed=4242; local function rng() seed=(seed*1103515245+12345)%2147483648; return seed/2147483648 end
local throw=dice.throw(rng,{3,4})
for _,size in ipairs({{51,19},{70,26},{100,40}}) do
 local t=window.create(term.current(),1,1,size[1],size[2],false)
 local r=render.new(t)
 local tiles={}; for n=1,9 do tiles[n]={down=(n==2 or n==5) and 1 or 0,lit=(n==3 or n==4),lift=(n==3 or n==4) and .25 or 0} end
 local frames=0; local start=os.epoch('utc')
 for k=0,math.floor((throw.duration+1.6)*10) do
  local tt=k/10; local d={}
  for i=1,2 do local pos,m=dice.pose(throw,i,tt); d[i]={pos=pos,matrix=m} end
  local cam=render.follow({d[1].pos,d[2].pos},tt,throw.duration,1.4)
  r:draw({camera=cam,tiles=tiles,players={list={43,false,false},current=2},dice=d,credits=99,bet=5,info='ROLL 3 + 4 = 7',message='TAKE 3 + 4?',options={{label='< OTHER'},{label='TAKE'},{label='OTHER >'}},lamps=function(i) return (i+k)%3==0 end})
  frames=frames+1
  if size[1]==100 then dump(t,('box-throw-%02d'):format(k)) end
 end
 local fps=frames/math.max(.001,(os.epoch('utc')-start)/1000)
 print(('Rendered %dx%d at %.1f fps'):format(size[1],size[2],fps)); assert(fps>=10,'Render under 10 fps')
 dump(t,'box-'..size[1]..'-rest')
end
print('PASS rendered stage')
-- Frames from the real game loop: the snap zoom, choosing tiles, and after the take.
local game=require('pinebox.game')
local t=window.create(term.current(),1,1,100,40,false); local now=0; local s2=7
local values={3,4}
local opts={target=t,wallet=require('casino.wallet').exhibition('PINE SHUT THE BOX'),clock=function() return now end,sound={play=function() end,tick=function() end},
 random=function(lo,hi) if lo==1 and hi==6 then return table.remove(values,1) end s2=(s2*1103515245+12345)%2147483648; return lo+s2%(hi-lo+1) end}
local co=coroutine.create(function() game.run(opts) end)
local oldPull,oldTimer=os.pullEvent,os.startTimer
os.pullEvent=function() return coroutine.yield() end; os.startTimer=function() return 1 end
local function send(...) assert(coroutine.resume(co,...)) end
local function run(s) for _=1,math.floor(s*20) do now=now+.05; send('timer',1) end end
send(); run(1); send('key',keys.two); run(1); send('key',keys.one); run(1); send('key',keys.two); run(1); send('key',keys.two)
local landed=0
for _=1,200 do run(.05); landed=landed+1; if landed==50 then dump(t,'box-game-zoom') end; local text=t.getLine(39); if text:find('TAKE') then break end end
dump(t,'box-game-choose')
send('key',keys.two); run(.35); dump(t,'box-game-falling'); run(1); dump(t,'box-game-after')
os.pullEvent,os.startTimer=oldPull,oldTimer
