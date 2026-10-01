-- Pixel mascot heads for Pine Shut the Box.
-- Sprites are intentionally tiny: seven cells wide by five high, readable on the
-- minimum 39x19 display and chunky enough to feel native to ComputerCraft.
local M={}

M.list={
 {id='fox',name='FOX',primary=colors.orange,accent=colors.white,sprite={
  'p     p','pp   pp','ppppppp','ppa app',' ppppp ',
 }},
 {id='cat',name='CAT',primary=colors.gray,accent=colors.pink,sprite={
  'pp   pp','ppp ppp','ppppppp','ppk kpp',' ppaap ',
 }},
 {id='bunny',name='BUNNY',primary=colors.lightGray,accent=colors.pink,sprite={
  ' pp pp ',' pp pp ','ppppppp','ppk kpp',' ppaap ',
 }},
 {id='wolf',name='WOLF',primary=colors.lightBlue,accent=colors.white,sprite={
  'pp   pp','ppp ppp','ppppppp','ppk kpp',' ppaap ',
 }},
 {id='raccoon',name='RACCOON',primary=colors.gray,accent=colors.lightGray,sprite={
  'pp   pp','ppppppp','paa aap','pkk kkp',' ppaap ',
 }},
 {id='bear',name='BEAR',primary=colors.brown,accent=colors.orange,sprite={
  'pp   pp','ppppppp','ppppppp','ppk kpp',' ppaap ',
 }},
 {id='deer',name='DEER',primary=colors.brown,accent=colors.white,sprite={
  'p p p p',' pp pp ','ppppppp','ppk kpp',' ppaap ',
 }},
 {id='otter',name='OTTER',primary=colors.brown,accent=colors.lightGray,sprite={
  ' pp pp ','ppppppp','ppppppp','ppk kpp',' ppaap ',
 }},
}

function M.get(i)
 if type(i)=='table' then return i end
 if not i then return nil end
 return M.list[(i-1)%#M.list+1]
end

local function fill(t,x,y,w,h,bg)
 t.setBackgroundColor(bg)
 for r=0,h-1 do t.setCursorPos(x,y+r); t.write(string.rep(' ',w)) end
end

function M.draw(t,avatar,x,y,ready,phase,label)
 local a=M.get(avatar); if not a then return end
 local w,h=t.getSize()
 if x+8>w or y+6>h then return end
 local bob=ready and ((phase or 0)%2) or 0
 fill(t,x,y,9,7,colors.black)
 t.setTextColor(colors.lightGray); t.setBackgroundColor(colors.black)
 t.setCursorPos(x,y); t.write(('+%s+'):format(string.rep('-',7)))
 for r,row in ipairs(a.sprite) do
  t.setCursorPos(x,y+r)
  t.setBackgroundColor(colors.black); t.write('|')
  for c=1,7 do
   local ch=row:sub(c,c)
   local col=colors.black
   if ch=='p' then col=a.primary elseif ch=='a' then col=a.accent elseif ch=='k' then col=colors.black elseif ch=='w' then col=colors.white end
   t.setBackgroundColor(col); t.write(' ')
  end
  t.setBackgroundColor(colors.black); t.setTextColor(colors.lightGray); t.write('|')
 end
 t.setCursorPos(x,y+6); t.setBackgroundColor(colors.black); t.setTextColor(ready and colors.yellow or colors.lightGray)
 local text=ready and ' READY ' or (' '..a.name..' ')
 if #text>7 then text=text:sub(1,7) end
 t.write(('|%-7s|'):format(text))
 if ready and bob==1 and y+7<=h then
  t.setCursorPos(x+2,y+6); t.setTextColor(colors.black); t.setBackgroundColor(colors.yellow); t.write(' ROLL ')
 end
end

return M
