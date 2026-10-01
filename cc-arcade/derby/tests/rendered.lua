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
os.pullEvent,os.startTimer,ui.card=originalPull,originalTimer,originalCard
print('PASS actual rendered race, station, confirmation and input scenarios')
