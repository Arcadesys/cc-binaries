local ui = {}

local function button(id,label,x,y,w,h)
  return {id=id,label=label,x=x,y=y,w=w,h=h}
end

function ui.layout(w,h,phase,camera)
  local out={rows=3,rowH=h<24 and 2 or 3}
  local rowH=out.rowH
  local cols=4
  local gap=1
  local cellW=math.floor((w-gap*(cols-1))/cols)
  local startY=h-rowH*3+1
  local function add(row,col,id,label,span)
    span=span or 1
    local x=(col-1)*(cellW+gap)+1
    local width=math.min(w-x+1,cellW*span+gap*(span-1))
    out[#out+1]=button(id,label,x,startY+(row-1)*rowH,width,rowH)
  end

  if w<39 or h<19 then
    out.rowH=math.min(rowH,h)
    out[1]=button("quit","QUIT",1,math.max(1,h),w,1)
    out.small=true
    return out
  end

  if phase=="SETUP" then
    add(1,1,"players_down","PLAYERS -",2)
    add(1,3,"players_up","PLAYERS +",2)
    add(2,1,"help","HELP",2)
    add(2,3,"pause","MENU",2)
    add(3,1,"start","START",4)
  elseif phase=="MASCOTS" then
    add(1,1,"mascot_prev","< MASCOT",2)
    add(1,3,"mascot_next","MASCOT >",2)
    add(2,1,"help","HELP",2); add(2,3,"pause","MENU",2)
    add(3,1,"mascot_confirm","LOCK IN",4)
  elseif phase=="RESULT" then
    add(1,1,"select_prev","PLAYER -",2)
    add(1,3,"select_next","PLAYER +",2)
    add(2,1,"view","VIEW",1); add(2,2,"help","HELP",1)
    add(2,3,"pause","MENU",2)
    add(3,1,"continue","CONTINUE",4)
  elseif phase=="FINAL" then
    add(1,1,"select_prev","PLAYER -",2)
    add(1,3,"select_next","PLAYER +",2)
    add(2,1,"view","VIEW",1); add(2,2,"help","HELP",1)
    add(2,3,"pause","MENU",2)
    add(3,1,"restart","NEW GAME",2)
    add(3,3,"quit","QUIT",2)
  elseif phase=="HELP" or phase=="PAUSED" then
    add(1,1,"start","RESUME",2)
    add(1,3,"restart","RESTART",2)
    add(3,1,"quit","QUIT",2); add(3,3,"pause",phase=="PAUSED" and "RESUME" or "MENU",2)
  elseif phase=="SIMULATE" or phase=="PLAYBACK" then
    add(3,1,"skip","SKIP",2); add(3,3,"help","HELP",1); add(3,4,"pause","MENU",1)
  else
    if camera=="score" then
      add(1,1,"select_prev","PLAYER -",2); add(1,3,"select_next","PLAYER +",2)
    else
      add(1,1,"select_position","POSITION",1); add(1,2,"select_aim","AIM",1)
      add(1,3,"select_power","POWER",1); add(1,4,"select_hook","HOOK",1)
    end
    add(2,1,"adjust_down","-",1); add(2,2,"adjust_up","+",1)
    add(2,3,"fine","FINE",1); add(2,4,"view","VIEW",1)
    add(3,1,"roll","ROLL",2); add(3,3,"help","HELP",1); add(3,4,"pause","MENU",1)
  end
  return out
end

local function put(t,x,y,text,fg,bg,width)
  local w,h=t.getSize()
  if y<1 or y>h or x>w then return end
  width=math.max(0,math.min(width or #text,w-x+1))
  text=tostring(text):sub(1,width)
  t.setCursorPos(x,y); t.setTextColor(fg); t.setBackgroundColor(bg)
  t.write(text..string.rep(" ",math.max(0,width-#text)))
end

local function fmtMark(frame)
  if type(frame)~="table" then return "" end
  local marks=frame.marks or {}
  local out={}
  for i=1,#marks do out[#out+1]=tostring(marks[i]) end
  if #out==0 then
    local rolls=frame.rolls or {}
    for i=1,#rolls do out[#out+1]=tostring(rolls[i]) end
  end
  return table.concat(out," ")
end

local pinCoords={
  [1]={8,4},[2]={5,3},[3]={11,3},[4]={3,2},[5]={8,2},[6]={13,2},
  [7]={1,1},[8]={5,1},[9]={9,1},[10]={13,1},
}

function ui.draw(t,view,buttons)
  local w,h=t.getSize()
  local white,black=colors.white,colors.black
  local gold=colors.yellow
  if buttons.small then
    t.setBackgroundColor(black); t.setTextColor(white); t.clear()
    put(t,1,1,"PINE LANES",black,gold,w)
    put(t,1,2,"RESIZE TO 39x19",white,black,w)
    put(t,1,3,"TO PLAY OR QUIT",white,black,w)
    for _,b in ipairs(buttons) do
      for y=b.y,math.min(h,b.y+b.h-1) do put(t,b.x,y,string.rep(" ",b.w),black,colors.lime,b.w) end
      put(t,b.x,b.y,"QUIT",black,colors.lime,b.w)
    end
    t.setCursorPos(1,h)
    return
  end
  local rowH=buttons.rowH or (h<24 and 2 or 3)
  local startY=h-rowH*3+1
  local settings=view.settings or {}
  local phase=view.phase or "AIM"
  local selected=view.selected
  local player=view.currentPlayer or 1
  local frame=view.frame or 1
  local ballNumber=view.ballNumber or 1
  local title
  if phase=="SETUP" then
    title="PINE LANES  |  LOCAL BOWLING"
  elseif phase=="MASCOTS" then
    title=string.format("PINE LANES | PLAYER %d/%d | CHOOSE MASCOT",view.mascotPlayer or 1,view.playerCount or 1)
  elseif phase=="RESULT" and view.rollSummary then
    local rs=view.rollSummary
    title=string.format("PINE LANES | P%d/%d | F%d | B%d",rs.player or player,view.playerCount or 1,rs.frame or frame,rs.ballNumber or ballNumber)
  else
    title=string.format("PINE LANES | P%d/%d | F%d | B%d",
      player,view.playerCount or 1,frame,ballNumber)
  end
  put(t,1,1,title,black,gold,w)

  local position=settings.position or 0
  local aim=settings.aim or 0
  local power=settings.power or 60
  local hook=settings.hook or 0
  local compact=string.format("P%+d A%+d W%d H%+d",position,aim,power,hook)
  local chosen=selected=="aim" and string.format("AIM %+d",aim) or
    selected=="power" and string.format("POWER %d%%",power) or
    selected=="hook" and string.format("HOOK %+d",hook) or string.format("POSITION %+d",position)
  local row2=string.format("%s | %s%s",chosen,compact,view.fine and " | FINE" or "")
  put(t,1,2,row2,white,black,w)

  local pins=(view.snapshot and view.snapshot.pins) or {}
  local pinState={}
  if view.snapshot and type(view.snapshot.pins)=="table" then
    for _,p in ipairs(pins) do pinState[p.id]=p end
    for id=1,10 do if not pinState[id] then pinState[id]={id=id,down=true,absent=true} end end
  else
    for id=1,10 do pinState[id]={id=id,down=false} end
  end
  local standing,down=0,0
  for id=1,10 do if pinState[id] and not pinState[id].down then standing=standing+1 else down=down+1 end end
  local stateLine=string.format("PINS %d UP %d DOWN",standing,down)
  if phase=="SETUP" then
    stateLine=string.format("%d PLAYERS | LEFT/RIGHT OR +/-",view.playerCount or 1)
  elseif phase=="MASCOTS" then
    local ms=require("lib.mascots"); local m=ms.get((view.mascots or {})[view.mascotPlayer or 1] or 1)
    stateLine="MASCOT: "..m.name.." | LEFT/RIGHT TO CHANGE"
  elseif view.message then stateLine=stateLine.." | "..tostring(view.message) end
  put(t,1,3,stateLine,white,black,w)
  if phase=="RESULT" then
    local nextPlayer=#(view.rankings or {})>0 and "FINAL RESULTS" or ("PLAYER "..tostring(view.currentPlayer or player))
    put(t,1,4,"NEXT: "..nextPlayer.." - CONTINUE",gold,black,w)
  elseif phase=="FINAL" then
    put(t,1,4,"NEXT: FINAL RESULTS",gold,black,w)
  elseif view.lastInput then put(t,1,4,"INPUT: "..tostring(view.lastInput),gold,black,w) end
  if buttons.small then
    put(t,1,math.max(1,h-1),"RESIZE: NEED 39 x 19",gold,black,w)
  end

  -- The pin diagram is always numbered. Fallen pins retain their ID with a ! prefix.
  local fullPanel=phase=="HELP" or phase=="PAUSED"
  local panelX=(view.camera=="score" or fullPanel) and w+1 or math.max(1,w-14)
  if view.camera~="score" and not fullPanel then
    put(t,panelX,5,"PINS ! = DOWN",gold,black,w-panelX+1)
    for id=1,10 do
      local c=pinCoords[id]
      local p=pinState[id]
      local label=not p and tostring(id) or (p.down and ("!"..id) or tostring(id))
      put(t,panelX+c[1]-1,5+c[2],label,white,black,math.max(1,w-(panelX+c[1])+2))
    end
  end

  if phase=="HELP" then
    put(t,1,5,"ARROWS: select or adjust | 1-4: setting",white,black,w)
    put(t,1,6,"SPACE: primary | TAB: view | F: fine",white,black,w)
    put(t,1,7,"H: help P: menu S: skip R: restart",white,black,w)
    put(t,1,8,"BACKSPACE: quit from menus",white,black,w)
  elseif phase=="PAUSED" then
    put(t,1,5,"PAUSED | RESUME, RESTART OR QUIT",gold,black,w)
  elseif view.camera=="score" then
    ui.drawScore(t,view,panelX)
  elseif phase=="RESULT" and view.rollSummary then
    local rs=view.rollSummary
    local knocked=rs.knocked or {}
    put(t,1,5,string.format("PLAYER %d  FRAME %d  BALL %d  KNOCKED %d",
      rs.player or player,rs.frame or frame,rs.ballNumber or ballNumber,rs.count or #knocked),gold,black,panelX-1)
    local ids={}
    for i=1,#knocked do ids[#ids+1]=tostring(knocked[i]) end
    put(t,1,6,"PINS: "..(#ids>0 and table.concat(ids,", ") or "none"),white,black,panelX-1)
  elseif phase=="FINAL" then
    put(t,1,5,"FINAL TOTALS",gold,black,panelX-1)
    for i,r in ipairs(view.rankings or {}) do
      put(t,1,5+i,string.format("%d. PLAYER %d  %s",r.place or i,r.player or i,r.total or "-"),white,black,panelX-1)
    end
  end

  for i=1,#buttons do
    local b=buttons[i]
    local label=b.id=="fine" and (view.fine and "FINE ON" or "FINE OFF") or b.label
    local active=false
    if b.id=="select_position" then active=selected=="position"
    elseif b.id=="select_aim" then active=selected=="aim"
    elseif b.id=="select_power" then active=selected=="power"
    elseif b.id=="select_hook" then active=selected=="hook" end
    local fg,bg=active and black or white,active and colors.lime or colors.gray
    if b.id=="roll" or b.id=="start" or b.id=="continue" then fg,bg=black,colors.lime end
    for y=b.y,math.min(h,b.y+b.h-1) do put(t,b.x,y,string.rep(" ",b.w),fg,bg,b.w) end
    put(t,b.x+math.max(0,math.floor((b.w-#label)/2)),b.y+math.floor((b.h-1)/2),label,fg,bg,math.min(#label,b.w))
  end
  t.setCursorPos(1,h)
end

function ui.drawScore(t,view,panelX)
  local w,h=t.getSize()
  local cardWidth=math.max(4,panelX>w and w or panelX-1)
  local player=math.max(1,view.scorePlayer or view.currentPlayer or 1)
  local card=(view.scorecards or {})[player]
  local frames=card and card.frames or {}
  put(t,1,5,string.format("PLAYER %d SCORECARD",player),colors.yellow,colors.black,cardWidth)
  local function group(first,y)
    local header,marks,scores={"FR "},{"R  "},{"S  "}
    for offset=0,4 do
      local n=first+offset
      local f=frames[n] or {}
      header[#header+1]=" "..string.format("%-5s",tostring(n))
      marks[#marks+1]=string.format("%-5.5s",fmtMark(f))
      scores[#scores+1]=" "..string.format("%-5s",f.cumulative and tostring(f.cumulative) or "-")
    end
    put(t,1,y,table.concat(header,""),colors.white,colors.black,cardWidth)
    put(t,1,y+1,marks[1].." "..table.concat(marks," ",2),colors.white,colors.black,cardWidth)
    put(t,1,y+2,table.concat(scores,""),colors.white,colors.black,cardWidth)
  end
  group(1,6); group(6,9)
  local subtotal="SUBTOTAL "..tostring(card and (card.resolvedSubtotal or card.total) or 0)
  if card and card.pending then subtotal=subtotal.." | SCORE PENDING" end
  put(t,1,12,subtotal,colors.yellow,colors.black,cardWidth)
  local totals={"TOTALS"}
  for i,entry in ipairs(view.scorecards or {}) do
    totals[#totals+1]=string.format("P%d:%s",i,entry.total or "-")
  end
  put(t,1,13,table.concat(totals,"  "),colors.white,colors.black,cardWidth)
end

ui.pinCoords=pinCoords
return ui
