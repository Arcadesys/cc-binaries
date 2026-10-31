local M={}
-- What each host phase means to a player.
M.phases={OPEN='BETTING OPEN',LOCKED='BETTING CLOSED - GATES LOADING',RUNNING="AND THEY'RE OFF",RESULT='RESULT',CANCELLED='RACE CANCELLED - STAKES REFUNDED'}
function M.phase(v)
 local text=v.offline and 'HOUSE OFFLINE - RECONNECTING' or v.paused and 'PAUSED' or M.phases[v.phase] or v.phase or 'CONNECTING'
 if not v.offline and (v.seconds or 0)>0 then text=text..' | '..v.seconds..'s' end
 return ' '..text
end
function M.line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y<1 or y>h then return end
 t.setCursorPos(1,y); t.setTextColor(fg or colors.white); t.setBackgroundColor(bg or colors.black)
 t.write((tostring(text)..string.rep(' ',w)):sub(1,w))
end
function M.clear(t,title)
 require('derby.palette').apply(t)
 t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear()
 M.line(t,1,' '..title,colors.white,colors.blue)
end
function M.button(t,y,label,focused,selected)
 local w=t.getSize(); local bg=focused and colors.white or colors.gray; local fg=focused and colors.black or colors.white
 local prefix=(focused and '> ' or '  ')..(selected and '[X] ' or '[ ] ')
 for row=y,y+2 do M.line(t,row,row==y+1 and prefix..label or '',fg,bg) end
 return {y=y,height=3}
end
function M.card()
 for _,name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name)=='drive' then
   local path=disk.getMountPath(name)
   if path then
    local account
    if fs.exists(path..'/house-card.json') then
     local f=fs.open(path..'/house-card.json','r'); local ok,v=pcall(textutils.unserializeJSON,f.readAll()); f.close()
     if ok and type(v)=='table' then account=v.account end
    end
    return {path=path,drive=name,diskID=disk.getID(name),account=account}
   end
  end
 end
end
function M.target()
 -- A plain monitor cannot show the colour games; prefer an advanced one.
 local monitor=peripheral.find('monitor',function(_,m) return m.isColor() end)
 if monitor then monitor.setTextScale(1); return monitor end
 return term.current()
end
-- Small monitors: use half-size text when the full size cannot fit w x h.
function M.fit(t,w,h)
 if not t.setTextScale then return t end
 t.setTextScale(1)
 local cw,ch=t.getSize()
 if cw<w or ch<h then t.setTextScale(.5) end
 return t
end
function M.usable(t)
 if not t.isColor() then
  t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1)
  t.write('Use an advanced colour computer/monitor.'); return false
 end
 local w,h=t.getSize()
 if w>=39 and h>=19 then return true end
 M.clear(t,'HOUSE'); M.line(t,3,'Display needs at least 39 x 19.'); M.line(t,5,'Resize or use a larger monitor.'); return false
end
return M
