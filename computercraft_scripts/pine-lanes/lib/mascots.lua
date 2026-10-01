-- Shared Rogers Bark sports mascot roster.
local M={}
M.list={
 {id='fox',name='FOX',primary=colors.orange,accent=colors.white,sprite={'p     p','pp   pp','ppppppp','ppa app',' ppppp '}},
 {id='cat',name='CAT',primary=colors.gray,accent=colors.pink,sprite={'pp   pp','ppp ppp','ppppppp','ppk kpp',' ppaap '}},
 {id='bunny',name='BUNNY',primary=colors.lightGray,accent=colors.pink,sprite={' pp pp ',' pp pp ','ppppppp','ppk kpp',' ppaap '}},
 {id='wolf',name='WOLF',primary=colors.lightBlue,accent=colors.white,sprite={'pp   pp','ppp ppp','ppppppp','ppk kpp',' ppaap '}},
 {id='raccoon',name='RACCOON',primary=colors.gray,accent=colors.lightGray,sprite={'pp   pp','ppppppp','paa aap','pkk kkp',' ppaap '}},
 {id='bear',name='BEAR',primary=colors.brown,accent=colors.orange,sprite={'pp   pp','ppppppp','ppppppp','ppk kpp',' ppaap '}},
 {id='deer',name='DEER',primary=colors.brown,accent=colors.white,sprite={'p p p p',' pp pp ','ppppppp','ppk kpp',' ppaap '}},
 {id='otter',name='OTTER',primary=colors.brown,accent=colors.lightGray,sprite={' pp pp ','ppppppp','ppppppp','ppk kpp',' ppaap '}},
}
function M.get(i) return M.list[((i or 1)-1)%#M.list+1] end
function M.draw(t,index,x,y,label)
 local a=M.get(index); local w,h=t.getSize()
 if x+8>w or y+6>h then return end
 t.setTextColor(colors.lightGray); t.setBackgroundColor(colors.black)
 t.setCursorPos(x,y); t.write('+-------+')
 for r,row in ipairs(a.sprite) do
  t.setCursorPos(x,y+r); t.setBackgroundColor(colors.black); t.write('|')
  for c=1,7 do
   local ch=row:sub(c,c); local col=colors.black
   if ch=='p' then col=a.primary elseif ch=='a' then col=a.accent end
   t.setBackgroundColor(col); t.write(' ')
  end
  t.setBackgroundColor(colors.black); t.setTextColor(colors.lightGray); t.write('|')
 end
 t.setCursorPos(x,y+6); t.setBackgroundColor(colors.black); t.setTextColor(colors.yellow)
 local text=(label or a.name):sub(1,7)
 t.write(('|%-7s|'):format(text))
end
return M
