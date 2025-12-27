-- Roulette wheel screensaver (ComputerCraft:Tweaked)
-- Simple terminal animation that spins and lands on a number.

local w, h = term.getSize()

local function centerText(y, s, textColor)
	if textColor then term.setTextColor(textColor) end
	local x = math.max(1, math.floor((w - #s) / 2) + 1)
	term.setCursorPos(x, y)
	write(s)
end

-- Standard European roulette numbers order.
local numbers = {
	0,
	32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
	5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26
}

local red = {
	[1]=true,[3]=true,[5]=true,[7]=true,[9]=true,[12]=true,[14]=true,[16]=true,[18]=true,
	[19]=true,[21]=true,[23]=true,[25]=true,[27]=true,[30]=true,[32]=true,[34]=true,[36]=true
}

local function colorFor(n)
	if n == 0 then return colors.green end
	if red[n] then return colors.red end
	return colors.black
end

local function bgCode(c)
	if c == colors.green then return "d" end
	if c == colors.red then return "e" end
	if c == colors.black then return "0" end
	return "7"
end

local function drawBand(offset, highlightIndex)
	-- Draw a horizontal band of slots with a pointer.
	local slots = math.min(13, w) -- visible slots
	local midY = math.floor(h / 2)
	local start = offset

	local text = {}
	local fg = {}
	local bg = {}
	for i = 1, slots do
		local idx = ((start + i - 2) % #numbers) + 1
		local n = numbers[idx]
		local label = tostring(n)
		if #label == 1 then label = " " .. label end
		if #label == 2 then label = "" .. label end
		-- Each slot is 3 chars wide: space + 2 digits
		local slotText = " " .. label
		for k = 1, #slotText do
			table.insert(text, slotText:sub(k, k))
			table.insert(fg, "f")

			local c = colorFor(n)
			if idx == highlightIndex then
				-- invert-ish highlight by using light gray background
				table.insert(bg, "7")
			else
				table.insert(bg, bgCode(c))
			end
		end
	end

	local line = table.concat(text)
	if #line > w then line = line:sub(1, w) end
	local fgs = table.concat(fg)
	local bgs = table.concat(bg)
	if #fgs > w then fgs = fgs:sub(1, w) end
	if #bgs > w then bgs = bgs:sub(1, w) end

	term.setCursorPos(1, midY)
	term.blit(line .. string.rep(" ", math.max(0, w - #line)), fgs .. string.rep("f", math.max(0, w - #fgs)), bgs .. string.rep("0", math.max(0, w - #bgs)))

	-- Pointer
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.yellow)
	local pointerX = math.max(1, math.floor(w / 2))
	term.setCursorPos(pointerX, midY - 1)
	write("v")
	term.setCursorPos(pointerX, midY + 1)
	write("^")
end

term.setBackgroundColor(colors.black)
term.clear()

while true do
	term.setBackgroundColor(colors.black)
	term.clear()
	centerText(2, "ROULETTE", colors.white)
	centerText(3, "Spinning...", colors.gray)

	local offset = math.random(1, #numbers)
	local speed = math.random(18, 28) / 10 -- initial slots per tick
	local decel = math.random(3, 6) / 100

	while speed > 0.05 do
		offset = offset + math.max(1, math.floor(speed))
		drawBand(offset)
		sleep(0.05)
		speed = speed - decel
	end

	local winningIndex = ((offset + math.floor(w / 6)) % #numbers) + 1
	local winning = numbers[winningIndex]

	term.setBackgroundColor(colors.black)
	term.clear()
	centerText(2, "ROULETTE", colors.white)
	centerText(3, "Winner:", colors.gray)
	centerText(5, tostring(winning), colors.yellow)
	centerText(6, (winning == 0 and "GREEN" or (red[winning] and "RED" or "BLACK")), colors.white)

	-- Show a final band with highlight
	drawBand(offset, winningIndex)
	sleep(1.2)
end
