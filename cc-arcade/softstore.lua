-- Pine Software: a casino kiosk that sells software on floppy disks for Eyes of Ender.
-- The customer picks a title, puts a floppy in the drive and Eyes of Ender in the payment
-- chest, and presses BUY. The kiosk moves the price into the vault chest, writes the disk
-- and ejects it. At home the disk offers to install the title when the computer starts
-- with it in a drive (or run disk/install).
-- Hardware: a disk drive, and two chests joined to the computer by wired modems (payment
-- and vault; pushItems only reaches inventories on the network). Optional: a monitor
-- (--monitor NAME) and a speaker.
-- Usage: softstore [--monitor NAME] [--base URL]
--        softstore setup       choose the payment and vault chests
--        softstore price N     Eyes of Ender per title (default 1)
local DEFAULT_BASE='https://raw.githubusercontent.com/Arcadesys/cc-binaries/main'
local EYE='minecraft:ender_eye'
local here=fs.getDir(shell.getRunningProgram())
local args={...}
local o={}
local i=1
while i<=#args do
 local a=args[i]
 if a=='--monitor' then i=i+1; o.monitor=args[i]
 elseif a=='--base' then i=i+1; o.base=args[i]
 elseif (a=='setup' or a=='price') and not o.command then o.command=a
 elseif o.command=='price' and not o.price then o.price=tonumber(a)
 else error('Unknown option '..a,0) end
 i=i+1
end
local function readJSON(path)
 if not fs.exists(path) then return nil end
 local f=fs.open(path,'r'); local v=textutils.unserializeJSON(f.readAll()); f.close(); return v
end
local function writeJSON(path,v) local f=fs.open(path,'w'); f.write(textutils.serializeJSON(v)); f.close() end

local function setup()
 local invs={}
 for _,n in ipairs(peripheral.getNames()) do
  if peripheral.wrap(n).pushItems then invs[#invs+1]=n end
 end
 if #invs<2 then error('Join two chests to this computer with wired modems: one for payment, one for the vault.',0) end
 local function choose(q,not_)
  while true do
   print(q)
   for k,n in ipairs(invs) do if n~=not_ then print(('%d) %s'):format(k,n)) end end
   write('Number? ')
   local n=invs[tonumber(read())]
   if n and n~=not_ then return n end
  end
 end
 local pay=choose('Which chest do customers put Eyes of Ender in?')
 local vault=choose('Which chest keeps the takings?',pay)
 settings.set('softstore.payment',pay)
 settings.set('softstore.vault',vault)
 -- Customers' disks sit in this computer's drive; their startup must not offer to install here.
 settings.set('softstore.kiosk',true)
 settings.save()
 print('Payment chest: '..pay..'. Vault: '..vault..'.')
end
if o.command=='setup' then return setup() end
if o.command=='price' then
 assert(o.price and o.price>=1 and o.price%1==0,'Usage: softstore price N (a whole number of Eyes of Ender)')
 settings.set('softstore.price',o.price); settings.save()
 print(('Each title now costs %d Eye%s of Ender.'):format(o.price,o.price==1 and '' or 's'))
 return
end
if not settings.get('softstore.payment') then setup() end
local payName,vaultName=settings.get('softstore.payment'),settings.get('softstore.vault')
local price=settings.get('softstore.price',1)
local pay,vault=peripheral.wrap(payName),peripheral.wrap(vaultName)
if not pay or not vault then error('Cannot find the payment or vault chest. Run softstore setup.',0) end
local drive=peripheral.find('drive')
if not drive then error('Attach a disk drive.',0) end
local speaker=peripheral.find('speaker')
local saved=readJSON(fs.combine(here,'.get.json'))
local base=o.base or (saved and saved.base) or DEFAULT_BASE

-- The shelf: every arcade game in the manifest, the whole arcade, ArcadeOS and TurtleOS.
local function shelf()
 local ok,h=pcall(http.get,base..'/cc-arcade/manifest.json')
 if not ok or not h then error('Cannot read the catalog from '..base,0) end
 local m=textutils.unserializeJSON(h.readAll()); h.close()
 local skip={[m.launcher]=true}
 for _,n in ipairs(m.tools or {}) do skip[n]=true end
 for _,n in ipairs(m.kiosks or {}) do skip[n]=true end
 local list={}
 for _,n in ipairs(m.order) do
  local p=m.programs[n]
  if not skip[n] then list[#list+1]={id=n,title=p.title,description=p.description,kind='arcade',programs={n}} end
 end
 list[#list+1]={id='all',title='Pine Arcade Complete',kind='arcade',programs={'all'},
  description='Every Pine game, with the Pine Arcade menu to choose between them.'}
 list[#list+1]={id='arcadeos',title='ArcadeOS',kind='arcadeos',
  description='A Windows 1.0-style desktop: Paint, Notepad, Reversi, Solitaire, Minesweeper, the Jukebox and the arcade games. Choose packages as it installs.'}
 list[#list+1]={id='turtleos',title='TurtleOS',kind='turtleos',
  description='Farming, tree and mining jobs for a turtle. Put the disk in a drive next to the turtle.'}
 return list
end
local items=shelf()

local function eyes()
 local n=0
 for _,it in pairs(pay.list()) do if it.name==EYE then n=n+it.count end end
 return n
end
-- Moves up to n Eyes from one chest to the other; returns how many moved.
local function move(from,toName,n)
 local moved=0
 for slot,it in pairs(from.list()) do
  if moved>=n then break end
  if it.name==EYE then moved=moved+from.pushItems(toName,slot,n-moved) end
 end
 return moved
end
-- none | record | blank | ours (a Pine Software disk, safe to rewrite) | used
local function diskState()
 if not drive.isDiskPresent() then return 'none' end
 if not drive.hasData() then return 'record' end
 local path=drive.getMountPath()
 if fs.exists(fs.combine(path,'.software.json')) then return 'ours',path end
 if #fs.list(path)==0 then return 'blank',path end
 return 'used',path
end
local function writeDisk(path,item)
 for _,f in ipairs(fs.list(path)) do fs.delete(fs.combine(path,f)) end
 fs.copy(fs.combine(here,'softstore/disk/install.lua'),fs.combine(path,'install.lua'))
 fs.copy(fs.combine(here,'softstore/disk/startup.lua'),fs.combine(path,'startup.lua'))
 writeJSON(fs.combine(path,'.software.json'),{id=item.id,title=item.title,kind=item.kind,programs=item.programs,base=base})
end
local function chime(notes)
 if not speaker then return end
 for _,n in ipairs(notes) do speaker.playNote(n[1],1,n[2]); sleep(.1) end
end

-- Screen
if o.monitor then
 local mon=peripheral.wrap(o.monitor)
 if not mon then error('No monitor called '..o.monitor,0) end
 mon.setTextScale(.5)
 term.redirect(mon)
end
local W,H=term.getSize()
local LW=math.min(24,math.floor(W/2))
local top,sel,message,msgColor=1,1,'Pick a title, insert a floppy, add Eyes of Ender.',colors.lightGray
local buyX
local function at(x,y,s,fg,bg)
 term.setCursorPos(x,y)
 if fg then term.setTextColor(fg) end
 if bg then term.setBackgroundColor(bg) end
 term.write(s)
end
local function wrap(text,width)
 local lines,line={},''
 for word in text:gmatch('%S+') do
  if #line+#word+1>width and #line>0 then lines[#lines+1]=line; line=word
  else line=#line>0 and line..' '..word or word end
 end
 if #line>0 then lines[#lines+1]=line end
 return lines
end
local DISK={none='Insert a floppy',record='That is a music disc',blank='Blank floppy ready',ours='Pine disk (will be rewritten)',used='Disk has files: use a blank'}
local function draw()
 term.setBackgroundColor(colors.black); term.clear()
 local title=(' PINE SOFTWARE  %d Eye%s of Ender per title'):format(price,price==1 and '' or 's')
 at(1,1,title..(' '):rep(W-#title),colors.white,colors.purple)
 local rows=H-5
 if sel<top then top=sel elseif sel>=top+rows then top=sel-rows+1 end
 for r=0,rows-1 do
  local it=items[top+r]
  if it then
   local hi=top+r==sel
   local s=' '..it.title
   at(1,3+r,s:sub(1,LW)..(' '):rep(LW-#s),hi and colors.black or colors.white,hi and colors.lime or colors.black)
  end
 end
 local it=items[sel]
 local x=LW+3
 at(x,3,it.title,colors.yellow,colors.black)
 for k,l in ipairs(wrap(it.description or '',W-x)) do
  if 4+k>H-4 then break end
  at(x,4+k,l,colors.white,colors.black)
 end
 local state=diskState()
 local n=eyes()
 at(1,H-2,' Disk: '..DISK[state],(state=='blank' or state=='ours') and colors.lime or colors.orange,colors.black)
 at(1,H-1,(' Eyes of Ender: %d of %d'):format(n,price),n>=price and colors.lime or colors.orange,colors.black)
 local ready=(state=='blank' or state=='ours') and n>=price
 local b=' BUY '
 buyX=W-#b-1
 at(buyX,H-2,b,colors.black,ready and colors.lime or colors.gray)
 at(1,H,' '..message:sub(1,W-1),msgColor,colors.black)
end
local function say(text,c) message,msgColor=text,c or colors.lightGray end

local function buy()
 local item=items[sel]
 local state,path=diskState()
 if state~='blank' and state~='ours' then return say(DISK[state]..'.',colors.orange) end
 if eyes()<price then return say(('Put %d Eye%s of Ender in the payment chest.'):format(price,price==1 and '' or 's'),colors.orange) end
 local paid=move(pay,vaultName,price)
 if paid<price then
  move(vault,payName,paid)
  return say('The vault chest is full or the Eyes moved. Nothing was charged.',colors.red)
 end
 say('Writing '..item.title..'...',colors.yellow); draw()
 local ok,err=pcall(writeDisk,path,item)
 if not ok then
  move(vault,payName,paid)
  return say('Could not write the disk ('..tostring(err)..'). Your Eyes are back in the chest.',colors.red)
 end
 drive.setDiskLabel(item.title)
 chime({{'chime',12},{'chime',16},{'chime',19}})
 drive.ejectDisk()
 say('Enjoy '..item.title..'! At home, put it in a disk drive and restart the computer.',colors.lime)
end

local timer=os.startTimer(1)
while true do
 draw()
 local e,a,b,c=os.pullEvent()
 if e=='monitor_touch' then e='mouse_click' end
 if e=='key' then
  if a==keys.up then sel=math.max(1,sel-1)
  elseif a==keys.down then sel=math.min(#items,sel+1)
  elseif a==keys.enter then buy() end
 elseif e=='mouse_scroll' then sel=math.max(1,math.min(#items,sel+a))
 elseif e=='mouse_click' then
  if c>=3 and c<=H-3 and b<=LW and items[top+c-3] then sel=top+c-3
  elseif c==H-2 and b>=buyX then buy() end
 elseif e=='timer' and a==timer then timer=os.startTimer(1) end
end
