-- dedicate.lua
-- Simple installer for dedicated (kiosk) machines.
-- Writes .arcade_config + kiosk flag files, then reboots.

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function writeFile(path, content)
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

local function deleteFile(path)
    if fs.exists(path) then
        fs.delete(path)
    end
end

local function isKioskEnabled()
    return fs.exists(".kiosk_mode")
end

local function currentCmd()
    if not fs.exists(".arcade_config") then return nil end
    local f = fs.open(".arcade_config", "r")
    if not f then return nil end
    local cmd = (f.readAll() or "")
    f.close()
    cmd = cmd:gsub("%s+", "")
    if cmd == "" then return nil end
    return cmd
end

local function pause()
    while true do
        local e, p1 = os.pullEvent()
        if e == "key" or e == "mouse_click" or e == "monitor_touch" then
            return
        end
    end
end

clear()
print("DEDICATED INSTALLER")
print("===================")
print("")
print("This will configure this computer to run")
print("only one game (kiosk mode).")
print("")
print("Current: " .. tostring(currentCmd() or "<none>"))
print("Kiosk:   " .. (isKioskEnabled() and "ON" or "OFF"))
print("")
print("1) Dedicated: Can't Stop (spawn)")
print("2) Disable kiosk (return to normal)")
print("")
print("Press 1 or 2...")

while true do
    local e, key = os.pullEvent("key")
    local name = keys.getName(key)

    if name == "one" or name == "numPad1" then
        -- Dedicated Can't Stop
        clear()
        print("Installing: Can't Stop kiosk...")
        writeFile(".arcade_config", "cant_stop")
        writeFile(".kiosk_mode", "1")
        writeFile(".kiosk_game", "cant_stop")
        print("Done. Rebooting...")
        sleep(1)
        os.reboot()

    elseif name == "two" or name == "numPad2" then
        -- Disable kiosk mode
        clear()
        print("Disabling kiosk mode...")
        deleteFile(".kiosk_mode")
        deleteFile(".kiosk_game")
        print("Done.")
        print("Tip: run setup.lua or edit .arcade_config")
        print("to choose a different default program.")
        print("")
        print("Rebooting...")
        sleep(1)
        os.reboot()
    end
end
