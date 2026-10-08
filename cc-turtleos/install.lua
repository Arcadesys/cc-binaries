-- TurtleOS installer. On a turtle:
--   wget run https://raw.githubusercontent.com/Arcadesys/cc-binaries/main/cc-turtleos/install.lua
-- Run it again to update. Options: --base URL (a fork or branch's raw
-- cc-binaries URL), --no-reboot.
local base = "https://raw.githubusercontent.com/Arcadesys/cc-binaries/main"
local reboot = true
local args = { ... }
local i = 1
while i <= #args do
    if args[i] == "--base" then
        i = i + 1
        base = args[i]
    elseif args[i] == "--no-reboot" then
        reboot = false
    else
        error("Unknown option " .. args[i], 0)
    end
    i = i + 1
end

-- Keep in step with the files under cc-turtleos/.
local FILES = {
    "boot.lua",
    "turtleos/menu.lua",
    "turtleos/apis/movement.lua",
    "turtleos/lib/core.lua",
    "turtleos/lib/field.lua",
    "turtleos/lib/inv.lua",
    "turtleos/lib/jobs.lua",
    "turtleos/lib/logger.lua",
    "turtleos/lib/nav.lua",
    "turtleos/lib/ui.lua",
    "turtleos/strategies/farmer/crops.lua",
    "turtleos/strategies/farmer/sugarcane.lua",
    "turtleos/strategies/farmer/tree.lua",
    "turtleos/strategies/miner/branch.lua",
}

-- Files from older TurtleOS versions that would show up as broken jobs.
local REMOVED = {
    "turtleos/strategies/farmer/potato.lua",
    "turtleos/roles",
    "turtleos/lib/schema.lua",
    "turtle_schema.json",
}

print("Installing TurtleOS from " .. base)
for _, path in ipairs(FILES) do
    local url = base .. "/cc-turtleos/" .. path
    local res, err = http.get(url)
    if not res then error("Couldn't download " .. url .. ": " .. tostring(err), 0) end
    local body = res.readAll()
    res.close()
    local h = fs.open("/" .. path, "w")
    h.write(body)
    h.close()
    print("  " .. path)
end
for _, path in ipairs(REMOVED) do
    if fs.exists("/" .. path) then fs.delete("/" .. path) end
end

if not fs.exists("/startup.lua") then
    local h = fs.open("/startup.lua", "w")
    h.write('shell.run("boot.lua")\n')
    h.close()
    print("Created startup.lua")
end

if not os.getComputerLabel() then
    os.setComputerLabel("Turtle " .. os.getComputerID())
    print("Labelled this turtle so it keeps its files when broken")
end

if reboot then
    print("Done. Rebooting in 3 seconds...")
    sleep(3)
    os.reboot()
end
print("Done. Run 'boot' to start.")
