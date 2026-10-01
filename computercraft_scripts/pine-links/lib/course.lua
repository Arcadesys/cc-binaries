-- Rogers Bark Municipal Golf: Marovitz-inspired Hole 3, ported from furball-simulator
-- src/sports/golf/course.ts. Authored mechanics study, NOT survey geometry.
-- Metres: tee origin, +Z downrange, +X right, +Y up. Pine3D draws furball (x, z) at Pine (X=z, Z=x).
local course = {}

course.hole = {number = 3, par = 3, length = 162.7632, greenRadiusX = 11, greenRadiusZ = 13, cupRadius = 0.3,
  name = "Marovitz-inspired Hole 3", club = "Rogers Bark Municipal Golf",
  tee = {x = 0, y = 0, z = 0}}
course.cup = {x = 0, z = course.hole.length}
course.hole.cup = {x = course.cup.x, y = 0, z = course.cup.z}
course.bounds = {halfWidth = 38, near = -15, far = 205}
course.bunkers = {
  {x = -12, z = 151, rx = 5.5, rz = 9},
  {x = 12, z = 165, rx = 5, rz = 8},
}
course.trees = {}
for i = 0, 10 do
  course.trees[#course.trees + 1] = {x = -23 - (i % 3) * 2, z = 22 + i * 14, radius = 0.85}
  course.trees[#course.trees + 1] = {x = 23 + (i % 2) * 3, z = 28 + i * 14, radius = 0.85}
end

function course.inEllipse(x, z, cx, cz, rx, rz)
  return ((x - cx) / rx) ^ 2 + ((z - cz) / rz) ^ 2 <= 1
end

function course.lieAt(x, z)
  for _, b in ipairs(course.bunkers) do
    if course.inEllipse(x, z, b.x, b.z, b.rx, b.rz) then return "sand" end
  end
  if course.inEllipse(x, z, course.cup.x, course.cup.z, course.hole.greenRadiusX, course.hole.greenRadiusZ) then return "green" end
  if math.abs(x) <= 3 and math.abs(z) <= 4 then return "tee" end
  if math.abs(x) <= 12 and z >= 4 and z <= 153 then return "fairway" end
  return "rough"
end

function course.outside(x, z)
  return math.abs(x) > course.bounds.halfWidth or z < course.bounds.near or z > course.bounds.far
end

return course
