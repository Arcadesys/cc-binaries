-- Arcade cabinet installer: one game and exactly the files it needs, straight from GitHub.
--   wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-arcade/get.lua pineslots --startup
--   wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-arcade/get.lua all --startup
-- Usage: get [program ...] [options]      (no program: pick from a menu)
--        get all                           every game, with the Pine Arcade menu first
--        get update                        re-download what this computer has installed
--        get boot <program|off>            choose what this computer starts into
--        get list                          show the programs
-- Options:
--   --startup         boot straight into the (first) program
--   --monitor NAME    with --startup: draw on this monitor instead of the first one found
--   --base URL        raw GitHub base for a fork or branch, e.g.
--                     https://raw.githubusercontent.com/Arcadesys/cc-binaries/my-branch
--   --local DIR       copy from a cc-arcade checkout on this computer instead of downloading
--   --dir DIR         install location (default /arcade)
local DEFAULT_BASE='https://raw.githubusercontent.com/Arcadesys/cc-binaries/main'
local STATE='.get.json'
local MARKER='-- Written by the arcade installer (get.lua).'
local args={...}
local o={dir='/arcade',programs={}}
local i=1
while i<=#args do
 local a=args[i]
 if a=='--startup' then o.startup=true
 elseif a=='--monitor' then i=i+1; o.monitor=args[i]
 elseif a=='--base' then i=i+1; o.base=args[i]
 elseif a=='--local' then i=i+1; o.localDir=args[i]
 elseif a=='--dir' then i=i+1; o.dir=args[i]
 elseif (a=='update' or a=='list' or a=='all' or a=='boot') and not o.command then o.command=a
 elseif a:sub(1,2)=='--' then error('Unknown option '..a,0)
 else o.programs[#o.programs+1]=a end
 i=i+1
end
local function color(c) if term.isColor() then term.setTextColor(c) end end
local function say(text,c) color(c or colors.white); print(text); color(colors.white) end
local function readJSON(path)
 if not fs.exists(path) then return nil end
 local f=fs.open(path,'r'); local v=textutils.unserializeJSON(f.readAll()); f.close(); return v
end
local function writeJSON(path,v) local f=fs.open(path,'w'); f.write(textutils.serializeJSON(v)); f.close() end
local saved=readJSON(fs.combine(o.dir,STATE))
-- Installs from before `boot` existed recorded startup=true and booted the first program.
if saved and saved.boot==nil and saved.startup then saved.boot=saved.programs[1] end
-- /startup.lua runs state.boot, or is removed when nothing should start. A startup.lua
-- this installer did not write is kept as /startup.lua.bak.
local function ours()
 if not fs.exists('/startup.lua') then return false end
 local h=fs.open('/startup.lua','r'); local old=h.readAll(); h.close()
 return old:sub(1,#MARKER)==MARKER
end
local function writeStartup(state)
 local p=state.boot and state.catalog and state.catalog[state.boot]
 if not p then
  if ours() then fs.delete('/startup.lua') end
  return
 end
 if fs.exists('/startup.lua') and not ours() then fs.delete('/startup.lua.bak'); fs.move('/startup.lua','/startup.lua.bak'); say('Kept your old startup as /startup.lua.bak',colors.lightGray) end
 local run={('%q'):format(p.entry)}
 if state.monitor and p.monitor~=false then run[#run+1]=('%q'):format('--monitor'); run[#run+1]=('%q'):format(state.monitor) end
 local s=fs.open('/startup.lua','w')
 s.write(MARKER..'\n-- Change with "get boot <program|off>" in '..o.dir..', or from the Pine Arcade menu.\n')
 s.write(('shell.setDir(%q)\nshell.run(%s)\n'):format(o.dir,table.concat(run,', ')))
 s.close()
end
-- get boot <program|off>: no download, just the startup file and the saved choice.
if o.command=='boot' then
 assert(saved and saved.catalog,'Nothing installed in '..o.dir..' by this version of get yet. Run get update first.')
 local pick=o.programs[1]
 assert(pick,'Usage: get boot <program|off>')
 if pick=='off' then saved.boot=nil
 else
  assert(saved.catalog[pick],'"'..pick..'" is not installed here. Installed: '..table.concat(saved.programs,', '))
  saved.boot=pick
 end
 if o.monitor then saved.monitor=o.monitor end
 saved.startup=saved.boot~=nil
 writeJSON(fs.combine(o.dir,STATE),saved); writeStartup(saved)
 say(saved.boot and 'Boots into '..saved.catalog[saved.boot].title..'.' or 'Nothing starts at boot.',colors.lime)
 return
end
-- Updating reuses the saved source and selection unless told otherwise.
if o.command=='update' then
 assert(saved,'Nothing installed in '..o.dir..' yet. Run get <program> first.')
 if #o.programs==0 then o.programs=saved.programs end
 o.base=o.base or saved.base; o.localDir=o.localDir or saved.localDir
 o.monitor=o.monitor or saved.monitor
end
o.base=(o.base or DEFAULT_BASE):gsub('/$','')
-- Files carry their path in the install and, when they live outside cc-arcade, src: the
-- path from the repository root. --local points at cc-arcade, so src is found beside it.
local function fetch(rel,src)
 if o.localDir then
  local p=src and fs.combine(o.localDir,'..',src) or fs.combine(o.localDir,rel)
  if not fs.exists(p) then return nil,'missing '..p end
  local f=fs.open(p,'rb'); local data=f.readAll(); f.close(); return data
 end
 if not http then return nil,'The HTTP API is disabled on this server (http.enabled in the CC: Tweaked config).' end
 local url=o.base..'/'..(src or 'cc-arcade/'..rel)
 local ok,h,err=pcall(http.get,url,nil,true)
 if not ok or not h then return nil,tostring(err or h or 'request failed')..': '..url end
 local data=h.readAll(); h.close(); return data
end
local text,err=fetch('manifest.json')
if not text then error('Cannot read the program list: '..err,0) end
local manifest=textutils.unserializeJSON(text)
assert(manifest and manifest.programs,'manifest.json is not valid')
local names=manifest.order
if not names then names={}; for name in pairs(manifest.programs) do names[#names+1]=name end; table.sort(names) end
local function isTool(name) for _,t in ipairs(manifest.tools) do if t==name then return true end end end
local function isKiosk(name) for _,t in ipairs(manifest.kiosks or {}) do if t==name then return true end end end
local games={}
for _,n in ipairs(names) do if not isTool(n) and not isKiosk(n) and n~=manifest.launcher then games[#games+1]=n end end
if o.command=='list' then
 for _,n in ipairs(names) do local p=manifest.programs[n]; say(('%-11s %s'):format(n,p.title),colors.yellow); say('            '..p.description) end
 say(('%-11s %s'):format('all','Everything above, opening on the Pine Arcade menu'),colors.yellow)
 return
end
-- All: the menu first (so --startup boots into it), then every game.
local function everything()
 local list={}
 if manifest.launcher then list[1]=manifest.launcher end
 for _,n in ipairs(games) do list[#list+1]=n end
 return list
end
if o.command=='all' then o.programs=everything() end
-- No program named: offer a menu of the games (the tools come with every install).
if #o.programs==0 then
 say('ARCADE CABINET INSTALLER',colors.yellow)
 say('0) Everything - every game and the Pine Arcade menu to choose between them')
 for k,n in ipairs(games) do say(('%d) %s - %s'):format(k,manifest.programs[n].title,manifest.programs[n].description)) end
 write('Install which number? ')
 local n=tonumber(read())
 if n==0 then o.programs=everything()
 else
  local pick=games[n]
  assert(pick,'No program chosen')
  o.programs={pick}
 end
 write('Start it when the computer boots? (y/n) ')
 o.startup=read():lower():sub(1,1)=='y'
end
for _,n in ipairs(o.programs) do assert(manifest.programs[n],'Unknown program "'..n..'". Try: get list') end
-- Every file the chosen programs and the tools need, once each.
local wanted,order={},{}
local function want(f) if not wanted[f.path] then wanted[f.path]=f; order[#order+1]=f.path end end
local selection={}
for _,n in ipairs(o.programs) do selection[#selection+1]=n end
for _,t in ipairs(manifest.tools) do selection[#selection+1]=t end
for _,n in ipairs(selection) do for _,f in ipairs(manifest.programs[n].files) do want(f) end end
want({path='get.lua'})
local total=#order
say(('Installing %s into %s (%d files)'):format(table.concat(o.programs,', '),o.dir,total),colors.yellow)
local _,y=term.getCursorPos()
for k,path in ipairs(order) do
 local f=wanted[path]
 local data,e=fetch(path,f.src)
 if not data then error('Download failed: '..e,0) end
 if f.size and #data~=f.size then error(('%s: expected %d bytes, got %d. Try again in a minute (GitHub may still be updating).'):format(path,f.size,#data),0) end
 local dest=fs.combine(o.dir,path)
 local h=fs.open(dest,'wb')
 if not h then error('Cannot write '..dest..(fs.getFreeSpace(o.dir)<#data and ': the disk is full' or ''),0) end
 h.write(data); h.close()
 term.setCursorPos(1,y); term.clearLine(); write(('[%d/%d] %s'):format(k,total,path))
end
print()
-- The catalog lets the Pine Arcade menu and `get boot` work without the network.
local catalog={}
for _,n in ipairs(selection) do
 local p=manifest.programs[n]
 catalog[n]={title=p.title,entry=p.entry,description=p.description,monitor=p.monitor,kind=isTool(n) and 'tool' or isKiosk(n) and 'kiosk' or n==manifest.launcher and 'launcher' or 'game'}
end
local boot
if o.startup then boot=o.programs[1]
elseif saved and saved.boot and catalog[saved.boot] then boot=saved.boot end
local state={base=o.base,localDir=o.localDir,programs=o.programs,boot=boot,startup=boot~=nil,monitor=o.monitor,catalog=catalog}
writeJSON(fs.combine(o.dir,STATE),state)
-- Leave /startup.lua alone unless asked, or unless it is ours and runs something here.
if o.startup or (saved and saved.boot) then
 writeStartup(state)
 if boot then say('Boots into '..catalog[boot].title..'.',colors.lime) end
end
say('Done.',colors.lime)
say(('Play:   cd %s  then  %s'):format(o.dir,o.programs[1]))
say('Update: '..fs.combine(o.dir,'get')..' update')
if #o.programs>1 then say('Boot:   '..fs.combine(o.dir,'get')..' boot <program|off>, or from the Pine Arcade menu') end
say('Cabinet buttons: config   House station: house setup station <modem> <host-id>')
for _,n in ipairs(o.programs) do if n=='pineslots' then say('Arm and buttons: pineslots setup') end end
