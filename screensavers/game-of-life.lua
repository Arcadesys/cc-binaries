-- Conway's Game of Life screensaver (ComputerCraft:Tweaked)
-- Yields via sleep() so it can be time-sliced by the launcher.

local w, h = term.getSize()

local function makeGrid(fill)
	local g = {}
	for y = 1, h do
		local row = {}
		for x = 1, w do
			row[x] = fill and true or false
		end
		g[y] = row
	end
	return g
end

local function randomize(g, pAlive)
	for y = 1, h do
		for x = 1, w do
			g[y][x] = (math.random() < pAlive)
		end
	end
end

local function countNeighbors(g, x, y)
	local n = 0
	for dy = -1, 1 do
		for dx = -1, 1 do
			if not (dx == 0 and dy == 0) then
				local xx = x + dx
				local yy = y + dy
				-- wrap edges
				if xx < 1 then xx = w elseif xx > w then xx = 1 end
				if yy < 1 then yy = h elseif yy > h then yy = 1 end
				if g[yy][xx] then n = n + 1 end
			end
		end
	end
	return n
end

local function step(cur, nxt)
	for y = 1, h do
		for x = 1, w do
			local alive = cur[y][x]
			local n = countNeighbors(cur, x, y)
			if alive then
				nxt[y][x] = (n == 2 or n == 3)
			else
				nxt[y][x] = (n == 3)
			end
		end
	end
end

local function draw(g)
	term.setCursorPos(1, 1)
	term.setTextColor(colors.black)

	for y = 1, h do
		local text = string.rep(" ", w)
		local fg = string.rep("0", w)
		local bg = {}
		for x = 1, w do
			bg[x] = g[y][x] and "f" or "0" -- white on black
		end
		term.setCursorPos(1, y)
		term.blit(text, fg, table.concat(bg))
	end
end

term.setBackgroundColor(colors.black)
term.clear()

local a = makeGrid(false)
local b = makeGrid(false)
randomize(a, 0.28)

local frames = 0
while true do
	draw(a)
	step(a, b)
	a, b = b, a

	frames = frames + 1
	-- Re-seed periodically to keep it interesting.
	if frames % 250 == 0 then
		randomize(a, 0.28)
	end

	sleep(0.12)
end
