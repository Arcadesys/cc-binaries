-- Minimal example screensaver.
-- This yields frequently (sleep), so the launcher can time-slice it.

local w, h = term.getSize()
local x, y = 2, 2
local dx, dy = 1, 1

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)

while true do
	term.clear()
	term.setCursorPos(x, y)
	write("CC")

	x = x + dx
	y = y + dy

	if x <= 1 then dx = 1 end
	if x >= w - 1 then dx = -1 end
	if y <= 1 then dy = 1 end
	if y >= h then dy = -1 end

	sleep(0.05)
end
