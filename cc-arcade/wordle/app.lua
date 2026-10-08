-- Daily Wordle: guess the day's five-letter Minecraft word in six tries. Every computer
-- on the server gets the same word on the same (UTC) day.
-- Type on the keyboard, touch the on-screen keys, or use the cabinet buttons: LEFT and
-- RIGHT move along the on-screen keys and CENTER presses the one lit up.
local rules=require('wordle.rules')
local render=require('wordle.render')
local M={}
local C=render.C
M.palette=render.palette
-- On-screen keys in reading order; the buttons walk this list.
local ROWS={'QWERTYUIOP','ASDFGHJKL','>ZXCVBNM<'}
local KEYS={}
for r,row in ipairs(ROWS) do for c in row:gmatch('.') do KEYS[#KEYS+1]={row=r,value=c=='>' and 'ENTER' or c=='<' and 'DEL' or c} end end
M.keys=KEYS
local PRAISE={'GENIUS','MAGNIFICENT','IMPRESSIVE','SPLENDID','GREAT','PHEW'}
-- {seconds after the cue, instrument, volume, pitch}
local CUES={
 type={{0,'hat',.4,16}},
 erase={{0,'hat',.4,10}},
 move={{0,'hat',.3,20}},
 bad={{0,'bass',1,6},{.1,'bass',1,4}},
 hit={{0,'bell',.8,18}},
 near={{0,'pling',.8,14}},
 miss={{0,'snare',.4,8}},
 win={{0,'chime',1,12},{.15,'chime',1,16},{.3,'chime',1,19},{.45,'chime',1,24}},
 lose={{0,'didgeridoo',1,8},{.3,'didgeridoo',1,4}},
}
M.cues=CUES
-- Animation timings, in seconds.
local FLIP=.25    -- between one tile starting to turn and the next
local TURN=.35    -- one tile turning over
local SHAKE=.5    -- a refused row shaking
local POP=.12     -- a typed tile's outline flashing
local HOP=.12     -- between solved tiles hopping
local HOPTIME=.36 -- one hop
-- Sizes, largest first: title rows tt, tiles tw x th with rg rows between them, keys
-- kw x kh with kg rows between the keyboard rows. A three-row title is the blocky one.
local SIZES={{3,7,3,1,5,3,1},{3,7,3,1,5,3,0},{3,7,3,1,5,1,0},{3,5,3,1,5,1,0},{1,5,3,1,5,1,0},{1,5,3,1,3,1,0},{1,3,1,1,3,1,0},{1,3,1,0,3,1,0}}
function M.layout(w,h)
 for _,s in ipairs(SIZES) do
  local tt,tw,th,rg,kw,kh,kg=table.unpack(s)
  local gridH=rules.TRIES*th+(rules.TRIES-1)*rg
  local kbH=3*kh+2*kg
  local gridW=rules.LENGTH*tw+rules.LENGTH-1
  local kbW=10*kw+9
  local used=tt+1+gridH+1+kbH+1+1
  if used<=h and gridW<=w and kbW<=w then
   local L={tt=tt,tw=tw,th=th,rg=rg,kw=kw,kh=kh,kg=kg,sw=(3*kw+1)/2}
   -- Centre the board and keyboard in the rows between the title and the message line.
   local spare=h-used
   L.gridY=tt+2+math.floor(spare/3)
   L.gridX=math.floor((w-gridW)/2)+1
   L.kbY=L.gridY+gridH+1+math.floor(spare/3)
   L.kbX=math.floor((w-kbW)/2)+1
   -- Where each on-screen key sits, in characters.
   L.keys={}
   local x,y,row=L.kbX,L.kbY,1
   for n,k in ipairs(KEYS) do
    if k.row~=row then row=k.row; y=y+kh+kg; x=L.kbX+(row==2 and math.floor((kw+1)/2) or 0) end
    local wd=(k.value=='ENTER' or k.value=='DEL') and L.sw or kw
    L.keys[n]={x=x,y=y,w=wd,value=k.value}
    x=x+wd+1
   end
   return L
  end
 end
end
local function centre(t,y,text,fg,bg)
 local w=t.getSize()
 t.setBackgroundColor(bg or C.bg); t.setCursorPos(1,y); t.clearLine()
 t.setTextColor(fg or C.text); t.setCursorPos(math.max(1,math.floor((w-#text)/2)+1),y); t.write(text)
end
-- The bottom row: three button slots, as wide as the cabinet buttons are apart.
local function slots(w)
 local a=math.floor(w/3)
 return {{x1=1,x2=a},{x1=a+1,x2=w-a},{x1=w-a+1,x2=w}}
end
M.slots=slots
-- opts: target, args, clock() (seconds, for animation), now() (UTC milliseconds, for the
-- day's word), button(event,p1), sound (casino.sound's play(at,instrument,volume,pitch) and
-- tick(now)), random(a,b) for the confetti
function M.run(opts)
 local t=opts.target
 local args=opts.args or {}
 local clock=opts.clock or function() return os.epoch('utc')/1000 end
 local now=opts.now or function() return os.epoch('utc') end
 local button=opts.button or require('input').getButton
 local sound=opts.sound or require('casino.sound')()
 local random=opts.random or math.random
 local monitorName
 for i,a in ipairs(args) do if a=='--monitor' then monitorName=args[i+1] end end
 if not monitorName and peripheral.getName then local ok,name=pcall(peripheral.getName,t); if ok then monitorName=name end end
 local view=render.new(t)
 local function cue(name)
  local at=clock()
  for _,n in ipairs(CUES[name]) do sound:play(at+n[1],n[2],n[3],n[4]) end
  sound:tick(at)
 end
 local puzzle,rows,typed,cursor,done,flash,flashUntil,shakeUntil,reveal,popAt,wonAt,confetti
 local function newGame()
  puzzle=rules.daily(now())
  rows={}; typed=''; done=nil; flash=nil; shakeUntil=0; reveal=nil; popAt=-1; wonAt=nil; confetti={}
  cursor=cursor or 1
 end
 newGame()
 local function say(text,secs) flash=text; flashUntil=clock()+(secs or 2) end
 local function message(w)
  if flash and clock()<flashUntil then return flash,C.text end
  if reveal then return '',C.text end
  if done then
   local left=86400000-now()%86400000
   local nextIn=('NEXT WORD IN %dH %02dM'):format(math.floor(left/3600000),math.floor(left%3600000/60000))
   local text=done=='win' and ('%s! SOLVED %d/%d'):format(PRAISE[#rows],#rows,rules.TRIES) or 'THE WORD WAS '..puzzle.word
   if #text+#nextIn+3<=w then text=text..' - '..nextIn end
   return text,done=='win' and C.grass or C.near
  end
  return ('GUESS %d OF %d'):format(#rows+1,rules.TRIES),C.key
 end
 -- How far tile i of row r has turned over, 0..1.
 local function flip(r,i)
  if not reveal or r<#rows then return 1 end
  return math.max(0,math.min(1,(clock()-reveal.start-(i-1)*FLIP)/TURN))
 end
 -- How many pixels tile i of the solved row is lifted.
 local function bounce(r,i)
  if not wonAt or r~=#rows then return 0 end
  local p=(clock()-wonAt-(i-1)*HOP)/HOPTIME
  if p<=0 or p>=1 then return 0 end
  return math.floor(3*math.sin(math.pi*p)+.5)
 end
 local function animating()
  local at=clock()
  return reveal or (flash and at<flashUntil+.1) or at<shakeUntil or at<popAt+POP or (wonAt and at<wonAt+HOP*rules.LENGTH+HOPTIME) or #confetti>0
 end
 local L
 local function draw()
  local w,h=t.getSize()
  L=M.layout(w,h)
  if not L then
   t.setBackgroundColor(C.bg); t.clear(); centre(t,1,'SCREEN TOO SMALL',C.bad); return
  end
  local at=clock()
  local seen=rules.keyboard(reveal and {table.unpack(rows,1,#rows-1)} or rows)
  local keys={}
  for n,k in ipairs(L.keys) do
   keys[n]={x=k.x,y=k.y,w=k.w,value=k.value,mark=seen[k.value],cursor=n==cursor and not done}
  end
  local shake=0
  if at<shakeUntil then shake=math.floor(2*math.sin((shakeUntil-at)*50)+.5) end
  view:draw({layout=L,puzzle=puzzle,rows=rows,typed=typed,done=done,tries=rules.TRIES,length=rules.LENGTH,
   keys=keys,flip=flip,bounce=bounce,shake=shake,pop=at<popAt+POP and #typed or nil,confetti=confetti})
  local text,fg=message(w)
  centre(t,h-1,text,fg)
  local bar=done and {'QUIT','NEXT PLAYER','QUIT'} or {'< KEY','PRESS '..KEYS[cursor].value,'KEY >'}
  for i,s in ipairs(slots(w)) do
   local wd=s.x2-s.x1+1
   t.setBackgroundColor(i==2 and C.miss or C.stone); t.setTextColor(C.text)
   t.setCursorPos(s.x1,h); t.write((' '):rep(wd))
   t.setCursorPos(s.x1+math.floor((wd-#bar[i])/2),h); t.write(bar[i])
  end
 end
 local function hitWhat(x,y)
  if not L then return end
  local w,h=t.getSize()
  if y==h then for i,s in ipairs(slots(w)) do if x>=s.x1 and x<=s.x2 then return ({'LEFT','CENTER','RIGHT'})[i] end end end
  for _,k in ipairs(L.keys) do if x>=k.x and x<k.x+k.w and y>=k.y and y<k.y+L.kh then return k.value end end
 end
 local function refuse(text) say(text); shakeUntil=clock()+SHAKE; cue('bad') end
 local function submit()
  if #typed<rules.LENGTH then return refuse('NOT ENOUGH LETTERS') end
  if not rules.valid(typed) then return refuse('NOT IN WORD LIST') end
  rows[#rows+1]={word=typed,marks=rules.score(typed,puzzle.word)}
  typed=''
  reveal={start=clock(),cued=0}
 end
 local function finish()
  local last=rows[#rows]
  if last.word==puzzle.word then
   done='win'; wonAt=clock(); cue('win')
   local w,h=t.getSize()
   local shades={C.hit,C.hitLight,C.near,C.nearLight,C.grass,C.cursorLight,C.text}
   for _=1,math.floor(w*1.2) do
    confetti[#confetti+1]={x=random(1,w*2),y=-random(0,h*2),vx=(random()-.5)*12,vy=random()*20,c=shades[random(1,#shades)]}
   end
  elseif #rows>=rules.TRIES then done='lose'; cue('lose') end
 end
 -- One action: a letter, ENTER, DEL, or a cabinet button. Returns true to quit.
 local function act(v)
  if reveal then return end
  if done then
   if v=='CENTER' then newGame()
   elseif v=='LEFT' or v=='RIGHT' then return true end
   return
  end
  if v=='LEFT' then cursor=(cursor-2)%#KEYS+1; cue('move'); return end
  if v=='RIGHT' then cursor=cursor%#KEYS+1; cue('move'); return end
  if v=='CENTER' then v=KEYS[cursor].value end
  if v=='ENTER' then submit()
  elseif v=='DEL' then if #typed>0 then typed=typed:sub(1,-2); cue('erase') end
  elseif #typed<rules.LENGTH then typed=typed..v; popAt=clock(); cue('type') end
 end
 local timer=os.startTimer(.05)
 local last=clock()
 local lastSecond=-1
 draw()
 while true do
  local e,p1,p2,p3=os.pullEventRaw()
  if e=='terminate' then return end
  local v
  if e=='timer' and p1==timer then
   local at=clock()
   local dt=math.min(.2,at-last); last=at
   local changed=false
   if reveal then
    -- Each tile sounds its mark as it shows its new face, halfway over.
    while reveal.cued<rules.LENGTH and at>=reveal.start+reveal.cued*FLIP+TURN/2 do
     reveal.cued=reveal.cued+1; cue(rows[#rows].marks[reveal.cued])
    end
    if at>=reveal.start+(rules.LENGTH-1)*FLIP+TURN then reveal=nil; finish(); changed=true end
   end
   if #confetti>0 then
    local _,h=t.getSize()
    for n=#confetti,1,-1 do
     local p=confetti[n]
     p.vy=p.vy+40*dt; p.x=p.x+p.vx*dt; p.y=p.y+p.vy*dt
     if p.y>h*3 then table.remove(confetti,n) end
    end
   end
   sound:tick(at)
   -- Redraw while something moves, and once a second for the countdown and messages.
   local second=math.floor(at)
   if changed or animating() or second~=lastSecond then draw(); lastSecond=second end
   timer=os.startTimer(.05)
  elseif e=='char' and p1:match('^%a$') then v=p1:upper()
  elseif e=='char' then v=button(e,p1)
  elseif e=='key' and p1==keys.enter then v='ENTER'
  elseif e=='key' and p1==keys.backspace then v='DEL'
  elseif e=='key' then
   -- Letter keys arrive again as char events; anything else may be a cabinet button.
   local name=keys.getName(p1) or ''
   if not name:match('^%a$') then v=button(e,p1) end
  elseif e=='redstone' then v=button(e,p1)
  elseif e=='mouse_click' and not monitorName then v=hitWhat(p2,p3)
  elseif e=='monitor_touch' and p1==monitorName then v=hitWhat(p2,p3)
  elseif e=='term_resize' or e=='monitor_resize' then draw() end
  if v then
   if act(v) then return end
   draw()
  end
 end
end
return M
