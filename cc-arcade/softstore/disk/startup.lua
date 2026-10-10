-- Pine Software disk startup: offers to install the disk's title once, then starts the
-- computer as it would without the disk (a disk's startup runs instead of the computer's).
local here=fs.getDir(shell.getRunningProgram())
local function readJSON(path)
 if not fs.exists(path) then return nil end
 local f=fs.open(path,'r'); local v=textutils.unserializeJSON(f.readAll()); f.close(); return v
end
local sw=readJSON(fs.combine(here,'.software.json'))
local done=readJSON('/.pine-software.json') or {}
-- The store kiosk itself boots with customers' disks in its drive.
if sw and not done[sw.id] and not settings.get('softstore.kiosk') then
 print('Pine Software disk: '..sw.title)
 write('Install it on this computer? (y/n) ')
 if read():lower():sub(1,1)=='y' then shell.run('/'..fs.combine(here,'install.lua')) end
end
if fs.exists('/startup.lua') then shell.run('/startup.lua')
elseif fs.isDir('/startup') then
 local files=fs.list('/startup'); table.sort(files)
 for _,f in ipairs(files) do shell.run('/startup/'..f) end
elseif fs.exists('/startup') then shell.run('/startup') end
