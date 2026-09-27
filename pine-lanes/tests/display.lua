local ui=require("lib.ui")
local ids={}
local function check(v,msg) assert(v,msg) end
for _,size in ipairs({{39,19},{51,19},{81,31},{120,40},{24,12},{2,2}}) do
  local w,h=size[1],size[2]
  for _,phase in ipairs({"SETUP","AIM","SIMULATE","PLAYBACK","RESULT","FINAL","HELP","PAUSED","DIAGNOSTIC"}) do
    local bs=ui.layout(w,h,phase,"lane")
    for _,b in ipairs(bs) do
      check(b.x>=1 and b.y>=1,"positive origin")
      check(b.w>=1 and b.h>=1,"positive size")
      check(b.x+b.w-1<=w,"button right edge in bounds "..w.."x"..h.." "..phase.." "..b.id)
      check(b.y+b.h-1<=h,"button bottom edge in bounds "..w.."x"..h.." "..phase.." "..b.id)
      if w>=39 and h>=19 and phase=="AIM" then check(b.h>=2,"accessible target height") end
      ids[b.id]=true
    end
    if w>=39 and h>=19 then check(bs.rowH==2 or bs.rowH==3,"two/three row target sizing") end
  end
end
for _,id in ipairs({"select_position","select_aim","select_power","select_hook","adjust_down","adjust_up","fine","view","roll","help","pause","start","continue","restart","quit"}) do
  check(ids[id],"layout exposes "..id)
end
for _,phase in ipairs({"HELP","PAUSED"}) do
  for _,b in ipairs(ui.layout(39,19,phase,"lane")) do check(b.id~="view","overlay does not promise ignored VIEW action") end
end

local function mockTerm(w,h)
  local rows={}; for y=1,h do rows[y]=string.rep(" ",w) end
  local x,y=1,1
  local t={}
  function t.getSize() return w,h end
  function t.clear() for row=1,h do rows[row]=string.rep(" ",w) end end
  function t.setCursorPos(nx,ny) x,y=nx,ny end
  function t.setTextColor() end
  function t.setBackgroundColor() end
  function t.write(s)
    local row=rows[y]; local left=row:sub(1,x-1); local right=row:sub(x+#s)
    rows[y]=(left..s..right):sub(1,w)
  end
  return t,rows
end
local ui=require("lib.ui")
local term39,rows39=mockTerm(39,19)
local buttons=ui.layout(39,19,"HELP")
ui.draw(term39,{phase="HELP",playerCount=1,currentPlayer=1,frame=1,ballNumber=1,settings={},lastInput="help"},buttons)
check(rows39[5]:find("1%-4: setting")~=nil,"help instructions fit on minimum display")
check(rows39[8]:find("BACKSPACE: quit from menus")~=nil,"complete quit help is visible")
local scoreHelp,scoreHelpRows=mockTerm(39,19)
ui.draw(scoreHelp,{phase="HELP",camera="score",settings={}},ui.layout(39,19,"HELP","score"))
check(scoreHelpRows[5]:find("ARROWS: select or adjust")~=nil,"help remains readable from score view")
local mini,miniRows=mockTerm(24,12)
ui.draw(mini,{phase="AIM",settings={}},ui.layout(24,12,"AIM"))
check(miniRows[1]:find("PINE LANES")~=nil and miniRows[2]:find("39x19")~=nil,"24x12 gets resize prompt and quit")
local tiny,tinyRows=mockTerm(17,6)
ui.draw(tiny,{phase="AIM",settings={}},ui.layout(17,6,"AIM"))
check(tinyRows[2]:find("RESIZE TO 39x19")~=nil,"17x6 prompt fits without overlapping panels")
local frames={}
for n=1,10 do frames[n]={marks={},rolls={},cumulative=nil} end
frames[10].marks={"X","X","X"}
local term51,rows51=mockTerm(51,19)
ui.draw(term51,{phase="AIM",camera="score",playerCount=1,currentPlayer=1,scorePlayer=1,frame=10,ballNumber=3,fine=true,
  settings={position=0,aim=0,power=.75,hook=0},scorecards={{frames=frames,total=300,resolvedSubtotal=300}},rankings={}},ui.layout(51,19,"AIM","score"))
check(rows51[10]:find("X X X")~=nil,"tenth-frame bonus marks remain visible")
check(rows51[2]:find("deg")~=nil,"aim units use readable ASCII text")
check(rows51[16]:find("FINE ON")~=nil,"fine-mode state is visible on the target")
frames[9].marks={"X"}
local pendingTerm,pendingRows=mockTerm(51,19)
ui.draw(pendingTerm,{phase="AIM",camera="score",playerCount=1,currentPlayer=1,scorePlayer=1,frame=9,ballNumber=1,
  settings={},scorecards={{frames=frames,total=240,pending=true}},rankings={}},ui.layout(51,19,"AIM","score"))
check(pendingRows[12]:find("SCORE PENDING")~=nil,"unresolved score is explicit")
local resultTerm,resultRows=mockTerm(39,19)
ui.draw(resultTerm,{phase="RESULT",playerCount=2,currentPlayer=2,frame=3,ballNumber=1,rollSummary={player=1,frame=3,ballNumber=1,count=6,knocked={1}},
  settings={},snapshot={pins={}}},ui.layout(39,19,"RESULT"))
check(resultRows[4]:find("NEXT: PLAYER 2 %- CONTINUE")~=nil,"result identifies next player on minimum display")
local pinModel=require("lib.render")._testPinModel
local function maxAxis(model,axis)
  local high=-math.huge
  for _,poly in ipairs(model) do for n=1,3 do high=math.max(high,poly[axis..n]) end end
  return high
end
check(maxAxis(pinModel(0,math.pi/2),"x")>.60,"fallen pin points +X when angle is zero")
check(maxAxis(pinModel(math.pi/2,math.pi/2),"z")>.60,"fallen pin points +Z at positive quarter turn")
local function span(model,axis)
  local low,high=math.huge,-math.huge
  for _,poly in ipairs(model) do for n=1,3 do
    local v=poly[axis..n]; low=math.min(low,v); high=math.max(high,v)
  end end
  return high-low
end
local ballModel=require("lib.render")._testBallModel()
check(math.abs(span(ballModel,"x")-span(ballModel,"z"))<.03,"ball is round across the stretched lane")
check(math.abs(span(pinModel(),"x")-span(pinModel(),"z"))<.015,"upright pin has a round footprint")
return true
