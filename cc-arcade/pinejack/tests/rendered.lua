-- Renders the table in typical states at two sizes and dumps each screen for review.
local render=require('pinejack.render')
local dump=require('casino.tests.screen')
local function card(id,rank,suit,x,z,n,down)
 return {id=id,card={rank=rank,suit=suit},x=x+(n-1)*.25,y=.01*n,z=z+(n-1)*.75,rx=down and math.pi or 0}
end
for _,size in ipairs({{51,19},{100,40}}) do
 local t=window.create(term.current(),1,1,size[1],size[2],false)
 local r=render.new(t)
 local actors={card('p1','A','S',-1.9,-.75,1),card('p2','10','H',-1.9,-.75,2),card('d1','K','D',2.6,-.9,1),card('d2','7','C',2.6,-.9,2,true),{id='bet',chips=20,x=-3.3,y=0,z=0}}
 r:draw({actors=actors,credits=80,bet=20,dealer='DEALER  K\4 ??',player='YOU  A\6 10\3  BLACKJACK!',message='BLACKJACK PAYS 3 TO 2',highlight=true,options={{label='HIT'},{label='STAND'},{label='DOUBLE'}}})
 dump(t,'jack-'..size[1]..'-deal')
 local split={card('a1','8','S',-1.9,-3.55,1),card('a2','3','D',-1.9,-3.55,2),card('a3','Q','H',-1.9,-3.55,3),card('b1','8','H',-1.9,2.05,1),card('b2','9','C',-1.9,2.05,2),
  card('d1','6','D',2.6,-.9,1),card('d2','J','S',2.6,-.9,2),card('d3','2','H',2.6,-.9,3),card('d4','5','C',2.6,-.9,4),
  {id='bet1',chips=20,x=-3.3,y=0,z=-2.8},{id='bet2',chips=20,x=-3.3,y=0,z=2.8}}
 r:draw({actors=split,credits=40,bet=20,dealer='DEALER  6\4 J\6 2\3 5\5  23 BUST',player='1 8\6 3\4 Q\3 21  |  2 8\3 9\5 17',message='WIN 80',options={{label='BET 20'},{label='DEAL'},{label='CASH OUT'}}})
 dump(t,'jack-'..size[1]..'-split')
 local start=os.epoch('utc'); for n=1,30 do r:draw({actors=split}) end
 local fps=30/math.max(.001,(os.epoch('utc')-start)/1000)
 print(('Rendered %dx%d at %.1f fps'):format(size[1],size[2],fps)); assert(fps>=10,'Render under 10 fps')
end
print('PASS rendered table')
-- A frame from the real game loop: split eights mid-hand.
local game=require('pinejack.game')
local t=window.create(term.current(),1,1,100,40,false); local now=0
local deck={'8','6','8','10','3','K'}
local opts={target=t,wallet=require('casino.wallet').exhibition('PINE JACK'),clock=function() return now end,sound={play=function() end,tick=function() end},
 newShoe=function() local s={cards={},next=1}; for i,r in ipairs(deck) do s.cards[i]={rank=r,suit=({'S','D','H','C'})[i%4+1]} end; for i=#deck+1,312 do s.cards[i]={rank='2',suit='C'} end; return s end}
local co=coroutine.create(function() game.run(opts) end)
local oldPull,oldTimer=os.pullEvent,os.startTimer
os.pullEvent=function() return coroutine.yield() end; os.startTimer=function() return 1 end
local function send(...) assert(coroutine.resume(co,...)) end
local function run(s) for _=1,s*20 do now=now+.05; send('timer',1) end end
send(); run(1); send('key',keys.two); run(4); send('key',keys.three); run(.2); send('key',keys.two); run(3)
dump(t,'jack-game-split')
os.pullEvent,os.startTimer=oldPull,oldTimer
