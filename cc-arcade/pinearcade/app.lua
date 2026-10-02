-- Pine Arcade: a Pine3D menu of the games get.lua installed beside it. LEFT and RIGHT
-- turn the carousel, CENTER picks a game; a picked game can be played or made what this
-- computer boots into. The last tile, STARTUP, boots into this menu or into nothing.
-- Boot changes go through `get boot`, so the installer's saved state stays the truth.
local render=require('pinearcade.render')
local M={}
local STATE='.get.json'
local function readJSON(path)
 if not fs.exists(path) then return nil end
 local f=fs.open(path,'r'); local v=textutils.unserializeJSON(f.readAll()); f.close(); return v
end
-- Installed games in install order, then the STARTUP tile.
function M.items(state)
 local list={}
 for _,n in ipairs(state.programs or {}) do
  local p=state.catalog[n]
  if p and p.kind=='game' then list[#list+1]={name=n,title=p.title,entry=p.entry,description=p.description,monitor=p.monitor} end
 end
 list[#list+1]={name='boot',title='Startup',description='Choose what this computer runs when it turns on'}
 return list
end
local KEYS_BACK={[keys.backspace]=true}
-- Menu sounds: {seconds after the cue, instrument, volume, pitch}. A game launch is a single
-- chord because the menu stops listening while the game has the screen.
local CUES={
 welcome={{0,'harp',1,12},{.12,'harp',1,16},{.24,'harp',1,19},{.36,'harp',1,24}},
 left={{0,'hat',.5,14}},
 right={{0,'hat',.5,20}},
 choose={{0,'pling',.8,16},{.08,'pling',.8,21}},
 back={{0,'hat',.5,8}},
 launch={{0,'bell',1,12},{0,'bell',1,19},{0,'basedrum',1,10}},
 bootOn={{0,'chime',1,19},{.1,'chime',1,24}},
 bootOff={{0,'chime',.8,14},{.1,'chime',.8,9}},
 denied={{0,'bass',1,6},{.12,'bass',1,3}},
}
M.cues=CUES
-- opts: dir (install folder holding .get.json), target, args (as given to pinearcade),
-- clock(), button(event,p1), launch(item,args) -> ok[, problem], pause(item) (waits after a
-- game stops, so its error can be read), setBoot(name|'off') -> ok, sound (casino.sound's
-- play(at,instrument,volume,pitch) and tick(now), timed by clock())
function M.run(opts)
 local dir=opts.dir
 local state=readJSON(fs.combine(dir,STATE))
 assert(state and state.catalog,'Pine Arcade lists what get.lua installed in '..dir..'. Install with: get all')
 local items=M.items(state)
 local t=opts.target
 local args=opts.args or {}
 local clock=opts.clock or function() return os.epoch('utc')/1000 end
 local button=opts.button or require('input').getButton
 local monitorName
 for i,a in ipairs(args) do if a=='--monitor' then monitorName=args[i+1] end end
 if not monitorName and peripheral.getName then local ok,name=pcall(peripheral.getName,t); if ok then monitorName=name end end
 local launch=opts.launch or function(item,gameArgs)
  local path='/'..fs.combine(dir,item.entry)
  if not fs.exists(path) then return false,'NOT INSTALLED, RUN GET UPDATE' end
  return shell.run(path,table.unpack(gameArgs))
 end
 local pause=opts.pause or function()
  -- Whatever the game printed is still on screen; hold it until a key is pressed.
  local w,h=term.getSize()
  term.setCursorPos(1,h); term.setTextColor(colors.yellow); term.write('Press any key to return to the menu')
  os.pullEventRaw('key')
 end
 local setBoot=opts.setBoot or function(name)
  -- get.lua prints as it works; keep that off the menu.
  local hidden=window.create(term.current(),1,1,51,19,false)
  local old=term.redirect(hidden)
  local ok=shell.run('/'..fs.combine(dir,'get.lua'),'boot',name,'--dir','/'..fs.combine(dir,''))
  term.redirect(old)
  return ok
 end
 local sound=opts.sound or require('casino.sound')()
 local function cue(name)
  local at=clock()
  for _,n in ipairs(CUES[name]) do sound:play(at+n[1],n[2],n[3],n[4]) end
  sound:tick(at)
 end
 local palette=require('casino.palette')
 local restore=require('derby.palette').save(t)
 palette.apply(t)
 local view=render.new(t,items)
 local n=#items
 local index=1 -- unbounded, so the carousel always turns the short way
 local pos,zoom,spin=0,0,0
 local mode='browse'
 local flash,flashUntil
 local function selected() return (index-1)%n+1 end
 local function item() return items[selected()] end
 local function bootTitle()
  local b=state.boot
  if not b then return nil end
  if state.catalog[b] and state.catalog[b].kind=='launcher' then return 'THIS MENU' end
  return state.catalog[b] and state.catalog[b].title:upper() or b
 end
 local function launcher()
  for name,p in pairs(state.catalog) do if p.kind=='launcher' then return name end end
  return 'off'
 end
 local function say(text) flash=text; flashUntil=clock()+3 end
 local function options()
  local it=item()
  if mode=='browse' then return {{label='< PREV'},{label=it.name=='boot' and 'STARTUP' or 'CHOOSE'},{label='NEXT >'}} end
  if it.name=='boot' then return {{label='BACK'},{label='MENU AT BOOT'},{label='NOTHING AT BOOT'}} end
  return {{label='BACK'},{label='PLAY'},{label=state.boot==it.name and 'MENU AT BOOT' or 'START AT BOOT'}}
 end
 local function status()
  if flash and clock()<flashUntil then return flash,true end
  local b=bootTitle()
  return b and 'STARTS AT BOOT: '..b or 'NOTHING STARTS AT BOOT',false
 end
 local function draw()
  local it=item()
  local text,hi=status()
  view:draw({angle=pos*2*math.pi/n,selected=selected(),spin=spin,zoom=zoom,bob=mode=='card' and math.sin(clock()*3)*.08 or 0,
   boot=state.boot,title=it.title:upper(),subtitle=it.description,status=text,highlight=hi,options=options(),counter=selected()..'/'..n})
 end
 local function changeBoot(name)
  if setBoot(name) then
   state=readJSON(fs.combine(dir,STATE)) or state
   local b=bootTitle()
   say(b and b..' NOW STARTS AT BOOT' or 'NOTHING STARTS AT BOOT NOW')
   cue(b and 'bootOn' or 'bootOff')
  else say('COULD NOT CHANGE THE STARTUP'); cue('denied') end
 end
 local function play(it)
  restore()
  t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1)
  -- The screen chosen for the menu carries over to games that take the same options.
  local gameArgs={}
  if it.monitor~=false then
   for i,a in ipairs(args) do
    if a=='--terminal' then gameArgs[#gameArgs+1]=a
    elseif a=='--monitor' then gameArgs[#gameArgs+1]=a; gameArgs[#gameArgs+1]=args[i+1] end
   end
  end
  cue('launch')
  local ok,problem=launch(it,gameArgs)
  -- A failed run (a crash, or Ctrl+T) keeps its output up until a key is pressed.
  if not ok and not problem then pause(it) end
  palette.apply(t); t.setBackgroundColor(colors.black); t.clear()
  mode='browse'
  if problem then say(it.title:upper()..' '..problem)
  elseif not ok then say(it.title:upper()..' STOPPED') end
 end
 local function press(b)
  local it=item()
  if mode=='browse' then
   if b=='LEFT' then index=index-1; spin=0; cue('left')
   elseif b=='RIGHT' then index=index+1; spin=0; cue('right')
   elseif b=='CENTER' then mode='card'; cue('choose') end
  elseif b=='LEFT' then mode='browse'; cue('back')
  elseif it.name=='boot' then
   changeBoot(b=='CENTER' and launcher() or 'off')
  elseif b=='CENTER' then play(it)
  else changeBoot(state.boot==it.name and launcher() or it.name) end
 end
 local function pointer(x,y)
  local w,h=t.getSize()
  if y==h then
   for i,s in ipairs(render.slots(w)) do if x>=s.x1 and x<=s.x2 then return ({'LEFT','CENTER','RIGHT'})[i] end end
  elseif mode=='browse' and y>1 and y<h-3 then
   return x<=w/3 and 'LEFT' or x>w*2/3 and 'RIGHT' or 'CENTER'
  end
 end
 local last=clock()
 local timer=os.startTimer(.05)
 cue('welcome')
 local ok,err=pcall(function()
  while true do
   local e,p1,p2,p3=os.pullEventRaw()
   if e=='terminate' then return end
   local b
   if e=='timer' and p1==timer then
    local now=clock(); local dt=math.min(.2,now-last); last=now
    pos=pos+(index-1-pos)*math.min(1,dt*9)
    if math.abs(index-1-pos)<.002 then pos=index-1 end
    zoom=zoom+((mode=='card' and 1 or 0)-zoom)*math.min(1,dt*8)
    spin=spin+dt*(mode=='card' and 2 or .8)
    sound:tick(now)
    draw()
    timer=os.startTimer(.05)
   elseif e=='key' and KEYS_BACK[p1] and mode=='card' then b='LEFT'
   elseif e=='mouse_click' and not monitorName then b=pointer(p2,p3)
   elseif e=='monitor_touch' and p1==monitorName then b=pointer(p2,p3)
   elseif e=='key' or e=='char' or e=='redstone' then b=button(e,p1) end
   if b then
    press(b); draw()
    -- A game takes the screen and its own timers; start ours again afterwards.
    timer=os.startTimer(.05); last=clock()
   end
  end
 end)
 restore()
 t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1)
 if not ok then error(err,0) end
end
return M
