-- update.lua
-- Arcade OS Updater
-- Downloads and installs the latest version from the configured URL

local w, h = term.getSize()

-- ============================================================================
-- CONFIGURATION
-- Default update URL points to the official Arcadesys/cc-arcade repo.
-- Override by creating .update_url file with a custom URL.
-- ============================================================================
local UPDATE_URL = "https://raw.githubusercontent.com/Arcadesys/cc-arcade/main/install.lua"

local function centerText(y, text, fg, bg)
    term.setBackgroundColor(bg or colors.black)
    term.setTextColor(fg or colors.white)
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.write(text)
end

local function drawHeader()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 1)
    term.clearLine()
    centerText(1, "ARCADE OS UPDATER", colors.yellow, colors.blue)
end

local function readUpdateUrl()
    if UPDATE_URL then return UPDATE_URL end
    if fs.exists(".update_url") then
        local f = fs.open(".update_url", "r")
        if f then
            local url = f.readAll()
            f.close()
            url = (url or ""):gsub("%s+", "")
            if url ~= "" then return url end
        end
    end
    return nil
end

local function saveUpdateUrl(url)
    local f = fs.open(".update_url", "w")
    if f then
        f.write(url)
        f.close()
    end
end

local function promptForUrl()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader()
    
    centerText(4, "No update URL configured.", colors.yellow, colors.black)
    centerText(6, "Enter the URL to your install.lua:", colors.white, colors.black)
    centerText(7, "(GitHub raw, Pastebin raw, or custom)", colors.gray, colors.black)
    
    term.setCursorPos(2, 9)
    term.setTextColor(colors.lime)
    term.write("> ")
    term.setTextColor(colors.white)
    
    local url = read()
    if url and url:match("^https?://") then
        saveUpdateUrl(url)
        return url
    end
    return nil
end

local function downloadInstaller(url)
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader()
    
    centerText(5, "Downloading update...", colors.yellow, colors.black)
    centerText(7, url:sub(1, w - 4), colors.gray, colors.black)
    
    -- Check if HTTP is enabled
    if not http then
        centerText(10, "ERROR: HTTP is disabled!", colors.red, colors.black)
        centerText(12, "Enable HTTP in ComputerCraft config", colors.white, colors.black)
        centerText(13, "or server settings.", colors.white, colors.black)
        sleep(3)
        return nil
    end
    
    local response, err = http.get(url)
    if not response then
        centerText(10, "ERROR: Download failed!", colors.red, colors.black)
        centerText(12, tostring(err or "Unknown error"), colors.gray, colors.black)
        sleep(3)
        return nil
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or #content < 100 then
        centerText(10, "ERROR: Invalid response!", colors.red, colors.black)
        sleep(3)
        return nil
    end
    
    return content
end

local function installUpdate(content)
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader()
    
    centerText(5, "Installing update...", colors.yellow, colors.black)
    
    -- Backup current install.lua
    if fs.exists("install.lua") then
        if fs.exists("install.lua.bak") then
            fs.delete("install.lua.bak")
        end
        fs.copy("install.lua", "install.lua.bak")
    end
    
    -- Write new installer
    local f = fs.open("install.lua", "w")
    if not f then
        centerText(8, "ERROR: Could not write file!", colors.red, colors.black)
        sleep(3)
        return false
    end
    f.write(content)
    f.close()
    
    centerText(7, "Running installer...", colors.lime, colors.black)
    sleep(1)
    
    -- Run the installer
    shell.run("install.lua")
    return true
end

local function showMenu()
    local url = readUpdateUrl()
    
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader()
    
    centerText(4, "ARCADE OS UPDATE UTILITY", colors.lime, colors.black)
    
    if url then
        centerText(6, "Update URL:", colors.white, colors.black)
        local displayUrl = #url > w - 6 and url:sub(1, w - 9) .. "..." or url
        centerText(7, displayUrl, colors.gray, colors.black)
    else
        centerText(6, "No update URL configured", colors.yellow, colors.black)
    end
    
    centerText(10, "[1] Check for Updates", colors.white, colors.black)
    centerText(11, "[2] Configure Update URL", colors.white, colors.black)
    centerText(12, "[3] Re-run Local Installer", colors.white, colors.black)
    centerText(13, "[4] Exit", colors.white, colors.black)
    
    centerText(h - 1, "Press a key...", colors.gray, colors.black)
    
    while true do
        local _, key = os.pullEvent("char")
        if key == "1" then
            if not url then
                url = promptForUrl()
            end
            if url then
                local content = downloadInstaller(url)
                if content then
                    installUpdate(content)
                    return
                end
            else
                centerText(h - 3, "No URL configured!", colors.red, colors.black)
                sleep(2)
            end
            return showMenu()
        elseif key == "2" then
            url = promptForUrl()
            return showMenu()
        elseif key == "3" then
            if fs.exists("install.lua") then
                term.setBackgroundColor(colors.black)
                term.clear()
                shell.run("install.lua")
            else
                centerText(h - 3, "No local installer found!", colors.red, colors.black)
                sleep(2)
                return showMenu()
            end
            return
        elseif key == "4" or key == "q" then
            term.setBackgroundColor(colors.black)
            term.clear()
            return
        end
    end
end

-- Run the menu
showMenu()
