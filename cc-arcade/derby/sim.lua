-- Pure, versioned simulation. Distances and time do not depend on the renderer.
local M = { version = 1, dt = .1, distance = 450 }
M.horses = {
 {name="COPPER COMET", style="STEADY", color=2},
 {name="LEDGER LIZARD", style="CLOSER", color=256},
 {name="NEON PANIC", style="CHAOS", color=1024},
}
local function random(s)
 s.rng = (s.rng * 48271) % 2147483647
 return s.rng / 2147483647
end
function M.new(seed)
 local s={seed=seed, rng=math.floor(seed)%2147483646+1, tick=0, horses={}, order={}, version=M.version}
 for _=1,8 do random(s) end
 for i=1,3 do s.horses[i]={distance=0, ability=.88+random(s)*.24, surge=0} end
 return s
end
function M.step(s)
 if #s.order == 3 then return s end
 s.tick=s.tick+1
 local crossing={}
 for i,h in ipairs(s.horses) do
  if not h.finish then
   local p=h.distance/M.distance
   local r=random(s)
   local speed
   if i==1 then speed=.95+r*.12
   elseif i==2 then speed=.82+.36*p+(r-.5)*.2
   else speed=.99+(r-.5)*1.6; if r>.97 then speed=2.5 elseif r<.04 then speed=0 end end
   if s.tick%25==1 then h.surge=(random(s)-.5)*.25 end
   speed=math.max(.03,(speed+h.surge)*h.ability)
   local previous=h.distance
   h.distance=previous+speed
   if h.distance>=M.distance then
    h.finish=(s.tick-1+(M.distance-previous)/speed)*M.dt
    crossing[#crossing+1]={id=i,time=h.finish,tie=random(s)}
   end
  end
 end
 table.sort(crossing,function(a,b) if a.time==b.time then return a.tie<b.tie end return a.time<b.time end)
 for _,c in ipairs(crossing) do s.order[#s.order+1]=c.id end
 return s
end
function M.run(seed)
 local s=M.new(seed)
 while #s.order<3 do M.step(s) end
 return s
end
function M.positions(s)
 local out={}
 for i,h in ipairs(s.horses) do out[i]=math.min(1,h.distance/M.distance) end
 return out
end
return M
