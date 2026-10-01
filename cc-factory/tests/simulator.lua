-- Deterministic CC:Tweaked API double. It enforces physical pose, fuel,
-- inventory capacity, receivers, and failures independently of miner state.
local M = {}
local function copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}; for k,v in pairs(t) do out[k] = copy(v) end; return out
end
local function serialize(v)
  if type(v)=='table' then
    local out={'{'}; for k,x in pairs(v) do out[#out+1]='['..serialize(k)..']='..serialize(x)..',' end
    out[#out+1]='}'; return table.concat(out)
  elseif type(v)=='string' then return string.format('%q',v)
  else return tostring(v) end
end
function M.new(opts)
  opts=opts or {}
  local env=opts.env or _ENV
  local w={pose=copy(opts.pose or {x=0,y=0,z=0,facing=opts.facing or 'north'}),blocks=opts.blocks or {},slots={},selected=1,
    fuel=opts.fuel or 10000, files=opts.files or {},calls={},fail={},drops=0,defaultBlock=opts.defaultBlock or 'minecraft:stone'}
  local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
  local headings={'north','east','south','west'}
  function w.key(p) return p.x..','..p.y..','..p.z end
  function w.target(dir)
    local p=copy(w.pose)
    if dir=='up' then p.y=p.y+1 elseif dir=='down' then p.y=p.y-1
    elseif dir=='back' then local v=vectors[p.facing]; p.x=p.x-v[1];p.z=p.z-v[2]
    else local v=vectors[p.facing];p.x=p.x+v[1];p.z=p.z+v[2] end
    return p
  end
  function w.block(p) local b=w.blocks[w.key(p)]; if b==nil then return w.defaultBlock end; return b end
  function w.set(p,b) w.blocks[w.key(p)]=b end
  function w.record(name,p)
    if w.beforeMutation then w.beforeMutation(name,p or w.pose,w) end
    w.calls[#w.calls+1]={name=name,pose=copy(w.pose),target=copy(p)}
    if w.fail[name] then
      if type(w.fail[name])=='function' then return w.fail[name](w) end
      return false,'Injected '..name..' failure'
    end
    return true
  end
  function w.add(name,count)
    for i=1,16 do local s=w.slots[i]; if s and s.name==name and s.count<64 then local n=math.min(count,64-s.count);s.count=s.count+n;count=count-n end end
    for i=1,16 do if not w.slots[i] and count>0 then local n=math.min(count,64);w.slots[i]={name=name,count=n};count=count-n end end
    return count==0
  end
  w.set(w.pose,false)
  local t={}
  for _,dir in ipairs({'front','up','down'}) do
    local suffix=dir=='front' and '' or dir=='up' and 'Up' or 'Down'
    t['inspect'..suffix]=function() local b=w.block(w.target(dir));if b then return true,{name=type(b)=='table' and b.name or b,tags=type(b)=='table' and b.tags or {}} end; return false,'No block to inspect' end
    t['detect'..suffix]=function() return not not w.block(w.target(dir)) end
    t['dig'..suffix]=function()
      local p=w.target(dir); local ok,e=w.record('dig'..suffix,p);if not ok then return ok,e end
      local b=w.block(p);if not b then return false,'Nothing to dig' end
      local name=type(b)=='table' and b.name or b
      if name=='minecraft:bedrock' then return false,'Unbreakable' end
      if not w.add(name,1) then return false,'No inventory space' end
      w.set(p,false);return true
    end
    t['place'..suffix]=function()
      local p=w.target(dir);local ok,e=w.record('place'..suffix,p);if not ok then return ok,e end
      local s=w.slots[w.selected];if not s then return false,'No items to place' end
      if w.block(p) then return false,'Position occupied' end
      if s.name=='minecraft:torch' then local floor={x=p.x,y=p.y-1,z=p.z};if not w.block(floor) then return false,'Torch has no solid support' end end
      w.set(p,s.name);s.count=s.count-1;if s.count==0 then w.slots[w.selected]=nil end;return true
    end
    t['drop'..suffix]=function(n)
      local p=w.target(dir);local ok,e=w.record('drop'..suffix,p);if not ok then return ok,e end
      local b=w.block(p);local s=w.slots[w.selected];if not s then return false,'No items' end
      if type(b)~='table' or not b.capacity then w.drops=w.drops+s.count;w.slots[w.selected]=nil;return true end
      local accepted=math.min(n or s.count,s.count,b.capacity,b.maxTransfer or 64);if accepted==0 then return false,'No space' end
      b.capacity=b.capacity-accepted;b.received=(b.received or 0)+accepted;b.items=b.items or {};b.items[s.name]=(b.items[s.name] or 0)+accepted;s.count=s.count-accepted;if s.count==0 then w.slots[w.selected]=nil end;return true
    end
    t['suck'..suffix]=function(n)
      if w.beforeMutation then local ok,err=w.record('suck'..suffix,w.target(dir));if not ok then return ok,err end end
      local b=w.block(w.target(dir));if type(b)~='table' then return false,'No inventory' end
      for _,name in ipairs({'minecraft:coal','minecraft:torch','minecraft:cobblestone'}) do
        local count=(b.items or {})[name] or 0;local slot=w.slots[w.selected]
        if count>0 and (not slot or slot.name==name) then
          local used=math.min(n or 64,count,64-(slot and slot.count or 0));if used>0 then b.items[name]=count-used;w.slots[w.selected]={name=name,count=(slot and slot.count or 0)+used};return true end
        end
      end;return false,'No items to take'
    end
    t['attack'..suffix]=function() error('Safety violation: attack called') end
  end
  for _,dir in ipairs({'forward','back','up','down'}) do
    t[dir]=function()
      local p=w.target(dir=='forward' and 'front' or dir);local ok,e=w.record(dir,p);if not ok then return ok,e end
      if w.block(p) then return false,'Movement obstructed' end
      if w.fuel~='unlimited' then if w.fuel<=0 then return false,'Out of fuel' end;w.fuel=w.fuel-1 end
      w.pose=p;if w.afterAction then w.afterAction(dir,w) end;return true
    end
  end
  for _,side in ipairs({'Left','Right'}) do
    t['turn'..side]=function()
      local ok,e=w.record('turn'..side);if not ok then return ok,e end
      for i,h in ipairs(headings) do if h==w.pose.facing then w.pose.facing=headings[(i-1+(side=='Right' and 1 or 3))%4+1];break end end;if w.afterAction then w.afterAction('turn'..side,w) end;return true
    end
  end
  t.getFuelLevel=function() return w.fuel end;t.getFuelLimit=function() return 100000 end
  t.select=function(i) w.selected=i;return true end;t.getSelectedSlot=function() return w.selected end
  t.getItemCount=function(i) local s=w.slots[i or w.selected];return s and s.count or 0 end
  t.getItemSpace=function(i) return 64-t.getItemCount(i) end
  t.getItemDetail=function(i) return copy(w.slots[i or w.selected]) end
  t.refuel=function(n)
    if n~=0 and w.beforeMutation then local ok,err=w.record('refuel',w.pose);if not ok then return ok,err end end
    local s=w.slots[w.selected];if not s or s.name~='minecraft:coal' then return false,'Not fuel' end
    if n==0 then return true end
    local used=math.min(n or s.count,s.count);s.count=s.count-used;if s.count==0 then w.slots[w.selected]=nil end
    if w.fuel~='unlimited' then w.fuel=w.fuel+80*used end;return true
  end
  env.turtle=t
  env.textutils=env.textutils or {serialize=serialize,unserialize=function(s) local f=load('return '..s);return f and f() end}
  env.fs={exists=function(p) return w.files[p]~=nil end,delete=function(p) w.files[p]=nil end,
    move=function(a,b) if w.fsFail=='move' then error('Injected rename failure') end;assert(w.files[a],'missing file');w.files[b]=w.files[a];w.files[a]=nil end,
    makeDir=function() end,getDir=function(p) return p:match('^(.*)/') or '' end,
    open=function(p,mode)
      if w.fsFail=='open' then return nil end
      if mode=='r' then if w.files[p]==nil then return nil end;return {readAll=function() return w.fsFail=='readback' and 'CORRUPT READBACK' or w.files[p] end,close=function() end} end
      w.files[p]='';return {write=function(s) if w.fsFail=='write' then error('Injected write failure') end;w.files[p]=w.files[p]..s end,writeLine=function(s) w.files[p]=w.files[p]..s..'\n' end,close=function() end,flush=function() end}
    end}
  env.peripheral={isPresent=function(side) local b=w.block(w.target((side=='top' or side=='up') and 'up' or (side=='bottom' or side=='down') and 'down' or 'front'));return type(b)=='table' and b.capacity~=nil end,
    hasType=function(side,kind) return env.peripheral.isPresent(side) and kind=='inventory' end,
    getType=function(side) if env.peripheral.isPresent(side) then return 'minecraft:chest','inventory' end end,
    wrap=function(side) if env.peripheral.isPresent(side) then return {list=function() local b=w.block(w.target(side=='up' and 'up' or side=='down' and 'down' or 'front'));local list={};for name,count in pairs(b.items or {}) do list[#list+1]={name=name,count=count} end;return list end,size=function() return 27 end} end end}
  env.sleep=function() end
  w.env=env;w.turtle=t
  return w
end
M.copy=copy
return M
