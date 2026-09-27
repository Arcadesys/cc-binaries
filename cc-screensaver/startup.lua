-- Auto-start the screensaver shuffler on boot.
-- Remove this file if you don't want auto-start.

if fs.exists("/screensaver.lua") then
	shell.run("/screensaver.lua")
else
	-- Fallback if the user renamed/moved it.
	shell.run("screensaver")
end
