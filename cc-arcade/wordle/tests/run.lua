-- Daily Wordle checks: the dated word list, scoring, the guess list, the layout at every
-- supported size, and a game played through the real event loop with a fake clock.
-- python3 derby/tools/run.py wordle.tests.run
local rules=require('wordle.rules')
local app=require('wordle.app')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local DAY=86400000
-- Ninety answers on consecutive dates, five capital letters each, no repeats, all guessable.
local words=rules.words
eq(#words,90,'Answers')
eq(words[1][1],'2026-10-08','First date')
local seen={}
for i,e in ipairs(words) do
 eq(rules.dayOf(e[1]),rules.dayOf(words[1][1])+i-1,'Date '..i..' follows on')
 check(e[2]:match('^%u%u%u%u%u$'),e[2]..' is five capitals')
 check(not seen[e[2]],e[2]..' repeated'); seen[e[2]]=true
 check(rules.valid(e[2]),e[2]..' is a valid guess')
end
-- The day's word, by UTC date, wrapping past the end of the list.
local function at(date,hours) return rules.dayOf(date)*DAY+(hours or 0)*3600000 end
eq(rules.daily(at('2026-10-08')).word,'STONE','First day'); eq(rules.daily(at('2026-10-08',23.9)).number,1,'Same day until midnight UTC')
eq(rules.daily(at('2026-10-09')).word,'BLAZE','Second day')
eq(rules.daily(at('2026-10-31')).word,'WITCH','Halloween')
eq(rules.daily(at('2026-12-25')).word,'CHEST','Christmas')
eq(rules.daily(at('2027-01-01')).word,'SPAWN',"New Year's Day")
eq(rules.daily(at('2027-01-05')).word,'STEAK','Last day')
local wrap=rules.daily(at('2027-01-06'))
eq(wrap.word,'STONE','Wraps around'); eq(wrap.number,91,'Puzzle numbers keep counting'); eq(wrap.date,'2027-01-06','Date shown')
eq(rules.dayOf('1970-01-01'),0,'Epoch'); eq(rules.dayOf('2000-03-01'),11017,'Leap century')
-- Scoring, with repeated letters.
local function marks(g,a) return table.concat(rules.score(g,a),' ') end
eq(marks('STONE','STONE'),'hit hit hit hit hit','All right')
eq(marks('CRANE','STONE'),'miss miss miss hit hit','Two in place')
eq(marks('NOTES','STONE'),'near near near near near','All elsewhere')
eq(marks('LLAMA','PLANK'),'miss hit hit miss miss','Extra L is a miss')
eq(marks('EERIE','ELDER'),'hit near near miss miss','Only as many Es as the answer has')
eq(marks('SPEED','SHEEP'),'hit near hit hit miss','Hits counted before nears')
-- The keyboard keeps the best mark per letter.
local best=rules.keyboard({{word='CRANE',marks=rules.score('CRANE','STONE')},{word='NOTES',marks=rules.score('NOTES','STONE')}})
eq(best.N,'hit','N stays a hit'); eq(best.C,'miss','C missed'); eq(best.S,'near','S is near')
-- Guesses.
check(rules.valid('CRANE') and rules.valid('MINES') and rules.valid('PIXEL'),'Common words')
check(not rules.valid('ZZZZZ') and not rules.valid('QWERT'),'Nonsense refused')
-- Every supported size fits the board, the keys and the bar.
for _,s in ipairs({{39,19},{51,19},{57,24},{100,40},{164,81}}) do
 local L=app.layout(s[1],s[2])
 check(L,('Layout at %dx%d'):format(s[1],s[2]))
 check(L.kbX+10*L.kw+9-1<=s[1] and L.gridX>=1,'Keyboard fits '..s[1])
 check(L.kbY+3*L.kh+2*L.kg-1<=s[2]-2,'Keyboard clears the message line at '..s[2])
end
check(not app.layout(30,12),'Too small is refused')
eq(app.layout(100,40).tw,7,'Big tiles on a big screen')
-- A game through the event loop: 2026-10-08, so the word is STONE.
local t=window.create(term.current(),1,1,51,19,false)
local clock=0; local ms=at('2026-10-08',20)
local heard={}
local sound={play=function(_,_,instrument,_,pitch) heard[#heard+1]=instrument..':'..pitch end,tick=function() end}
local function sounded(name) for _,h in ipairs(heard) do if h==name then return true end end return false end
local quit=false
local co=coroutine.create(function()
 app.run({target=t,clock=function() return clock end,now=function() return ms end,sound=sound,
  button=function(e,p1) return ({[keys.left]='LEFT',[keys.up]='CENTER',[keys.right]='RIGHT'})[p1] end})
 quit=true
end)
local oldPull,oldTimer=os.pullEventRaw,os.startTimer
os.pullEventRaw=function() return coroutine.yield() end; os.startTimer=function() return 1 end
local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
local function run(s) for _=1,s*20 do clock=clock+.05; send('timer',1) end end
local function word(w) for c in w:gmatch('.') do send('char',c:lower()) end end
local function key(k) send('key',k) end
local function line(y) return (t.getLine(y)) end
local function has(y,text) return line(y):find(text,1,true)~=nil end
local L=app.layout(51,19)
local function tile(r) return (line(L.gridY+(r-1)*(L.th+L.rg)):gsub('[^%u]','')) end
local ok,err=pcall(function()
 send(); run(.2)
 check(has(1,'DAILY WORDLE #1'),'Title and number')
 check(has(19,'PRESS Q'),'Bar shows the lit key')
 -- Too short, then not a word: refused, the row stays.
 word('sto'); key(keys.enter); run(.1)
 check(has(18,'NOT ENOUGH LETTERS'),'Short guess refused'); check(sounded('bass:6'),'Refusal buzz')
 key(keys.backspace); key(keys.backspace); key(keys.backspace)
 word('zzzzz'); key(keys.enter); run(.1)
 check(has(18,'NOT IN WORD LIST'),'Unknown word refused'); eq(tile(1),'ZZZZZ','Refused guess stays to fix')
 for _=1,5 do key(keys.backspace) end
 -- A letter key's key event must not also move the cursor or type twice.
 key(keys.a); send('char','a'); eq(tile(1),'A','One A'); key(keys.backspace)
 -- CRANE: the tiles turn over one at a time.
 word('crane'); key(keys.enter); run(.1)
 run(2)
 eq(tile(1),'CRANE','First guess on the board')
 check(sounded('bell:18') and sounded('snare:8'),'Tiles sound as they turn')
 check(has(18,'GUESS 2 OF 6'),'Second guess next')
 local bg=select(3,t.getLine(L.gridY))
 eq(bg:sub(L.gridX,L.gridX),colors.toBlit(colors.gray),'C is a miss')
 eq(bg:sub(L.gridX+3*(L.tw+1),L.gridX+3*(L.tw+1)),colors.toBlit(colors.green),'N is a hit')
 -- The cabinet buttons: RIGHT moves along the keys, CENTER presses, then type the rest.
 key(keys.right); check(has(19,'PRESS W'),'RIGHT moves to W')
 key(keys.left); key(keys.left); check(has(19,'PRESS DEL'),'LEFT wraps to DEL')
 for _=1,16 do key(keys.left) end
 check(has(19,'PRESS S'),'Back along the bottom row and up to S'); key(keys.up)
 word('tone'); key(keys.enter); run(3)
 eq(tile(2),'STONE','Solved on guess two')
 check(has(18,'MAGNIFICENT! SOLVED 2/6'),'Win message'); check(sounded('chime:24'),'Win jingle')
 check(has(19,'NEXT PLAYER'),'Next player offered')
 -- Typing after the win does nothing; NEXT PLAYER clears the board for the same word.
 word('abc'); eq(tile(3),'','No typing once solved')
 key(keys.up); run(.1)
 eq(tile(1),'','Board cleared'); check(has(1,'DAILY WORDLE #1'),'Same puzzle')
 -- Six misses lose and show the word.
 for _=1,6 do word('crane'); key(keys.enter); run(2) end
 check(has(18,'THE WORD WAS STONE'),'Loss shows the word'); check(sounded('didgeridoo:4'),'Loss sound')
 -- The next player after midnight gets the next day's word.
 ms=at('2026-10-09',0.5); key(keys.up); run(.1)
 check(has(1,'DAILY WORDLE #2'),'Next day')
 for _=1,6 do word('crane'); key(keys.enter); run(2) end
 check(has(18,'THE WORD WAS BLAZE'),'Day two is BLAZE')
 key(keys.left)
 check(quit,'QUIT leaves the game')
end)
os.pullEventRaw,os.startTimer=oldPull,oldTimer
if not ok then error(err,0) end
print(('wordle: %d checks passed'):format(passed))
