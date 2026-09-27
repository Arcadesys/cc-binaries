-- rps_rogue.lua
-- Rock-Paper-Scissors Roguelike

local w, h = term.getSize()

-- 3-Button Config
local input = require("input")

local function waitForDiskOrTimeout(seconds)
    local timerId
    if seconds and seconds > 0 then
        timerId = os.startTimer(seconds)
    end

    while true do
        local e, p1 = os.pullEvent()

        if e == "disk" then
            return { type = "disk", event = e, p1 = p1 }
        end

        if timerId and e == "timer" and p1 == timerId then
            return { type = "timeout" }
        end
    end
end

local function waitKey()
    while true do
        local e, p1 = os.pullEvent()
        local button = input.getButton(e, p1)
        if button then
            if e == "redstone" then sleep(0.2) end
            return button
        end
    end
end

--------------------------------------------------------------------------------
-- GAME LOGIC
--------------------------------------------------------------------------------

local MOVES = { "Rock", "Paper", "Scissors" }
local BEATS = { Rock = "Scissors", Paper = "Rock", Scissors = "Paper" }

local player = { hp = 20, maxHp = 20, dmg = 3, level = 1 }
local enemy = { hp = 10, maxHp = 10, dmg = 2, name = "Slime" }
local floor = 1
local log = {}

local function addLog(msg)
    table.insert(log, 1, msg)
    if #log > 5 then table.remove(log) end
end

local function generateEnemy()
    local types = {
        {name="Slime", hp=10, dmg=2},
        {name="Goblin", hp=15, dmg=3},
        {name="Orc", hp=25, dmg=4},
        {name="Dragon", hp=50, dmg=8}
    }
    local idx = math.min(#types, math.floor((floor-1)/3) + 1)
    if floor > 10 then idx = 4 end
    
    local base = types[idx]
    enemy = {
        name = base.name,
        hp = base.hp + math.floor(floor * 1.5),
        maxHp = base.hp + math.floor(floor * 1.5),
        dmg = base.dmg + math.floor(floor * 0.5)
    }
end

local function resolveRound(pMove, eMove)
    addLog("You: " .. pMove .. " vs " .. eMove)
    
    if pMove == eMove then
        addLog("Draw!")
    elseif BEATS[pMove] == eMove then
        addLog("Hit! Dealt " .. player.dmg .. " dmg.")
        enemy.hp = enemy.hp - player.dmg
        audio.playClick()
    else
        addLog("Ouch! Took " .. enemy.dmg .. " dmg.")
        player.hp = player.hp - enemy.dmg
        audio.playLose()
    end
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local function drawText(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(text)
end

local function drawFooter(c1, c2, c3)
    local colW = math.floor(w / 3)
    
    -- Left Button
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", colW))
    drawText(math.floor(colW/2 - #c1/2)+1, h, c1, colors.white, colors.red)
    
    -- Center Button
    term.setCursorPos(colW + 1, h)
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
    term.write(string.rep(" ", colW))
    drawText(colW + math.floor(colW/2 - #c2/2)+1, h, c2, colors.black, colors.yellow)
    
    -- Right Button
    term.setCursorPos(colW * 2 + 1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w - (colW*2)))
    drawText(colW*2 + math.floor((w - colW*2)/2 - #c3/2)+1, h, c3, colors.white, colors.blue)
end

local function drawBar(label, val, max, y, color)
    term.setCursorPos(2, y)
    term.setTextColor(color)
    term.write(label .. ": " .. val .. "/" .. max)
    
    local barW = 10
    local fill = math.ceil((val/max) * barW)
    term.setCursorPos(2, y+1)
    term.setBackgroundColor(color)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", barW - fill))
    term.setBackgroundColor(colors.black)
end

local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" FLOOR " .. floor .. " - " .. enemy.name)
    
    -- Stats
    drawBar("PLAYER", player.hp, player.maxHp, 3, colors.lime)
    drawBar("ENEMY", enemy.hp, enemy.maxHp, 3, colors.red)
    
    -- Enemy is on the right
    term.setCursorPos(w - 15, 3)
    term.setTextColor(colors.red)
    term.write(enemy.name)
    term.setCursorPos(w - 15, 4)
    term.write("HP: " .. enemy.hp .. "/" .. enemy.maxHp)
    
    -- Log
    term.setCursorPos(2, 8)
    term.setTextColor(colors.white)
    term.write("--- LOG ---")
    for i, msg in ipairs(log) do
        term.setCursorPos(2, 9 + i)
        term.setTextColor(colors.lightGray)
        term.write(msg)
    end
    
    -- Controls
    term.setCursorPos(1, h)
    drawFooter("Rock", "Paper", "Scissors")
end

local function drawUpgradeMenu()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.clearLine()
    term.write(" LEVEL UP! Choose Upgrade:")
    
    term.setCursorPos(1, h)
    drawFooter("Heal Full", "+5 Max HP", "+1 Damage")
end

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------

local creditsAPI = require("credits")
local audio = require("audio")

local function main()
    while creditsAPI.get() < 5 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.clearLine()
        term.write(" RPS ROGUE ")

        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(2, math.floor(h/2) - 2)
        term.write("Insert Coin: 5 Credits")
        term.setCursorPos(2, math.floor(h/2))
        term.setTextColor(colors.gray)
        term.write("ATTRACTION MODE - Insert Disk to Play")

        -- Simple demo text that cycles until a disk is inserted.
        local demoLines = {
            "Rock beats Scissors",
            "Paper beats Rock",
            "Scissors beats Paper",
            "Level up and keep going!",
        }

        for i = 1, #demoLines do
            term.setCursorPos(2, math.floor(h/2) + 2)
            term.setTextColor(colors.yellow)
            term.clearLine()
            term.write(demoLines[i])
            local brk = waitForDiskOrTimeout(1.0)
            if brk and brk.type == "disk" then
                break
            end
        end
    end
    creditsAPI.remove(5)

    generateEnemy()
    
    while true do
        if player.hp <= 0 then
            term.clear()
            term.setCursorPos(1, h/2)
            term.setTextColor(colors.red)
            term.write("GAME OVER")
            term.setCursorPos(1, h/2 + 1)
            term.write("Reached Floor " .. floor)
            audio.playLose()
            sleep(3)
            break
        end
        
        if enemy.hp <= 0 then
            -- Victory
            floor = floor + 1
            player.level = player.level + 1
            creditsAPI.add(5) -- Reward for clearing floor
            audio.playWin()
            
            -- Upgrade
            drawUpgradeMenu()
            local key = waitKey()
            if key == "LEFT" then
                player.hp = player.maxHp
            elseif key == "CENTER" then
                player.maxHp = player.maxHp + 5
                player.hp = player.hp + 5
            elseif key == "RIGHT" then
                player.dmg = player.dmg + 1
            end
            audio.playConfirm()
            
            generateEnemy()
            log = {}
            addLog("Floor " .. floor .. " start!")
        else
            drawUI()
            local key = waitKey()
            local pMove = nil
            if key == "LEFT" then pMove = "Rock"
            elseif key == "CENTER" then pMove = "Paper"
            elseif key == "RIGHT" then pMove = "Scissors" end
            
            if pMove then
                local eMove = MOVES[math.random(1, 3)]
                resolveRound(pMove, eMove)
            end
        end
    end
    
    if fs.exists("menu.lua") then shell.run("menu.lua") end
end

main()
