-- Full campaigns through the real input dispatcher. No test-only state mutation.
local App=require("lib.app")
local ui=require("lib.ui")
local runtime={}
local moves={{1,0,"east"},{0,1,"south"},{-1,0,"west"},{0,-1,"north"}}
local keyNames={forward="up",backward="down",turn_left="left",turn_right="right",
  attack="space",heal="h",map="tab",help="f1",menu="p",quit="q"}
local facingIndex={north=1,east=2,south=3,west=4}
local function relativeAction(s,direction)
  if not direction then return nil end
  local difference=(facingIndex[direction]-facingIndex[s.player.facing])%4
  return ({[0]="forward",[1]="turn_right",[2]="backward",[3]="turn_left"})[difference]
end
local function route(s)
  local q={{s.player.x,s.player.z,nil}};local seen={[s.player.x..":"..s.player.z]=true};local head=1
  while q[head] do
    local here=q[head];head=head+1
    if here[1]==s.exit.x and here[2]==s.exit.z then return here[3] end
    for _,d in ipairs(moves) do
      local x,z=here[1]+d[1],here[2]+d[2];local k=x..":"..z
      if not seen[k] and z>=1 and z<=s.height and x>=1 and x<=s.width
        and s.tiles[z][x]~="#" then
        seen[k]=true;q[#q+1]={x,z,here[3] or d[3]}
      end
    end
  end
end
function runtime.run(mode)
  local name=mode=="monitor" and "dungeon_test" or nil
  if name then assert(periphemu.create(name,"monitor")) end
  local original=term.current();local target=name and peripheral.wrap(name) or original
  local palette={};for i=0,15 do palette[2^i]={original.getPaletteColor(2^i)} end
  local warm=1;local warmActions={"map","map","help","resume","menu","resume"}
  local done=false;local final;local actions=0;local frames={};local stage=0;local resized=false;local detached=false
  local frameW,frameH
  local function queue(action,app)
    local currentName=detached and nil or name
    if currentName then
      local buttons=ui.layout(frameW,frameH,app.overlay or app.state.phase)
      local requested=action
      if action=="resume" then requested="resume" end
      local b
      for _,v in ipairs(buttons) do if v.id==requested then b=v;break end end
      assert(b,"missing tap target "..action)
      os.queueEvent("monitor_touch",currentName,b.x+math.floor(b.w/2),b.y+math.floor(b.h/2))
    else
      local key=action=="resume" and (app.overlay=="help" and "f1" or "p") or keyNames[action]
      assert(key,"missing key "..action)
      os.queueEvent("key",assert(keys[key]),false)
    end
    actions=actions+1
  end
  local options={terminal=not name,monitor=name}
  options.record=function(kind,data,app)
    if kind~="frame" then return end
    frameW,frameH=data.width,data.height
    frames[#frames+1]=data.renderMs
    assert(#frames<500,"runaway dungeon render loop")
    if warm<=#warmActions then
      queue(warmActions[warm],app);warm=warm+1;return
    end
    if app.state.phase=="play" then
      assert(app.state.turn<300,"turn budget")
      local action=app.state.player.hp<=5 and app.state.player.potions>0 and "heal"
        or relativeAction(app.state,route(app.state))
      assert(action,"route to stairs")
      queue(action,app)
    elseif app.state.phase=="won" then
      if name and stage==0 then
        stage=1;target.setTextScale(3)
      elseif name and stage==1 and app.small then
        resized=true;stage=2;target.setTextScale(.5)
      elseif name and stage==2 and not app.small then
        stage=3;queue("resume",app)
      elseif name and stage==3 and not app.overlay then
        stage=4;assert(periphemu.remove(name));detached=true
      elseif name and stage==4 and app.overlay then
        stage=5;queue("resume",app)
      else queue("quit",app) end
    else error("campaign lost on floor "..app.state.floor.." turn "..app.state.turn) end
  end
  parallel.waitForAll(function() final=App.run(options);done=true end,function()
    local start=os.clock()
    while not done do
      sleep(.05)
      if os.clock()-start>60 then os.queueEvent("terminate");return end
    end
  end)
  assert(final.state.phase=="won" and final.state.floor==3,
    "complete campaign: "..mode.." phase="..final.state.phase.." floor="..final.state.floor..
    " turn="..final.state.turn.." warm="..warm.." stage="..stage.." actions="..actions)
  assert(final.state.player.hp>0 and final.state.turn>0,"alive victory")
  assert(term.current()==original,"terminal redirect restored")
  for c,rgb in pairs(palette) do
    local r,g,b=original.getPaletteColor(c)
    assert(math.abs(r-rgb[1])<1e-6 and math.abs(g-rgb[2])<1e-6 and math.abs(b-rgb[3])<1e-6,
      "palette restored")
  end
  if name then assert(resized and detached,"monitor recovery tested") end
  print("PASS runtime "..mode.." three floors, "..final.state.turn.." turns, "..actions..
    " actions, HP "..final.state.player.hp..", gold "..final.state.player.gold)
  return {mode=mode,turns=final.state.turn,actions=actions,hp=final.state.player.hp,
    gold=final.state.player.gold,frames=frames,resized=resized,detached=detached}
end
return runtime
