-- "3D Pipes"-style screensaver (ComputerCraft:Tweaked)
-- Pseudo-3D pipe trail projected onto the terminal.

local w, h = term.getSize()

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function project(p)
	-- Simple isometric projection from 3D grid to terminal coords.
	-- p = {x,y,z} in [1..gx],[1..gy],[1..gz]
	local cx = math.floor(w / 2)
	local cy = math.floor(h / 2)

	local x = p.x
	local y = p.y
	local z = p.z

	local sx = cx + (x - z) * 2
	local sy = cy + (y - math.floor((x + z) / 2))
	return sx, sy
end

local function depthColor(z, gz)
	-- Closer (larger z) => brighter.
	local t = (z - 1) / math.max(1, gz - 1)
	if t > 0.75 then return colors.white end
	if t > 0.55 then return colors.lightGray end
	if t > 0.35 then return colors.gray end
	if t > 0.15 then return colors.blue end
	return colors.black
end

local gx = 10
local gy = 10
local gz = 10

local dirs = {
	{ dx = 1, dy = 0, dz = 0 },
	{ dx = -1, dy = 0, dz = 0 },
	{ dx = 0, dy = 1, dz = 0 },
	{ dx = 0, dy = -1, dz = 0 },
	{ dx = 0, dy = 0, dz = 1 },
	{ dx = 0, dy = 0, dz = -1 },
}

local function isOpposite(a, b)
	return a.dx == -b.dx and a.dy == -b.dy and a.dz == -b.dz
end

local function chooseTurn(cur)
	-- Continue straight most of the time; otherwise turn to a non-opposite axis.
	if math.random() < 0.72 then return cur end

	local options = {}
	for _, d in ipairs(dirs) do
		if not isOpposite(d, cur) then
			table.insert(options, d)
		end
	end
	return options[math.random(1, #options)]
end

local function inBounds(p)
	return p.x >= 1 and p.x <= gx and p.y >= 1 and p.y <= gy and p.z >= 1 and p.z <= gz
end

local trail = {}
local maxTrail = 180

local head = { x = math.floor(gx / 2), y = math.floor(gy / 2), z = math.floor(gz / 2) }
local dir = dirs[math.random(1, #dirs)]

term.setBackgroundColor(colors.black)
term.clear()

while true do
	-- Step
	dir = chooseTurn(dir)
	local next = { x = head.x + dir.dx, y = head.y + dir.dy, z = head.z + dir.dz }

	-- Bounce off bounds by picking a different direction.
	if not inBounds(next) then
		for _ = 1, 10 do
			dir = dirs[math.random(1, #dirs)]
			next = { x = head.x + dir.dx, y = head.y + dir.dy, z = head.z + dir.dz }
			if inBounds(next) then break end
		end
	end

	if inBounds(next) then
		head = next
		table.insert(trail, 1, { x = head.x, y = head.y, z = head.z })
		if #trail > maxTrail then
			table.remove(trail)
		end
	else
		-- Reset if truly stuck.
		head = { x = math.floor(gx / 2), y = math.floor(gy / 2), z = math.floor(gz / 2) }
		dir = dirs[math.random(1, #dirs)]
		trail = {}
	end

	-- Render
	term.setBackgroundColor(colors.black)
	term.clear()
	term.setCursorPos(1, 1)
	term.setTextColor(colors.gray)
	write("3D PIPES")

	for i = #trail, 1, -1 do
		local p = trail[i]
		local sx, sy = project(p)
		if sx >= 1 and sx <= w and sy >= 1 and sy <= h then
			local c = depthColor(p.z, gz)
			if c ~= colors.black then
				term.setCursorPos(clamp(sx, 1, w), clamp(sy, 1, h))
				term.setBackgroundColor(c)
				write(" ")
			end
		end
	end

	sleep(0.07)
end
