local course = require("lib.course")
local hole = course.hole
local function check(ok, message) if not ok then error(message, 2) end end
check(hole.par == 3 and hole.listed_yards == 107 and hole.tee_set == "Blue", "scorecard metadata")
check(hole.tee.x == 0 and hole.tee.z == 0 and hole.cup.x == 107 and hole.cup.z == 0, "coordinate contract")
check(#hole.triangles > 100, "terrain mesh exists")
local allowed = {rough=true, fairway=true, green=true, bunker=true}
for i, tri in ipairs(hole.triangles) do
  check(allowed[tri.material], "unknown material at triangle " .. i)
  local ax,az=tri.b.x-tri.a.x,tri.b.z-tri.a.z
  local bx,bz=tri.c.x-tri.a.x,tri.c.z-tri.a.z
  check(ax*bz-az*bx < -1e-8, "triangle winding must face upward for rendering " .. i)
  for _,p in ipairs({tri.a,tri.b,tri.c}) do
    check(math.abs(p.z)<=22-14*p.x/107+1e-8, "terrain triangle extends over the ocean")
  end
end
local tee = course.sample(hole.tee.x,hole.tee.z)
local cup = course.sample(hole.cup.x,hole.cup.z)
check(tee and tee.material ~= "bunker" and tee.height > 10, "tee is supported and elevated")
check(cup and cup.material == "green", "cup is on the green")
check(course.sample(30,0).material == "fairway", "fairway uses its tagged support triangles")
check(course.sample(96,-5).material == "bunker", "bunker uses its tagged support triangles")
local nn=math.sqrt(cup.nx^2+cup.ny^2+cup.nz^2)
check(math.abs(nn-1)<1e-6 and cup.ny>0, "sample normal is normalized and upward")
for _, p in ipairs({{20,23},{60,17},{100,13},{110,11},{116,0},{40,30}}) do
  check(course.sample(p[1],p[2])==nil, "ocean or exterior point has no ground support")
end
local count={}
for _,tri in ipairs(hole.triangles) do count[tri.material]=(count[tri.material] or 0)+1 end
for _,mat in ipairs({"rough","fairway","green","bunker"}) do check((count[mat] or 0)>0,"missing region material: "..mat) end
print("course: ok ("..#hole.triangles.." shoreline-clipped, material-tagged triangles)")
return true
