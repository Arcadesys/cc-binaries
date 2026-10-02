-- Pine Arcade checks: `get all` from this checkout, the Furball games on the shared Pine3D,
-- and the menu driven through its real event loop, changing the boot choice with get.lua.
-- Needs the repository root at /repo (derby/tools/run.py mounts it).
local dump=require('casino.tests.screen')
local passed=0
local function check(v,msg) assert(v,msg); passed=passed+1 end
local function eq(a,b,msg) check(a==b,(msg or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local function read(path) local f=fs.open(path,'r'); if not f then return nil end; local s=f.readAll(); f.close(); return s end
local dir='/results/all'
fs.delete('/startup.lua')
-- Install everything, booting into the menu.
check(shell.run('/arcade/get.lua','all','--local','/repo/cc-arcade','--dir',dir,'--startup'),'get all')
local manifest=textutils.unserializeJSON(read('/arcade/manifest.json'))
local state=textutils.unserializeJSON(read(dir..'/.get.json'))
eq(state.programs[1],'pinearcade','Menu installed first'); eq(state.boot,'pinearcade','Boots into the menu')
for _,name in ipairs(manifest.order) do
 check(state.catalog[name],name..' in the catalog')
 for _,f in ipairs(manifest.programs[name].files) do check(fs.exists(fs.combine(dir,f.path)),name..' missing '..f.path) end
end
check(not fs.exists(dir..'/pine-ball/vendor'),'Furball games share the derby Pine3D')
local boot=read('/startup.lua')
check(boot:find('pinearcade.lua',1,true) and boot:find(dir,1,true),'Startup runs the menu')
-- Each Furball game loads its renderer (and so Pine3D) the way its entry file sets up require.
for _,name in ipairs({'pineball','pinelinks','pinelanes','pinedungeon','pineface'}) do
 local entry=fs.combine(dir,state.catalog[name].entry)
 local src=read(entry)
 check(src:find('derby',1,true),name..' entry falls back to the shared Pine3D')
 local base=fs.getDir(entry)
 local env=setmetatable({},{__index=_ENV}); env.require,env.package=require('cc.require').make(env,base)
 env.package.path=env.package.path..';/'..fs.combine(base,'..','derby')..'/?.lua'
 local ok,err=pcall(env.require,'lib.render'); check(ok,name..' render: '..tostring(err))
 ok,err=pcall(env.require,'lib.app'); check(ok,name..' app: '..tostring(err))
end
-- get boot by hand.
check(shell.run(dir..'/get.lua','boot','pinelanes','--dir',dir),'get boot pinelanes')
check(read('/startup.lua'):find('pine-lanes/bowl.lua',1,true),'Boots into Pine Lanes')
check(not shell.run(dir..'/get.lua','boot','nosuchgame','--dir',dir),'Unknown programs are refused')
check(shell.run(dir..'/get.lua','boot','pinearcade','--dir',dir),'Back to the menu')
-- The menu, through its event loop with a fake clock.
local app=require('pinearcade.app')
local t=window.create(term.current(),1,1,51,19,false)
local now=0; local launched={}; local paused=0
local heard={}; local ticks=0
local sound={play=function(_,at,instrument,volume,pitch) heard[#heard+1]=instrument..':'..pitch end,tick=function() ticks=ticks+1 end}
local function sounded(name) for _,h in ipairs(heard) do if h==name then return true end end return false end
local opts={dir=dir,target=t,clock=function() return now end,sound=sound,
 launch=function(item,args) launched[#launched+1]=item.name; return item.name~='pineface' end,
 pause=function() paused=paused+1 end}
local co=coroutine.create(function() app.run(opts) end)
local oldPull,oldTimer=os.pullEventRaw,os.startTimer
os.pullEventRaw=function() return coroutine.yield() end; os.startTimer=function() return 1 end
local function send(...) local ok,err=coroutine.resume(co,...); assert(ok,err) end
local function run(s) for _=1,s*20 do now=now+.05; send('timer',1) end end
local function key(k) send('key',k); run(.6) end
local function text(y) return (t.getLine(y)) end
local function state_() return textutils.unserializeJSON(read(dir..'/.get.json')) end
send(); run(1)
check(sounded('harp:12') and sounded('harp:24'),'Menu greets with a jingle')
check(text(19):find('CHOOSE',1,true),'Browse bar'); check(text(16):find('PINE SLOTS',1,true),'First game shown')
check(text(18):find('STARTS AT BOOT: THIS MENU',1,true),'Boot status')
dump(t,'arcade-51-browse')
key(keys.right); check(text(16):find('PINE JACK',1,true),'RIGHT turns to the next game')
check(sounded('hat:20'),'Turning right ticks')
key(keys.enter); check(text(19):find('START AT BOOT',1,true),'Game card')
check(sounded('pling:16'),'Choosing a game chimes')
dump(t,'arcade-51-card')
key(keys.right)
eq(state_().boot,'pinejack','START AT BOOT'); check(read('/startup.lua'):find('pinejack.lua',1,true),'Startup runs Pine Jack')
check(text(18):find('PINE JACK NOW STARTS AT BOOT',1,true),'Confirmation shown')
check(sounded('chime:19'),'A boot change confirms')
check(text(19):find('MENU AT BOOT',1,true),'Card offers the menu back')
key(keys.enter); eq(launched[1],'pinejack','PLAY launches the game'); check(sounded('basedrum:10'),'Launching a game sounds'); eq(paused,0,'No pause after a clean run'); check(text(19):find('CHOOSE',1,true),'Back to browsing after play')
-- Left past the first game wraps to the STARTUP tile.
key(keys.left); key(keys.left); check(text(16):find('STARTUP',1,true),'Wraps to STARTUP')
dump(t,'arcade-51-startup')
key(keys.enter); key(keys.right)
eq(state_().boot,nil,'NOTHING AT BOOT'); check(not fs.exists('/startup.lua'),'Startup removed')
check(sounded('chime:14'),'Clearing the boot choice sounds different')
key(keys.enter); eq(state_().boot,'pinearcade','MENU AT BOOT'); check(read('/startup.lua'):find('pinearcade.lua',1,true),'Startup runs the menu again')
key(keys.backspace); check(text(19):find('NEXT',1,true),'Backspace leaves the card')
check(sounded('hat:8'),'Leaving a card sounds'); check(ticks>20,'The frame loop drains the sound queue')
-- Touch: the bar's thirds are the buttons; a game that errors is reported.
key(keys.left); check(text(16):find('PINE FACE',1,true),'Previous game')
send('mouse_click',1,25,19); run(.6); send('mouse_click',1,25,19); run(.6)
eq(launched[2],'pineface','Clicked PLAY'); check(text(18):find('STOPPED',1,true),'Stop reported'); eq(paused,1,'Output held after a failed run')
send('terminate'); check(coroutine.status(co)=='dead','Terminate leaves the menu')
os.pullEventRaw,os.startTimer=oldPull,oldTimer
-- Screens at a monitor size, mid-turn and with a card open.
local render=require('pinearcade.render')
local items=app.items(state_())
for _,size in ipairs({{100,40},{39,19},{29,16}}) do
 local w=window.create(term.current(),1,1,size[1],size[2],false)
 require('casino.palette').apply(w)
 local r=render.new(w,items)
 local n=#items
 r:draw({angle=2.5*2*math.pi/n,selected=3,spin=.6,boot='pinearcade',title='PINE SHUT THE BOX',subtitle=items[3].description,status='STARTS AT BOOT: THIS MENU',options={{label='< PREV'},{label='CHOOSE'},{label='NEXT >'}},counter='3/'..n})
 dump(w,('arcade-%d-turning'):format(size[1]))
 for k=1,n do
  r:draw({angle=(k-1)*2*math.pi/n,selected=k,spin=.5,zoom=1,boot='pinejack',title=items[k].title:upper(),subtitle=items[k].description,status='STARTS AT BOOT: PINE JACK',options={{label='BACK'},{label='PLAY'},{label='START AT BOOT'}}})
  dump(w,('arcade-%d-card-%s'):format(size[1],items[k].name))
 end
 local start=os.epoch('utc'); for k=1,30 do r:draw({angle=k*.05,selected=1,spin=k*.1}) end
 local fps=30/math.max(.001,(os.epoch('utc')-start)/1000)
 print(('Rendered %dx%d at %.1f fps'):format(size[1],size[2],fps)); check(fps>=10,'Render under 10 fps')
end
print(('PASS pine arcade (%d checks)'):format(passed))
