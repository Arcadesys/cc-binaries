-- Disco floor screensaver (ComputerCraft:Tweaked)
-- Flashing color tiles, Saturday Night Fever-ish.

local w, h = term.getSize()

-- Use 2-column tiles for chunkier squares.
local tilesX = math.max(1, math.floor(w / 2))
local tilesY = h

local palette = {
	colors.red,
	colors.orange,
	colors.yellow,
	colors.lime,
	colors.green,
	colors.cyan,
	colors.lightBlue,
	colors.blue,
	colors.purple,
	colors.magenta,
	colors.pink,
	colors.white,
	colors.lightGray,
}

local function bgCode(c)
	if c == colors.black then return "0" end
	if c == colors.blue then return "1" end
	if c == colors.green then return "2" end
	if c == colors.cyan then return "3" end
	if c == colors.red then return "4" end
	if c == colors.purple then return "5" end
	if c == colors.orange then return "6" end
	if c == colors.lightGray then return "7" end
	if c == colors.gray then return "8" end
	if c == colors.lightBlue then return "9" end
	if c == colors.lime then return "a" end
	if c == colors.pink then return "d" end
	if c == colors.magenta then return "c" end
	if c == colors.yellow then return "b" end
	if c == colors.white then return "f" end
	return "0"
end

local tiles = {}
for y = 1, tilesY do
	tiles[y] = {}
	for x = 1, tilesX do
		tiles[y][x] = palette[math.random(1, #palette)]
	end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.black)
term.clear()

local t = 0
while true do
	t = t + 1

	-- Randomly flip some tiles each frame.
	local flips = math.floor((tilesX * tilesY) * 0.12)
	for _ = 1, flips do
		local x = math.random(1, tilesX)
		local y = math.random(1, tilesY)
		tiles[y][x] = palette[math.random(1, #palette)]
	end

	-- Add a moving "spotlight" wave.
	local waveX = ((t % (tilesX + 6)) - 3)
	for y = 1, tilesY do
		for x = 1, tilesX do
			if math.abs(x - waveX) <= 1 and math.random() < 0.45 then
				tiles[y][x] = colors.white
			end
		end
	end

	-- Render via blit (fast)
	for y = 1, tilesY do
		local text = {}
		local fg = {}
		local bg = {}
		for x = 1, tilesX do
			local c = tiles[y][x]
			local code = bgCode(c)
			-- 2-column tile
			table.insert(text, " ")
			table.insert(text, " ")
			table.insert(fg, "0")
			table.insert(fg, "0")
			table.insert(bg, code)
			table.insert(bg, code)
		end

		local line = table.concat(text)
		local fgs = table.concat(fg)
		local bgs = table.concat(bg)
		if #line < w then
			local pad = w - #line
			line = line .. string.rep(" ", pad)
			fgs = fgs .. string.rep("0", pad)
			bgs = bgs .. string.rep("0", pad)
		elseif #line > w then
			line = line:sub(1, w)
			fgs = fgs:sub(1, w)
			bgs = bgs:sub(1, w)
		end

		term.setCursorPos(1, y)
		term.blit(line, fgs, bgs)
	end

	-- Title overlay (top-left)
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.gray)
	term.setCursorPos(1, 1)
	write("DISCO")

	sleep(0.1)
end
