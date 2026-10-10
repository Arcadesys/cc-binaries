-- Pine Software disk installer. The disk's startup runs it when a computer boots with the
-- disk in a drive; it also runs by hand: disk/install
-- .software.json beside it says what the disk holds: {id, title, kind, programs, base}.
-- Everything downloads from GitHub, so the computer needs HTTP.
local here=fs.getDir(shell.getRunningProgram())
local RECORD='/.pine-software.json'
local function readJSON(path)
 if not fs.exists(path) then return nil end
 local f=fs.open(path,'r'); local v=textutils.unserializeJSON(f.readAll()); f.close(); return v
end
local function writeJSON(path,v) local f=fs.open(path,'w'); f.write(textutils.serializeJSON(v)); f.close() end
local function say(text,c) if term.isColor() then term.setTextColor(c or colors.white) end; print(text); term.setTextColor(colors.white) end
local function ask(q) write(q..' (y/n) '); return read():lower():sub(1,1)=='y' end
local sw=readJSON(fs.combine(here,'.software.json'))
if not sw then error('This disk has no Pine Software on it.',0) end
if not http then error('Installing needs HTTP, which is turned off on this server.',0) end
-- Fetch an installer from the repository and run it here, so shell and require reach it.
local function run(path,...)
 local ok,h=pcall(http.get,sw.base..'/'..path)
 if not ok or not h then return false,'Cannot reach '..sw.base..'/'..path end
 local src=h.readAll(); h.close()
 local fn,err=load(src,'@'..path,'t',_ENV)
 if not fn then return false,err end
 return pcall(fn,...)
end
local args,path={}
if sw.kind=='arcade' then
 path='cc-arcade/get.lua'
 if sw.programs[1]=='all' then args={'all'}
 else
  -- get.lua records only what it was asked for, so ask again for every game this
  -- computer already has; the Pine Arcade menu then shows them all.
  local saved=readJSON('/arcade/.get.json')
  local seen={}
  local function add(n) if not seen[n] then seen[n]=true; args[#args+1]=n end end
  add('pinearcade')
  for _,n in ipairs(saved and saved.programs or {}) do add(n) end
  for _,n in ipairs(sw.programs) do add(n) end
  if not (saved and saved.boot) and ask('Start Pine Arcade when this computer turns on?') then args[#args+1]='--startup' end
 end
 args[#args+1]='--base'; args[#args+1]=sw.base
elseif sw.kind=='arcadeos' then
 path='arcadeos/install.lua'
 args={'--base',sw.base}
elseif sw.kind=='turtleos' then
 if not turtle then error('TurtleOS runs on turtles. Put this disk in a drive next to a turtle.',0) end
 path='cc-turtleos/install.lua'
 args={'--base',sw.base}
else error('Unknown software kind '..tostring(sw.kind),0) end
say('PINE SOFTWARE',colors.yellow)
say('Installing '..sw.title..'...')
-- Recorded first: the ArcadeOS and TurtleOS installers start or reboot into what they
-- installed and never return here.
local done=readJSON(RECORD) or {}
done[sw.id]=true; writeJSON(RECORD,done)
local ok,err=run(path,table.unpack(args))
if not ok then
 done[sw.id]=nil; writeJSON(RECORD,done)
 error('Install failed: '..tostring(err),0)
end
say(sw.title..' is installed.',colors.lime)
if sw.kind=='arcade' then say('Type arcade/pinearcade to play.') end
