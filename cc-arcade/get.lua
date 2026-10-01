-- Arcade cabinet installer: one game and exactly the files it needs, straight from GitHub.
--   wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-arcade/get.lua pineslots --startup
-- Usage: get [program ...] [options]      (no program: pick from a menu)
--        get update                        re-download what this computer has installed
--        get list                          show the programs
-- Options:
--   --startup         boot straight into the (first) program
--   --monitor NAME    with --startup: draw on this monitor instead of the first one found
--   --base URL        raw GitHub base for a fork or branch, e.g.
--                     https://raw.githubusercontent.com/Arcadesys/cc-binaries/my-branch
--   --local DIR       copy from a checkout on this computer instead of downloading
--   --dir DIR         install location (default /arcade)
local DEFAULT_BASE='https://raw.githubusercontent.com/Arcadesys/cc-binaries/main'
local STATE='.get.json'
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
 elseif a=='update' or a=='list' then o.command=a
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
-- Updating reuses the saved source and selection unless told otherwise.
local saved=readJSON(fs.combine(o.dir,STATE))
if o.command=='update' then
 assert(saved,'Nothing installed in '..o.dir..' yet. Run get <program> first.')
 if #o.programs==0 then o.programs=saved.programs end
 o.base=o.base or saved.base; o.localDir=o.localDir or saved.localDir
 if o.startup==nil then o.startup=saved.startup end
 o.monitor=o.monitor or saved.monitor
end
o.base=(o.base or DEFAULT_BASE):gsub('/$','')
local function fetch(rel)
 if o.localDir then
  local p=fs.combine(o.localDir,rel)
  if not fs.exists(p) then return nil,'missing '..p end
  local f=fs.open(p,'rb'); local data=f.readAll(); f.close(); return data
 end
 if not http then return nil,'The HTTP API is disabled on this server (http.enabled in the CC: Tweaked config).' end
 local url=o.base..'/cc-arcade/'..rel
 local ok,h,err=pcall(http.get,url,nil,true)
 if not ok or not h then return nil,tostring(err or h or 'request failed')..': '..url end
 local data=h.readAll(); h.close(); return data
end
local text,err=fetch('manifest.json')
if not text then error('Cannot read the program list: '..err,0) end
local manifest=textutils.unserializeJSON(text)
assert(manifest and manifest.programs,'manifest.json is not valid')
local names={}
for name in pairs(manifest.programs) do names[#names+1]=name end
table.sort(names)
local function isTool(name) for _,t in ipairs(manifest.tools) do if t==name then return true end end end
if o.command=='list' then
 for _,n in ipairs(names) do local p=manifest.programs[n]; say(('%-10s %s'):format(n,p.title),colors.yellow); say('           '..p.description) end
 return
end
-- No program named: offer a menu of the games (the tools come with every install).
if #o.programs==0 then
 say('ARCADE CABINET INSTALLER',colors.yellow)
 local games={}
 for _,n in ipairs(names) do if not isTool(n) then games[#games+1]=n end end
 for k,n in ipairs(games) do say(('%d) %s - %s'):format(k,manifest.programs[n].title,manifest.programs[n].description)) end
 write('Install which number? ')
 local pick=games[tonumber(read())]
 assert(pick,'No program chosen')
 o.programs={pick}
 write('Start it when the computer boots? (y/n) ')
 o.startup=read():lower():sub(1,1)=='y'
end
for _,n in ipairs(o.programs) do assert(manifest.programs[n],'Unknown program "'..n..'". Try: get list') end
-- Every file the chosen programs and the tools need, once each.
local wanted,order={},{}
local function want(path,size) if not wanted[path] then wanted[path]=size; order[#order+1]=path end end
local selection={}
for _,n in ipairs(o.programs) do selection[#selection+1]=n end
for _,t in ipairs(manifest.tools) do selection[#selection+1]=t end
for _,n in ipairs(selection) do for _,f in ipairs(manifest.programs[n].files) do want(f.path,f.size) end end
want('get.lua')
local total=#order
say(('Installing %s into %s (%d files)'):format(table.concat(o.programs,', '),o.dir,total),colors.yellow)
local _,y=term.getCursorPos()
for k,path in ipairs(order) do
 local data,e=fetch(path)
 if not data then error('Download failed: '..e,0) end
 if wanted[path] and #data~=wanted[path] then error(('%s: expected %d bytes, got %d. Try again in a minute (GitHub may still be updating).'):format(path,wanted[path],#data),0) end
 local dest=fs.combine(o.dir,path)
 local f=assert(fs.open(dest,'wb'),'Cannot write '..dest); f.write(data); f.close()
 term.setCursorPos(1,y); term.clearLine(); write(('[%d/%d] %s'):format(k,total,path))
end
print()
local state={base=o.base,localDir=o.localDir,programs=o.programs,startup=o.startup,monitor=o.monitor}
local f=fs.open(fs.combine(o.dir,STATE),'w'); f.write(textutils.serializeJSON(state)); f.close()
if o.startup then
 local first=manifest.programs[o.programs[1]]
 local marker='-- Written by the arcade installer (get.lua).'
 if fs.exists('/startup.lua') then
  local h=fs.open('/startup.lua','r'); local old=h.readAll(); h.close()
  if old:sub(1,#marker)~=marker then fs.delete('/startup.lua.bak'); fs.move('/startup.lua','/startup.lua.bak'); say('Kept your old startup as /startup.lua.bak',colors.lightGray) end
 end
 local run={('%q'):format(first.entry)}
 if o.monitor then run[#run+1]=('%q'):format('--monitor'); run[#run+1]=('%q'):format(o.monitor) end
 local s=fs.open('/startup.lua','w')
 s.write(marker..'\n-- Re-run "get update" in '..o.dir..' to update; delete this file to stop autostart.\n')
 s.write(('shell.setDir(%q)\nshell.run(%s)\n'):format(o.dir,table.concat(run,', ')))
 s.close()
 say('Boots into '..first.title..'.',colors.lime)
end
say('Done.',colors.lime)
say(('Play:   cd %s  then  %s'):format(o.dir,o.programs[1]))
say('Update: '..fs.combine(o.dir,'get')..' update')
say('Cabinet buttons: config   House station: house setup station <modem> <host-id>')
if o.programs[1]=='pineslots' then say('Arm and buttons: pineslots setup') end
