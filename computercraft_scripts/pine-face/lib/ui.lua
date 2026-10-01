local world=require("lib.world")
local ui={}
local C=colors
local seatBg={C.yellow,C.cyan,C.lime,C.red}
local function put(t,x,y,s,fg,bg,width)
  local w,h=t.getSize()
  if y<1 or y>h or x>w then return end
  s=tostring(s);width=math.max(0,math.min(width or #s,w-x+1));s=s:sub(1,width)
  t.setCursorPos(x,y);t.setTextColor(fg);t.setBackgroundColor(bg)
  t.write(s..string.rep(" ",width-#s))
end
ui.put=put
local function center(t,y,s,fg,bg)
  local w=t.getSize();put(t,math.max(1,math.floor((w-#s)/2)+1),y,s,fg,bg)
end
local function buttonsFor(view)
  if not view then return {{"left","\27 TURN"},{"fwd","\24 GO"},{"fire","FIRE"},{"back","\25 BACK"},{"right","TURN \26"},{"menu","MENU"}} end
  if view.overlay then return {{"resume","RESUME"},{"quit","QUIT"}} end
  local host=view.role=="host"
  if view.phase=="play" then
    return {{"left","\27 TURN"},{"fwd","\24 GO"},{"fire","FIRE"},{"back","\25 BACK"},{"right","TURN \26"},{"menu","MENU"}}
  elseif view.phase=="lobby" then
    return host and {{"start","START"},{"help","HELP"},{"quit","QUIT"}} or {{"help","HELP"},{"quit","QUIT"}}
  elseif view.phase=="over" then
    return host and {{"start","NEW MATCH"},{"quit","QUIT"}} or {{"quit","QUIT"}}
  elseif view.phase=="lost" then return {{"retry","RETRY"},{"quit","QUIT"}}
  end
  return {{"quit","QUIT"}}
end
function ui.layout(w,h,view)
  local out={buttons={}}
  if w<39 or h<19 then
    out.small=true;out.buttons[1]={id="quit",label="QUIT",x=1,y=h,w=w,h=1}
    return out
  end
  local bh=h>=22 and 2 or 1
  local labels=buttonsFor(view)
  local cell=math.floor(w/#labels)
  local short={left="\27",fwd="\24",back="\25",right="\26"}
  for i,b in ipairs(labels) do
    local x=(i-1)*cell+1
    local label=cell<9 and short[b[1]] or b[2]
    out.buttons[i]={id=b[1],label=label,x=x,y=h-bh+1,w=i==#labels and w-x+1 or cell,h=bh}
  end
  local radarW=w>=46 and 12 or 0
  out.scene={x=1,y=3,w=w-radarW,h=h-2-bh}
  if radarW>0 then out.radar={x=w-radarW+1,y=3,w=radarW,h=h-2-bh} end
  out.showScene=view~=nil and view.phase=="play" and not view.overlay and view.state~=nil
  return out
end
local function drawButtons(t,buttons)
  for _,b in ipairs(buttons) do
    local hot=b.id=="fire" or b.id=="start" or b.id=="resume" or b.id=="retry"
    local bg=hot and C.orange or C.gray;local fg=hot and C.black or C.white
    for y=b.y,b.y+b.h-1 do put(t,b.x,y,"",fg,bg,b.w) end
    put(t,b.x+math.max(0,math.floor((b.w-#b.label)/2)),b.y+math.floor((b.h-1)/2),b.label,fg,bg,math.min(#b.label,b.w))
  end
end
local function name(view,i)
  local n=view.names and view.names[i] or "P"..i
  if i==view.mySeat then return "YOU" end
  return n
end
local function scoreboard(t,view)
  local w=t.getSize();local cell=math.floor(w/4);local s=view.state
  for i=1,4 do
    local x=(i-1)*cell+1;local p=s and s.players[i]
    local label=string.format("%d %s",i,name(view,i))
    local score=p and tostring(p.score) or ""
    local width=i==4 and w-x+1 or cell
    local text=(" "..label):sub(1,width-#score-1)
    text=text..string.rep(" ",width-#text-#score-1)..score.." "
    local dead=p and not p.alive
    put(t,x,1,text,dead and C.gray or C.black,seatBg[i],width)
  end
end
local arrows={[0]="\26",[1]="\25",[2]="\27",[3]="\24"}
local function radar(t,view,box)
  local s=view.state;local me=s.players[view.mySeat or 1]
  local rw=box.w-1;local rh=math.min(box.h,rw)
  local ox,oz=math.floor(me.x+.5)-math.floor(rw/2),math.floor(me.z+.5)-math.floor(rh/2)
  for row=0,rh-1 do
    local text,fgs,bgs={}, {}, {}
    for col=0,rw-1 do
      local x,z=ox+col,oz+row;local ch=" ";local fg,bg=C.white,C.black
      if x>=1 and z>=1 and x<=s.width and z<=s.height and world.tile(s,x,z)=="#" then bg=C.blue end
      for seat,b in pairs(s.bullets) do if math.floor(b.x+.5)==x and math.floor(b.z+.5)==z then ch="\7";fg=C.white end end
      for i,p in ipairs(s.players) do
        if p.alive and math.floor(p.x+.5)==x and math.floor(p.z+.5)==z then
          if i==view.mySeat then ch=arrows[math.floor(((p.yaw+45)%360)/90)];fg=C.white;bg=C.gray
          else ch=tostring(i);fg=C.black;bg=seatBg[i] end
        end
      end
      text[#text+1]=ch;fgs[#fgs+1]=colors.toBlit(fg);bgs[#bgs+1]=colors.toBlit(bg)
    end
    t.setCursorPos(box.x+1,box.y+row);t.blit(table.concat(text),table.concat(fgs),table.concat(bgs))
  end
  for row=0,box.h-1 do put(t,box.x,box.y+row," ",C.white,C.gray,1) end
  local y=box.y+rh
  if y<=box.y+box.h-1 then put(t,box.x+1,y," RADAR",C.lightGray,C.black,rw) end
  local p=me
  if y+1<=box.y+box.h-1 then put(t,box.x+1,y+1,string.format(" TAGS %d",p.score),C.white,C.black,rw) end
  if y+2<=box.y+box.h-1 then put(t,box.x+1,y+2,string.format(" OUTS %d",p.deaths or 0),C.white,C.black,rw) end
  if y+3<=box.y+box.h-1 then put(t,box.x+1,y+3," WIN AT "..world.WIN,C.lightGray,C.black,rw) end
end
local help={
  "PINE FACE - Smiley tag in a maze.",
  "UP/W go   DOWN/S back",
  "LEFT/A RIGHT/D turn",
  "SPACE fire (one shot in the air)",
  "3 hits tags a Smiley: +1 for you.",
  "Fresh spawns flash white: shielded.",
  "First to "..world.WIN.." tags wins.",
  "TAB scores  P menu  Q quit",
  "Host: face --host   Join: face --join",
}
local function lobby(t,view,top)
  local w=t.getSize()
  put(t,1,top,"",C.black,C.yellow,w);center(t,top,"P I N E   F A C E",C.black,C.yellow)
  local kinds=view.kinds or ""
  for i=1,4 do
    local k=kinds:sub(i,i)
    local who=k=="B" and "BOT" or (view.names and view.names[i] or "?")
    if i==view.mySeat then who=who.." (YOU)" end
    local tag=k=="B" and "computer" or (i==1 and "host" or "player")
    put(t,3,top+1+i,string.format(" P%d ",i),C.black,seatBg[i],4)
    put(t,8,top+1+i,who.."  ",C.white,C.black,w-8)
    put(t,8+#who+2,top+1+i,tag,C.lightGray,C.black,w)
  end
  put(t,2,top+7,view.message or "",C.yellow,C.black,w-2)
  if view.role=="host" and view.online then
    put(t,2,top+8,"Others run: face --join "..(os.getComputerID and os.getComputerID() or ""),C.lightGray,C.black,w-2)
  end
end
local function results(t,view,top)
  local s=view.state;local w=t.getSize()
  local winner=s and s.winner
  put(t,1,top,"",C.black,winner and seatBg[winner] or C.yellow,w)
  center(t,top,winner and (name(view,winner)=="YOU" and "YOU WIN!" or ("P"..winner.." "..name(view,winner).." WINS!")) or "MATCH OVER",
    C.black,winner and seatBg[winner] or C.yellow)
  local order={1,2,3,4}
  table.sort(order,function(a,b) return s.players[a].score>s.players[b].score or
    (s.players[a].score==s.players[b].score and a<b) end)
  for row,i in ipairs(order) do
    local p=s.players[i]
    put(t,3,top+1+row,string.format(" P%d ",i),C.black,seatBg[i],4)
    put(t,8,top+1+row,string.format("%-10s %2d tags %2d outs",name(view,i),p.score,p.deaths or 0),C.white,C.black,w-8)
  end
  if view.phase=="over" then
    put(t,2,top+7,view.role=="host" and "ENTER plays again." or "Waiting for the host...",C.yellow,C.black,w-2)
  end
end
function ui.draw(t,view,layout)
  local w,h=t.getSize()
  if layout.small then
    t.setBackgroundColor(C.black);t.clear()
    put(t,1,1,"PINE FACE",C.black,C.yellow,w)
    put(t,1,2,"Needs 39x19 or larger",C.white,C.black,w)
    drawButtons(t,layout.buttons);return
  end
  local s=view.state
  scoreboard(t,view)
  local me=s and s.players[view.mySeat or 1]
  local status=view.message or ""
  if view.phase=="play" and me then
    local hearts=string.rep("\3",me.alive and me.hp or 0)..string.rep(" ",world.HP-(me.alive and me.hp or 0))
    put(t,1,2," "..hearts.." ",C.red,C.black,world.HP+2)
    if not me.alive then status="TAGGED! Back in "..math.max(1,math.ceil((me.respawn or 0)/10)).."s"
    elseif (me.shield or 0)>0 then status="SHIELDED"
    elseif s.message and s.message~="" then status=s.message end
    put(t,world.HP+3,2,status,(not me.alive) and C.red or C.yellow,C.black,w-world.HP-2)
  elseif view.phase=="joining" or view.phase=="lost" then
    put(t,1,2," "..status,C.yellow,C.black,w)
  end
  local sc=layout.scene;local top=sc.y+1
  if view.overlay=="help" then
    for i,line in ipairs(help) do put(t,2,top+i-1,line,C.white,C.black,w-2) end
  elseif view.overlay=="menu" then
    center(t,top+1,"MENU",C.yellow,C.black)
    center(t,top+3,"The match keeps running!",C.white,C.black)
    center(t,top+4,"RESUME or QUIT",C.white,C.black)
  elseif view.overlay=="scores" and s then results(t,view,top)
  elseif view.phase=="lobby" or view.phase=="joining" then lobby(t,view,top)
  elseif view.phase=="over" and s then results(t,view,top)
  elseif view.phase=="lost" then
    center(t,top+2,"PINE FACE",C.yellow,C.black)
    center(t,top+4,view.message or "Disconnected",C.white,C.black)
  elseif layout.showScene and not me.alive then
    center(t,sc.y+math.floor(sc.h/2),"  TAGGED  ",C.white,C.red)
  end
  if layout.radar and s and view.phase=="play" and not view.overlay then radar(t,view,layout.radar) end
  drawButtons(t,layout.buttons)
  t.setCursorPos(1,h)
end
return ui
