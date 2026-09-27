-- Shared terrain access for the canonical material-tagged course mesh.
local course = {hole=require("courses.pebble_beach.hole_07")}

-- Build a small coarse lookup once. Sampling in the shot loop checks only nearby faces.
local cellSize = 8
local bins = {}
local bounds = course.hole.bounds
local function binKey(ix, iz) return ix .. ":" .. iz end
for _, tri in ipairs(course.hole.triangles) do
  local minX=math.min(tri.a.x,tri.b.x,tri.c.x)
  local maxX=math.max(tri.a.x,tri.b.x,tri.c.x)
  local minZ=math.min(tri.a.z,tri.b.z,tri.c.z)
  local maxZ=math.max(tri.a.z,tri.b.z,tri.c.z)
  for ix=math.floor(minX/cellSize),math.floor(maxX/cellSize) do
    for iz=math.floor(minZ/cellSize),math.floor(maxZ/cellSize) do
      local key=binKey(ix,iz)
      bins[key]=bins[key] or {}
      table.insert(bins[key],tri)
    end
  end
end

local function barycentric(x, z, a, b, c)
  local den = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
  if math.abs(den) < 1e-10 then return nil end
  local u = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
  local v = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
  local w = 1 - u - v
  local eps = 1e-8
  if u < -eps or v < -eps or w < -eps then return nil end
  return u, v, w
end

function course.sample(x, z)
  if x < bounds.minX or x > bounds.maxX or z < bounds.minZ or z > bounds.maxZ then return nil end
  for _, tri in ipairs(bins[binKey(math.floor(x/cellSize),math.floor(z/cellSize))] or {}) do
    local u, v, w = barycentric(x, z, tri.a, tri.b, tri.c)
    if u then
      local a, b, c = tri.a, tri.b, tri.c
      local height = u * a.y + v * b.y + w * c.y
      -- The world uses x/z as the ground plane and y up. Orient the normal upward.
      local ux, uy, uz = b.x-a.x, b.y-a.y, b.z-a.z
      local vx, vy, vz = c.x-a.x, c.y-a.y, c.z-a.z
      local nx, ny, nz = uy*vz-uz*vy, uz*vx-ux*vz, ux*vy-uy*vx
      if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
      local length = math.sqrt(nx*nx + ny*ny + nz*nz)
      if length < 1e-10 then return nil end
      return {height=height, nx=nx/length, ny=ny/length, nz=nz/length, material=tri.material}
    end
  end
  return nil
end

return course
