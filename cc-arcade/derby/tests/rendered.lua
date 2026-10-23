local render=require('derby.render')
local sim=require('derby.sim')
local ui=require('derby.ui')
local odds=require('derby.odds')
local function dump(t,name)
 local w,h=t.getSize(); local pal={}; local lines={}; local hex='0123456789abcdef'
 for i=0,15 do pal[hex:sub(i+1,i+1)]=colors.packRGB(t.getPaletteColor(2^i)) end
 for y=1,h do local text,fg,bg=t.getLine(y); lines[y]={text={text:byte(1,-1)},fg=fg,bg=bg} end
 local f=fs.open('/results/'..name..'.screen.json','w'); f.write(textutils.serializeJSON({w=w,h=h,palette=pal,lines=lines})); f.close()
end
local function win(w,h) return window.create(term.current(),1,1,w,h,false) end
for _,size in ipairs({{51,19},{100,40}}) do
 local t=win(size[1],size[2]); local renderer=render.new(t); local s=sim.new(743)
 for _=1,200 do sim.step(s) end
 for _,camera in ipairs({'overview','follow','finish'}) do
  renderer:draw({id='race-1',phase='RUNNING',tick=s.tick,positions=sim.positions(s),order=s.order},camera,true)
  dump(t,'race-'..size[1]..'-'..camera)
 end
 local frames=0; local samples={}; local start=os.epoch('utc')
 while #s.order<3 do
  sim.step(s); local before=os.epoch('utc')
  renderer:draw({id='race-1',phase='RUNNING',tick=s.tick,positions=sim.positions(s),order=s.order},'follow',true)
  samples[#samples+1]=os.epoch('utc')-before; frames=frames+1
  if frames%20==0 then os.queueEvent('render_yield'); os.pullEvent('render_yield') end
 end
 table.sort(samples)
 local fps=frames/math.max(.001,(os.epoch('utc')-start)/1000)
 print('Rendered '..size[1]..'x'..size[2]..': '..frames..' frames; '..string.format('%.1f',fps)..' fps; p95 '..samples[math.ceil(#samples*.95)]..'ms')
 assert(fps>=10,'Render throughput under 10 fps')
 renderer:draw({id='race-1',phase='RESULT',tick=s.tick,positions=sim.positions(s),order=s.order},'finish',true)
 dump(t,'race-'..size[1]..'-result')
end
-- Drive the actual station event loop: keyboard selection, confirmation, touch, and card removal.
local originalPull,originalTimer,originalCard=os.pullEvent,os.startTimer,ui.card
os.pullEvent=function() return coroutine.yield() end
os.startTimer=function() return 77 end
local activeCard={account='house-1',path='disk',diskID=1}
ui.card=function() return activeCard end
for _,width in ipairs({51,100}) do
 local t=win(width,width==51 and 19 or 40); local calls={}
 local client={}
 function client:read(q)
  if q.op=='snapshot' then return {ok=true,id='race-1',phase='OPEN',seconds=45,payouts=odds.payouts} end
  return {ok=true,balance=20}
 end
 function client:mutate(q) calls[#calls+1]=q; return {ok=true} end
 function client:retry() return {ok=true} end
 local co=coroutine.create(function() require('derby.station').run(client,t) end)
 local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
 send(); send('timer',77); dump(t,'station-'..width)
 for _=1,4 do send('key',keys.tab) end
 send('key',keys.enter); dump(t,'confirm-'..width)
 activeCard=nil; send('key',keys.enter); assert(#calls==0,'Card removal must cancel unsent bet')
 activeCard={account='house-1',path='disk',diskID=1}; send('timer',77)
 send('mouse_click',1,10,8); send('mouse_click',1,10,16); send('mouse_click',1,10,14)
 assert(#calls==1 and calls[1].horse==2,'Touch chooses horse and confirms one ticket')
 send('key',keys.q); assert(coroutine.status(co)=='dead')
end
-- Station feedback: short balance, a review overtaken by the lock, and the ticket's result.
do
 local t=win(51,19); local calls={}; local balance=3
 local snap={ok=true,id='race-1',phase='OPEN',seconds=45,payouts=odds.payouts}
 local client={}
 function client:read(q) if q.op=='snapshot' then return snap end return {ok=true,balance=balance} end
 function client:mutate(q) calls[#calls+1]=q; return {ok=true} end
 function client:retry() return {ok=true} end
 local co=coroutine.create(function() require('derby.station').run(client,t) end)
 local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
 local function text(y) return (t.getLine(y)) end
 send(); send('timer',77)
 assert(text(3):find('BETTING OPEN | 45s',1,true),'Friendly phase: '..text(3))
 for _=1,4 do send('key',keys.tab) end; send('key',keys.enter)
 assert(text(19):find('Not enough credits: 3',1,true) and not text(4):find('CONFIRM',1,true),'Short balance stops before review')
 balance=20; send('timer',77); send('key',keys.enter)
 assert(text(4):find('CONFIRM',1,true) and text(12):find('closes in 45s',1,true),'Review shows the countdown')
 snap={ok=true,id='race-1',phase='LOCKED',seconds=5,payouts=odds.payouts}; send('timer',77)
 assert(not text(4):find('CONFIRM',1,true) and text(19):find('Betting closed before you confirmed',1,true),'Lock cancels a stale review')
 send('key',keys.enter); assert(#calls==0,'No bet sent after the lock')
 snap={ok=true,id='race-1',phase='RUNNING',payouts=odds.payouts,ticket={horse=2,stake=10,returns=34}}; send('timer',77)
 assert(text(13):find('Your ticket: LEDGER LIZARD, 10 to return 34',1,true),'Ticket shown: '..text(13))
 snap.phase='RESULT'; snap.ticket.paid=34; send('timer',77)
 assert(text(13):find('YOU WON 34 CREDITS',1,true),'Win shown')
 snap.ticket.paid=0; send('timer',77); assert(text(13):find('No win on LEDGER LIZARD',1,true),'Loss shown')
 send('key',keys.q); assert(coroutine.status(co)=='dead')
end
-- Display: an offline house reads as offline (not paused); a touch changes the camera.
do
 local app=require('derby.app'); local t=win(51,19)
 settings.set('derby.camera','follow')
 local client={read=function() return {ok=false,offline=true,error='House offline'} end}
 local co=coroutine.create(function() app.display(client,t,false) end)
 local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
 send(); send('timer',77)
 assert((t.getLine(2)):find('HOUSE OFFLINE - RECONNECTING',1,true),'Offline label: '..t.getLine(2))
 send('monitor_touch','top',5,5); assert(settings.get('derby.camera')=='overview','Touch cycles camera')
 send('key',keys.x); assert(settings.get('derby.camera')=='overview','Other keys leave it')
 send('key',keys.q); assert(coroutine.status(co)=='dead','Q exits')
 local words,screen=app.options({'--monitor','left','display'})
 assert(words[1]=='display' and #words==1 and screen.monitor=='left','Monitor option split from command')
 words,screen=app.options({'--terminal'}); assert(#words==0 and screen.terminal,'Terminal option')
 -- Pine Arcade and get --startup launch a bare `race`; unconfigured, that is the exhibition.
 assert(not fs.exists('/house-config.json'),'Test computer is not a house member')
 local display=app.display; local seen
 app.display=function(client,target,demo) seen={client=client,demo=demo} end
 app.run({}); app.display=display
 assert(seen and seen.demo and seen.client==nil,'Bare race shows the exhibition')
end
os.pullEvent,os.startTimer,ui.card=originalPull,originalTimer,originalCard
print('PASS actual rendered race, station, confirmation and input scenarios')
