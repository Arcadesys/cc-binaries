-- menu.lua
-- The Arcade OS Shell with Attract Mode
-- Controls: [Left] Prev, [Center] Launch, [Right] Next

local games = {
    { name = "Blackjack", cmd = "blackjack", hasDemo = true },
    { name = "Baccarat", cmd = "baccarat", hasDemo = false },
    { name = "Super Slots", cmd = "slots", hasDemo = true },
    { name = "Horse Race", cmd = "race", hasDemo = true },
    { name = "Can't Stop (Free)", cmd = "cant_stop", hasDemo = true },
    { name = "RPS Rogue", cmd = "rps_rogue", hasDemo = true },
    { name = "Idlecraft (Free)", cmd = "idlecraft", hasDemo = true },
}

local utilityItems = {
    { name = "Roulette Watch", cmd = "screensavers/roulette" },
    { name = "Update Arcade", cmd = "update" },
    { name = "Reboot", cmd = "reboot" },
    { name = "Shutdown", cmd = "shutdown" },
}

-- Build full menu
local menuItems = {}
for _, g in ipairs(games) do table.insert(menuItems, g) end
for _, u in ipairs(utilityItems) do table.insert(menuItems, u) end

local selected = 1
local w, h = term.getSize()

local input = require("input")
local credits = require("credits")
local audio = require("audio")

--------------------------------------------------------------------------------
-- UI Drawing
--------------------------------------------------------------------------------

local function drawHeader()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write("ARCADE OS")
    
    local c = credits.get()
    local name = credits.getName()

    local rightText = "Credits: " .. c
    if name then
        rightText = name .. " | " .. rightText
    end

    term.setCursorPos(w - #rightText - 1, 1)
    term.write(rightText)
end

local function drawMenu()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader()
    
    local startY = 3
    local maxVisible = h - 4
    
    for i, item in ipairs(menuItems) do
        local y = startY + i - 1
        if y >= startY and y < startY + maxVisible then
            term.setCursorPos(2, y)
            if i == selected then
                term.setTextColor(colors.lime)
                term.write("> " .. item.name .. " <")
            else
                term.setTextColor(colors.white)
                term.write("  " .. item.name)
            end
        end
    end
    
    -- Footer
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.setCursorPos(1, h)
    term.clearLine()
    term.write(" [L] Prev  [C] Launch  [R] Next")
end

local function drawWelcomePopup(name, amount)
    local popupW, popupH = 28, 9
    local px = math.floor((w - popupW) / 2)
    local py = math.floor((h - popupH) / 2)
    
    -- Draw box
    term.setBackgroundColor(colors.blue)
    for row = py, py + popupH do
        term.setCursorPos(px, row)
        term.write(string.rep(" ", popupW))
    end
    
    term.setTextColor(colors.yellow)
    term.setCursorPos(px + 2, py + 1)
    term.write("*** WELCOME BACK! ***")
    
    term.setTextColor(colors.white)
    term.setCursorPos(px + 2, py + 3)
    term.write("Player: " .. name)
    
    term.setCursorPos(px + 2, py + 5)
    term.write("Credits: " .. amount)
    
    term.setTextColor(colors.lime)
    term.setCursorPos(px + 2, py + 7)
    term.write("Select your game!")
end

--------------------------------------------------------------------------------
-- Attract Mode - Random Game Demos
--------------------------------------------------------------------------------

local function runAttractMode()
    -- Pick a random game that has a demo
    local demoGames = {}
    for _, g in ipairs(games) do
        if g.hasDemo and fs.exists(g.cmd .. ".lua") then
            table.insert(demoGames, g)
        end
    end
    
    if #demoGames == 0 then
        -- Fallback: just show the menu with a screensaver effect
        term.setBackgroundColor(colors.black)
        term.clear()
        
        local cx, cy = math.floor(w/2), math.floor(h/2)
        local titles = {"ARCADE", "INSERT CARD", "PLAY NOW"}
        local colorCycle = {colors.red, colors.yellow, colors.lime, colors.cyan, colors.purple}
        
        for i = 1, 30 do
            term.setBackgroundColor(colors.black)
            term.clear()
            
            local title = titles[(i % #titles) + 1]
            local color = colorCycle[(i % #colorCycle) + 1]
            
            term.setTextColor(color)
            term.setCursorPos(cx - math.floor(#title / 2), cy)
            term.write(title)
            
            local event, p1 = os.pullEvent()
            if event == "disk" then
                return "disk", p1
            end
            local button = input.getButton(event, p1)
            if button or event == "key" or event == "char" then
                return "input"
            end
            if event ~= "timer" then
                sleep(0.5)
            end
        end
        return "timeout"
    end
    
    -- Pick random game and show its name
    local game = demoGames[math.random(#demoGames)]
    
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setTextColor(colors.yellow)
    local title = "NOW SHOWING: " .. game.name:upper()
    term.setCursorPos(math.floor((w - #title) / 2), 2)
    term.write(title)
    sleep(1)
    
    -- Run the game - it will show its attract mode
    -- Games should exit their attract mode on disk insert
    shell.run(game.cmd)
    
    return "game_exit"
end

--------------------------------------------------------------------------------
-- Main Loop
--------------------------------------------------------------------------------

local function launchGame(item)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    
    if item.cmd == "reboot" then
        os.reboot()
    elseif item.cmd == "shutdown" then
        os.shutdown()
    else
        if fs.exists(item.cmd .. ".lua") then
            shell.run(item.cmd)
        else
            print("Game not installed: " .. item.cmd)
            sleep(1)
        end
    end
end

local function main()
    local attractTimer = os.startTimer(15)  -- Start attract mode after 15s idle
    local jazzCoroutine = nil
    local cardInserted = credits.getName() ~= nil
    
    while true do
        drawMenu()
        
        local event, p1 = os.pullEvent()
        
        -- Reset attract timer on any input
        if event ~= "timer" then
            attractTimer = os.startTimer(15)
        end
        
        local button = input.getButton(event, p1)
        
        if button == "LEFT" then
            selected = selected - 1
            if selected < 1 then selected = #menuItems end
            audio.playClick()
            if event == "redstone" then sleep(0.2) end
            
        elseif button == "RIGHT" then
            selected = selected + 1
            if selected > #menuItems then selected = 1 end
            audio.playClick()
            if event == "redstone" then sleep(0.2) end
            
        elseif button == "CENTER" then
            audio.playConfirm()
            audio.stopJazz()
            launchGame(menuItems[selected])
            -- Reset state after returning from game
            cardInserted = credits.getName() ~= nil
            attractTimer = os.startTimer(15)
            if event == "redstone" then sleep(0.2) end
            
        elseif event == "disk" then
            -- Card inserted! Play jazz and show welcome
            local name = credits.getName()
            local amount = credits.get()
            
            if name and not cardInserted then
                cardInserted = true
                audio.playConfirm()
                
                -- Start jazz in parallel
                jazzCoroutine = coroutine.create(function()
                    audio.playJazz()
                end)
                
                -- Show welcome popup
                drawWelcomePopup(name, amount)
                
                -- Wait a moment, playing jazz
                for _ = 1, 20 do
                    if jazzCoroutine and coroutine.status(jazzCoroutine) ~= "dead" then
                        coroutine.resume(jazzCoroutine)
                    end
                    sleep(0.15)
                end
            end
            attractTimer = os.startTimer(15)
            
        elseif event == "disk_eject" then
            cardInserted = false
            audio.stopJazz()
            attractTimer = os.startTimer(15)
            
        elseif event == "timer" and p1 == attractTimer then
            -- No card and idle - run attract mode
            if not cardInserted then
                audio.stopJazz()
                local result = runAttractMode()
                
                if result == "disk" then
                    -- Card was inserted during attract
                    cardInserted = true
                    local name = credits.getName()
                    local amount = credits.get()
                    if name then
                        jazzCoroutine = coroutine.create(function()
                            audio.playJazz()
                        end)
                        drawMenu()
                        drawWelcomePopup(name, amount)
                        for _ = 1, 20 do
                            if jazzCoroutine and coroutine.status(jazzCoroutine) ~= "dead" then
                                coroutine.resume(jazzCoroutine)
                            end
                            sleep(0.15)
                        end
                    end
                end
            end
            attractTimer = os.startTimer(15)
            
        elseif event == "key" then
            local name = keys.getName(p1)
            if name == "up" then
                selected = selected - 1
                if selected < 1 then selected = #menuItems end
                audio.playClick()
            elseif name == "down" then
                selected = selected + 1
                if selected > #menuItems then selected = 1 end
                audio.playClick()
            elseif name == "enter" then
                audio.playConfirm()
                audio.stopJazz()
                launchGame(menuItems[selected])
                cardInserted = credits.getName() ~= nil
                attractTimer = os.startTimer(15)
            end
        end
        
        -- Keep jazz playing if active
        if jazzCoroutine and coroutine.status(jazzCoroutine) ~= "dead" then
            coroutine.resume(jazzCoroutine)
        end
    end
end

main()
