local world=require("lib.world")
local ui={}
local function put(t,x,y,s,fg,bg,width)
  local w,h=t.getSize()
  if y<1 or y>h or x>w then return end
  width=math.max(0,math.min(width or #s,w-x+1));s=tostring(s):sub(1,width)
  t.setCursorPos(x,y);t.setTextColor(fg);t.setBackgroundColor(bg)
  t.write(s..string.rep(" ",width-#s))
end
function ui.layout(w,h,phase)
  local out={}
  if w<39 or h<19 then
    out.small=true;out[1]={id="quit",label="QUIT",x=1,y=math.max(1,h),w=w,h=1}
    return out
  end
  local rowH=h>=25 and 3 or 2
  local cell=math.floor(w/4)
  local labels
  if phase=="won" or phase=="lost" then
    labels={{"new","NEW GAME"},{"quit","QUIT"}}
  elseif phase=="menu" or phase=="help" then
    labels={{"resume","RESUME"},{"new","NEW GAME"},{"quit","QUIT"}}
  else
    labels={
      {"forward","FORWARD"},{"backward","BACKWARD"},
      {"turn_left","TURN","LEFT"},{"turn_right","TURN","RIGHT"},
      {"attack","ATTACK"},{"heal","EAT"},{"map","MAP"},{"help","HELP"},
      {"wait","WAIT"},{"menu","MENU"},{"quit","QUIT"},
    }
  end
  local start=h-rowH*3+1
  for i,b in ipairs(labels) do
    local row=math.floor((i-1)/4);local col=(i-1)%4
    local x=col*cell+1;local width=col==3 and w-x+1 or cell
    out[#out+1]={id=b[1],label=b[2],label2=b[3],x=x,y=start+row*rowH,w=width,h=rowH}
  end
  out.rowH=rowH
  return out
end
local function drawButtons(t,buttons)
  for _,b in ipairs(buttons) do
    local bg=(b.id=="attack" or b.id=="resume" or b.id=="new") and colors.lime or colors.gray
    local fg=bg==colors.lime and colors.black or colors.white
    for y=b.y,b.y+b.h-1 do put(t,b.x,y,"",fg,bg,b.w) end
    local x=b.x+math.max(0,math.floor((b.w-#b.label)/2))
    put(t,x,b.y,b.label,fg,bg,#b.label)
    if b.label2 then
      local x2=b.x+math.max(0,math.floor((b.w-#b.label2)/2))
      put(t,x2,b.y+1,b.label2,fg,bg,#b.label2)
    end
  end
end
function ui.draw(t,view,buttons)
  local w,h=t.getSize();local s=view.state;local p=s.player
  if buttons.small then
    t.setBackgroundColor(colors.black);t.setTextColor(colors.white);t.clear()
    put(t,1,1,"PINE DUNGEON",colors.black,colors.yellow,w)
    put(t,1,2,"RESIZE TO 39x19",colors.white,colors.black,w)
    put(t,1,3,"OR PRESS Q TO QUIT",colors.white,colors.black,w)
    drawButtons(t,buttons);return
  end
  local boss=world.boss(s)
  if boss and s.phase=="play" then
    local max=boss.maxHp or world.kinds.W.hp;local cells=10
    local full=math.max(0,math.ceil(boss.hp/max*cells))
    local bar=string.rep("#",full)..string.rep("-",cells-full)
    put(t,1,1,string.format("WARDEN [%s] %d/%d  FL %d/3",bar,boss.hp,max,s.floor),
      colors.white,boss.charging and colors.orange or colors.red,w)
  else
    put(t,1,1,"PINE DUNGEON | FLOOR "..s.floor.."/3 | "..string.upper(s.phase),colors.black,colors.yellow,w)
  end
  put(t,1,2,string.format("HEARTS %d/%d STEAK %d EMERALDS %d T%d",
    p.hp,p.maxHp,p.potions,p.gold,s.turn),colors.white,colors.black,w)
  put(t,1,3,s.message,boss and boss.charging and colors.orange or colors.yellow,colors.black,w)
  local sceneBottom=h-buttons.rowH*3
  if view.overlay=="help" then
    local lines={"UP/W forward  DOWN/S backward",
      "LEFT/A turn left  RIGHT/D turn right",
      "SPACE attack ahead  |  . wait",
      "E/H: eat steak  |  TAB: map",
      "F1: help  |  P: menu  |  Q: quit",
      "Move into a monster to strike it.",
      "@ YOU  z zombie  k skeleton  W Warden",
      "% STEAK  $ EMERALD  > LADDER  O PORTAL",
      "Slay the Warden, enter the portal."}
    for i,line in ipairs(lines) do put(t,1,3+i,line,colors.white,colors.black,w) end
  elseif view.overlay=="menu" then
    put(t,1,5,"PAUSED",colors.yellow,colors.black,w)
    put(t,1,7,"RESUME, NEW GAME, or QUIT.",colors.white,colors.black,w)
  elseif s.phase=="won" or s.phase=="lost" then
    put(t,1,5,s.phase=="won" and "YOU BEAT THE DUNGEON!" or "YOU DIED!",colors.yellow,colors.black,w)
    put(t,1,7,string.format("FLOOR %d  EMERALDS %d  TURNS %d",s.floor,p.gold,s.turn),colors.white,colors.black,w)
  elseif view.map then
    put(t,1,4,"MAP: N UP  E RIGHT  @ YOU",colors.yellow,colors.black,w)
    for z=1,s.height do
      if z+4<=sceneBottom then
        local line={}
        for x=1,s.width do line[#line+1]=world.symbol(s,x,z) end
        put(t,2,z+4,table.concat(line),colors.white,colors.black,s.width)
      end
    end
    put(t,16,6,"z k W MOBS",colors.white,colors.black,w-15)
    put(t,16,7,"% STEAK",colors.white,colors.black,w-15)
    put(t,16,8,"$ EMERALD",colors.white,colors.black,w-15)
    put(t,16,9,"> LADDER O PORTAL",colors.white,colors.black,w-15)
  else
    local panelX=w-12
    put(t,panelX,4,"LOOK "..string.upper(p.facing).." N^",colors.yellow,colors.black,13)
    for z=1,s.height do
      local line={}
      for x=1,s.width do line[#line+1]=world.symbol(s,x,z) end
      put(t,panelX,4+z,table.concat(line),colors.white,colors.black,13)
    end
  end
  drawButtons(t,buttons)
  t.setCursorPos(1,h)
end
return ui
