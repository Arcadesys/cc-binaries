-- setup.lua
-- Initial Configuration Menu
-- Select the game to permanently install on this machine

local games = {
    { name = "Blackjack", cmd = "blackjack" },
    { name = "Baccarat", cmd = "baccarat" },
    { name = "Super Slots", cmd = "slots" },
    { name = "Horse Race", cmd = "race" },
    { name = "Can't Stop (Free)", cmd = "cant_stop" },
    { name = "Can't Stop (Dedicated Spawn)", cmd = "cant_stop_kiosk" },
    { name = "RPS Rogue", cmd = "rps_rogue" },
    { name = "Roulette Watch", cmd = "screensavers/roulette" },
    { name = "Exchange", cmd = "exchange" },
    { name = "Cashier System", cmd = "cashier" }
}

local selected = 1
local w, h = term.getSize()

local input = require("input")
local audio = require("audio")

local function drawHeader()
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write("SYSTEM SETUP - ONE TIME ONLY")
end

local function drawMenu()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader()
    
    local centerY = math.floor(h / 2)
    
    term.setCursorPos(2, 3)
    term.setTextColor(colors.gray)
    term.write("Select Game to Install:")

    for i, game in ipairs(games) do
        local y = centerY - 1 + i
        if y >= 4 and y < h then
            term.setCursorPos(2, y)
            if i == selected then
                term.setTextColor(colors.lime)
                term.write("> " .. game.name .. " <")
            else
                term.setTextColor(colors.white)
                term.write("  " .. game.name)
            end
        end
    end
    
    -- Footer
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.setCursorPos(1, h)
    term.clearLine()
    term.write(" [L] Prev  [C] INSTALL  [R] Next")
end

local function installGame()
    local game = games[selected]
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("Installing " .. game.name .. "...")

    -- Dedicated Spawn preset
    if game.cmd == "cant_stop_kiosk" then
        local file = fs.open(".arcade_config", "w")
        file.write("cant_stop")
        file.close()

        local k = fs.open(".kiosk_mode", "w")
        k.write("1")
        k.close()

        local kg = fs.open(".kiosk_game", "w")
        kg.write("cant_stop")
        kg.close()
    else
        local file = fs.open(".arcade_config", "w")
        file.write(game.cmd)
        file.close()
    end
    
    print("Configuration saved.")
    print("Rebooting in 2 seconds...")
    sleep(2)
    os.reboot()
end

local function main()
    while true do
        drawMenu()
        
        local event, p1 = os.pullEvent()
        local button = input.getButton(event, p1)
        
        if button == "LEFT" then
            selected = selected - 1
            if selected < 1 then selected = #games end
            audio.playClick()
            if event == "redstone" then sleep(0.2) end
        elseif button == "RIGHT" then
            selected = selected + 1
            if selected > #games then selected = 1 end
            audio.playClick()
            if event == "redstone" then sleep(0.2) end
        elseif button == "CENTER" then
            audio.playConfirm()
            installGame()
            break
        end
    end
end

main()
