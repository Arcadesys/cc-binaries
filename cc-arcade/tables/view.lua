-- Draws a table view: {title,status,lines={{text,color}},buttons={{id,label}}}.
-- Seats know nothing about any game; new games need no seat update.
local M={}
local function line(t,y,text,fg,bg)
 local w,h=t.getSize(); if y<1 or y>h then return end
 t.setCursorPos(1,y); t.setTextColor(fg or colors.white); t.setBackgroundColor(bg or colors.black)
 t.write((tostring(text)..string.rep(' ',w)):sub(1,w))
end
-- Buttons stack up from the bottom, three rows each when there is room.
function M.layout(t,view)
 local w,h=t.getSize(); local n=#(view.buttons or {})
 local tall=h-3-n*3>=4; local size=tall and 3 or 1
 local out={}
 for i=1,n do out[i]={y=h-1-(n-i+1)*size+1,height=size} end
 return out,size
end
function M.draw(t,view)
 t.setBackgroundColor(colors.black); t.clear()
 line(t,1,' '..(view.title or 'TABLE'),colors.white,colors.blue)
 line(t,2,' '..(view.status or ''),colors.yellow)
 local boxes=M.layout(t,view)
 local bottom=boxes[1] and boxes[1].y-1 or select(2,t.getSize())-1
 for i,l in ipairs(view.lines or {}) do
  if 3+i>bottom then break end
  if type(l)=='table' then line(t,3+i,' '..l[1],l[2]) else line(t,3+i,' '..l) end
 end
 for i,b in ipairs(view.buttons or {}) do
  local box=boxes[i]
  for row=box.y,box.y+box.height-1 do
   local label=row==box.y+math.floor(box.height/2) and ' ['..i..'] '..b.label or ''
   line(t,row,label,colors.black,b.color or colors.lime)
  end
 end
 local _,h=t.getSize(); line(t,h,' '..(view.footer or ''),colors.lightGray)
end
-- Which button a click/touch at row y lands on.
function M.hit(t,view,y)
 for i,box in ipairs(M.layout(t,view)) do
  if y>=box.y and y<box.y+box.height then return view.buttons[i] end
 end
end
return M
