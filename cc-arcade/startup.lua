-- startup.lua
-- Launches the Arcade Menu OS

-- Monitor Detection
local monitor = peripheral.find("monitor")
if monitor then
    term.redirect(monitor)
    
    -- Dynamic Scaling: Find largest text scale that fits the UI
    local min_w, min_h = 39, 19 -- Minimum resolution for Arcade apps
    
    for scale = 5, 0.5, -0.5 do
        monitor.setTextScale(scale)
        local w, h = monitor.getSize()
        if w >= min_w and h >= min_h then
            break
        end
    end
end

term.clear()
term.setCursorPos(1, 1)
print("Booting ArcadeOS...")

if not fs.exists(".button_config") then
    shell.run("config.lua")
end

-- Kiosk Mode: Dedicated public machine (e.g., spawn Can't Stop)
local function readArcadeConfig()
    if not fs.exists(".arcade_config") then return nil end
    local f = fs.open(".arcade_config", "r")
    if not f then return nil end
    local cmd = (f.readAll() or "")
    f.close()
    cmd = cmd:gsub("%s+", "")
    if cmd == "" then return nil end
    return cmd
end

local function adminKeyPresent()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "drive" then
            local path = disk.getMountPath(side)
            if path and fs.exists(path .. "/admin.key") then
                return true
            end
        end
    end
    return false
end

local function shouldKiosk()
    -- If explicitly enabled, always kiosk.
    if fs.exists(".kiosk_mode") then return true end
    -- Default: any configured machine is kiosk unless an admin key disk is inserted.
    if fs.exists(".arcade_config") and not adminKeyPresent() then return true end
    return false
end

-- Remote Update Function
local function runRemoteUpdate()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("ARCADE OS UPDATER")
    print("=================")
    term.setTextColor(colors.white)
    
    -- Read update URL from .update_url or use default
    local DEFAULT_URL = "https://raw.githubusercontent.com/Arcadesys/cc-arcade/main/install.lua"
    local url = DEFAULT_URL
    if fs.exists(".update_url") then
        local f = fs.open(".update_url", "r")
        if f then
            local custom = (f.readAll() or ""):gsub("%s+", "")
            f.close()
            if custom ~= "" then url = custom end
        end
    end
    
    if not http then
        term.setTextColor(colors.red)
        print("")
        print("ERROR: HTTP is disabled!")
        print("Enable HTTP in ComputerCraft config.")
        print("")
        print("Press any key to continue boot...")
        os.pullEvent("key")
        return false
    end
    
    print("")
    print("Downloading from:")
    term.setTextColor(colors.gray)
    print(url:sub(1, 45) .. (url:len() > 45 and "..." or ""))
    term.setTextColor(colors.white)
    print("")
    
    local response, err = http.get(url)
    if not response then
        term.setTextColor(colors.red)
        print("Download failed: " .. tostring(err))
        print("")
        print("Press any key to continue boot...")
        os.pullEvent("key")
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or #content < 100 then
        term.setTextColor(colors.red)
        print("Invalid response (too short)")
        print("")
        print("Press any key to continue boot...")
        os.pullEvent("key")
        return false
    end
    
    -- Backup and write
    if fs.exists("install.lua") then
        if fs.exists("install.lua.bak") then fs.delete("install.lua.bak") end
        fs.copy("install.lua", "install.lua.bak")
    end
    
    local f = fs.open("install.lua", "w")
    f.write(content)
    f.close()
    
    term.setTextColor(colors.lime)
    print("Download complete!")
    print("Running installer...")
    sleep(1)
    
    shell.run("install.lua")
    return true
end

if shouldKiosk() and fs.exists("kiosk.lua") then
    _G.ARCADE_KIOSK = true
    shell.run("kiosk.lua")
    os.reboot()
end

print("Press 'D' Dev Mode, 'U' Update (2s)...")

_G.ARCADE_DEV_MODE = false
local timer = os.startTimer(2)
while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timer then
        break
    elseif event == "char" and p1:lower() == "d" then
        _G.ARCADE_DEV_MODE = true
        print("DEV MODE ENABLED: Infinite Credits")
        sleep(1)
        break
    elseif event == "char" and p1:lower() == "u" then
        runRemoteUpdate()
        -- After update, installer reboots, so we won't reach here
        -- But if update fails, continue boot
        break
    end
end

if not _G.ARCADE_DEV_MODE then
    print("Production Mode: Standard Credits")
end
sleep(0.5)

-- Always launch the menu
if fs.exists("menu.lua") then
    print("Launching Arcade Menu...")
    sleep(0.5)
    shell.run("menu")
elseif fs.exists("setup.lua") then
    shell.run("setup.lua")
else
    print("Error: menu.lua not found!")
end
