local M={}
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
 local monitor=peripheral.find('monitor')
 if monitor then monitor.setTextScale(1); return monitor end
 return term.current()
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
