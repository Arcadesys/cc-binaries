-- slots.lua
-- 3-Button Slot Machine (Multiplayer Edition)

local w, h = term.getSize()
local cx, cy = math.floor(w / 2), math.floor(h / 2)

local input = require("input")
local creditsAPI = require("credits")
local audio = require("audio")

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

local function drawText(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(text)
end

local function drawCenter(y, text, fg, bg)
    local x = math.floor((w - #text)/2) + 1
    drawText(x, y, text, fg, bg)
end

--------------------------------------------------------------------------------
-- UI PRIMITIVES ("graphics" via term/blit)
--------------------------------------------------------------------------------

local HAS_BLIT = type(term.blit) == "function"

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function toBlit(c)
    if type(colors) == "table" and type(colors.toBlit) == "function" then
        return colors.toBlit(c)
    end
    -- Fallback: most CC installs have colors.toBlit; if not, use white.
    return "0"
end

local function blitFill(x, y, width, height, ch, fg, bg)
    ch = ch or " "
    fg = fg or colors.white
    bg = bg or colors.black
    if width <= 0 or height <= 0 then return end
    if not HAS_BLIT then
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        for row = 0, height - 1 do
            term.setCursorPos(x, y + row)
            term.write(string.rep(ch, width))
        end
        return
    end
    local text = string.rep(ch, width)
    local fgs = string.rep(toBlit(fg), width)
    local bgs = string.rep(toBlit(bg), width)
    for row = 0, height - 1 do
        term.setCursorPos(x, y + row)
        term.blit(text, fgs, bgs)
    end
end

local function writeAt(x, y, text, fg, bg)
    if not text or #text == 0 then return end
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end

local function frameRect(x, y, width, height, borderBg, innerBg)
    if width <= 1 or height <= 1 then return end
    borderBg = borderBg or colors.gray
    innerBg = innerBg or colors.black

    blitFill(x, y, width, 1, " ", colors.white, borderBg)
    blitFill(x, y + height - 1, width, 1, " ", colors.white, borderBg)
    blitFill(x, y + 1, 1, height - 2, " ", colors.white, borderBg)
    blitFill(x + width - 1, y + 1, 1, height - 2, " ", colors.white, borderBg)
    blitFill(x + 1, y + 1, width - 2, height - 2, " ", colors.white, innerBg)
end

local function shadowRect(x, y, width, height, shadowBg)
    shadowBg = shadowBg or colors.black
    blitFill(x + 1, y + height, width, 1, " ", colors.white, shadowBg)
    blitFill(x + width, y + 1, 1, height, " ", colors.white, shadowBg)
end

local function centerTextIn(x, y, width, text, fg, bg)
    local tx = x + math.floor((width - #text) / 2)
    writeAt(tx, y, text, fg, bg)
end

--------------------------------------------------------------------------------
-- GAME CONFIG
--------------------------------------------------------------------------------

local SYMBOLS = {"Cherry", "Lemon", "Orange", "Plum", "Bell", "Bar", "7"}
local COLORS = {
    Cherry = colors.red, Lemon = colors.yellow, Orange = colors.orange,
    Plum = colors.purple, Bell = colors.gold or colors.yellow,
    Bar = colors.lightGray, ["7"] = colors.red
}
local CHARS = {
    Cherry = "@", Lemon = "O", Orange = "O", Plum = "%",
    Bell = "A", Bar = "=", ["7"] = "7"
}
local PAYOUTS = {
    Cherry = 5, Lemon = 10, Orange = 20, Plum = 50,
    Bell = 100, Bar = 250, ["7"] = 500
}

local REELS = {}
for i=1,3 do
    REELS[i] = {}
    for j=1,32 do
        local r = math.random()
        local s
        if r < 0.05 then s = "7"
        elseif r < 0.15 then s = "Bar"
        elseif r < 0.25 then s = "Bell"
        elseif r < 0.40 then s = "Plum"
        elseif r < 0.60 then s = "Orange"
        elseif r < 0.80 then s = "Lemon"
        else s = "Cherry" end
        table.insert(REELS[i], s)
    end
end

--------------------------------------------------------------------------------
-- DRAWING
--------------------------------------------------------------------------------

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

local reelPos = {1, 1, 1}

local function drawReel(idx, x, y)
    -- Reel window: framed 7x7 with 3 visible symbols.
    local reelW, reelH = 7, 7
    shadowRect(x, y, reelW, reelH, colors.black)
    frameRect(x, y, reelW, reelH, colors.gray, colors.white)

    local innerX, innerY = x + 1, y + 1
    local innerW, innerH = reelW - 2, reelH - 2

    -- Subtle inner shading band
    blitFill(innerX, innerY, innerW, 1, " ", colors.white, colors.lightGray)
    blitFill(innerX, innerY + innerH - 1, innerW, 1, " ", colors.white, colors.lightGray)

    local rowYs = { innerY + 1, innerY + 2, innerY + 3 }
    for i = 0, 2 do
        local pos = (reelPos[idx] + i - 1) % #REELS[idx] + 1
        local sym = REELS[idx][pos]
        local yRow = rowYs[i + 1]

        -- highlight the center row slightly
        local bg = (i == 1) and colors.white or colors.lightGray
        blitFill(innerX, yRow, innerW, 1, " ", colors.white, bg)

        local face = " " .. CHARS[sym] .. CHARS[sym] .. CHARS[sym] .. " "
        centerTextIn(innerX, yRow, innerW, face, COLORS[sym], bg)
    end
end

local function drawMachine(bet, message, currentPlayerName, currentCredits)
    -- Small terminal fallback
    if w < 34 or h < 19 then
        term.setBackgroundColor(colors.black)
        term.clear()
        drawCenter(1, " SUPER SLOTS ", colors.yellow, colors.blue)
        drawCenter(3, "Bet: " .. tostring(bet), colors.white, colors.black)
        drawCenter(5, tostring(message), colors.yellow, colors.black)
        if currentPlayerName then
            drawCenter(7, "Player: " .. currentPlayerName, colors.white, colors.black)
            drawCenter(8, "Credits: " .. tostring(currentCredits), colors.gold, colors.black)
        end
        drawFooter("Bet", "Spin", "Exit")
        return
    end

    -- Background (subtle pattern)
    term.setBackgroundColor(colors.black)
    term.clear()
    for y = 2, h - 5, 2 do
        blitFill(1, y, w, 1, " ", colors.white, colors.black)
        blitFill(1, y + 1, w, 1, " ", colors.white, colors.gray)
    end

    -- Top title bar
    blitFill(1, 1, w, 1, " ", colors.white, colors.blue)
    centerTextIn(1, 1, w, " SUPER SLOTS ", colors.yellow, colors.blue)
    writeAt(2, 1, "*", colors.yellow, colors.blue)
    writeAt(w - 1, 1, "*", colors.yellow, colors.blue)

    -- Cabinet frame
    local boxW, boxH = 30, 15
    local bx, by = clamp(cx - math.floor(boxW / 2), 2, w - boxW - 1), clamp(cy - 7, 3, h - boxH - 5)
    shadowRect(bx, by, boxW, boxH, colors.black)
    frameRect(bx, by, boxW, boxH, colors.gray, colors.lightGray)
    blitFill(bx + 1, by + 1, boxW - 2, 1, " ", colors.white, colors.orange)
    centerTextIn(bx + 1, by + 1, boxW - 2, " JACKPOT ", colors.white, colors.orange)

    -- Reels area
    local startX = bx + 4
    local startY = by + 4
    for i = 1, 3 do
        drawReel(i, startX + (i - 1) * 9, startY)
    end

    -- Paylines (left arrows + line highlight across reel windows)
    local payTopY = startY + 2
    local payMidY = startY + 3
    local payBotY = startY + 4
    local arrowX = startX - 2
    local lineX = startX + 1
    local lineW = 3 * 9 - 4

    if bet >= 2 then
        writeAt(arrowX, payTopY, ">", colors.red, colors.lightGray)
        blitFill(lineX, payTopY, lineW, 1, " ", colors.white, colors.red)
    end
    if bet >= 1 then
        writeAt(arrowX, payMidY, ">", colors.red, colors.lightGray)
        blitFill(lineX, payMidY, lineW, 1, " ", colors.white, colors.red)
    end
    if bet >= 3 then
        writeAt(arrowX, payBotY, ">", colors.red, colors.lightGray)
        blitFill(lineX, payBotY, lineW, 1, " ", colors.white, colors.red)
    end

    -- Side info panels
    local infoY = by + boxH + 1
    local infoH = 3
    local leftW = math.min(18, w - 4)
    local rightW = 12

    frameRect(2, infoY, leftW, infoH, colors.gray, colors.black)
    frameRect(w - rightW - 1, infoY, rightW, infoH, colors.gray, colors.black)

    if currentPlayerName then
        writeAt(4, infoY + 1, "Player:", colors.lightGray, colors.black)
        writeAt(12, infoY + 1, tostring(currentPlayerName), colors.white, colors.black)
        writeAt(4, infoY + 2, "Credits:", colors.lightGray, colors.black)
        writeAt(13, infoY + 2, tostring(currentCredits), colors.gold, colors.black)
    else
        writeAt(4, infoY + 1, "Insert card to play", colors.lightGray, colors.black)
    end

    writeAt(w - rightW, infoY + 1, "BET", colors.lightGray, colors.black)
    centerTextIn(w - rightW, infoY + 2, rightW - 1, tostring(bet), colors.white, colors.black)

    -- Message banner
    local msgY = h - 4
    frameRect(2, msgY, w - 2, 2, colors.gray, colors.black)
    centerTextIn(2, msgY + 1, w - 2, tostring(message or ""), colors.yellow, colors.black)

    -- Footer
    drawFooter("Bet", "Spin", "Exit")
end

local function spin(player)
    if creditsAPI.get(player.mountPath) < player.bet then
        return "Not enough credits!"
    end
    
    creditsAPI.remove(player.bet, player.mountPath)
    
    -- Animation
    for i=1,20 do
        for r=1,3 do reelPos[r] = (reelPos[r] % #REELS[r]) + 1 end
        drawMachine(player.bet, "Spinning...", player.name, creditsAPI.get(player.mountPath))
        audio.playShuffle()
        sleep(0.05)
    end
    
    -- Stop one by one
    for r=1,3 do
        for i=1,10 do
            reelPos[r] = (reelPos[r] % #REELS[r]) + 1
            for k=r+1,3 do reelPos[k] = (reelPos[k] % #REELS[k]) + 1 end
            drawMachine(player.bet, "Spinning...", player.name, creditsAPI.get(player.mountPath))
            sleep(0.05 + i*0.01)
        end
        audio.playSlotStop()
    end
    
    -- Check Win
    local win = 0
    local function getSym(r, offset)
        return REELS[r][(reelPos[r] + offset - 1) % #REELS[r] + 1]
    end
    
    local function checkLine(offset)
        local s1, s2, s3 = getSym(1, offset), getSym(2, offset), getSym(3, offset)
        if s1 == s2 and s2 == s3 then return PAYOUTS[s1] end
        if s1 == "Cherry" and s2 == "Cherry" then return 5 end
        return 0
    end
    
    if player.bet >= 1 then win = win + checkLine(1) end -- Center (offset 1)
    if player.bet >= 2 then win = win + checkLine(0) end -- Top (offset 0)
    if player.bet >= 3 then win = win + checkLine(2) end -- Bottom (offset 2)
    
    if win > 0 then
        creditsAPI.add(win, player.mountPath)
        audio.playWin()
        
        -- Flash Effect
        for i=1,3 do
            drawMachine(player.bet, "WINNER! " .. win, player.name, creditsAPI.get(player.mountPath))
            sleep(0.1)
            term.setBackgroundColor(colors.lime)
            term.clear()
            sleep(0.1)
        end
        return "WINNER! " .. win
    else
        audio.playLose()
        return "Try again!"
    end
end

local function waitForBreakEvent(seconds)
    local timerId
    if seconds and seconds > 0 then
        timerId = os.startTimer(seconds)
    end

    while true do
        local e, p1 = os.pullEvent()

        if e == "disk" then
            return { type = "disk", event = e, p1 = p1 }
        end

        local button = input.getButton(e, p1)
        if button then
            return { type = "button", button = button, event = e, p1 = p1 }
        end

        if e == "key" or e == "char" then
            return { type = "key", event = e, p1 = p1 }
        end

        if timerId and e == "timer" and p1 == timerId then
            return { type = "timeout" }
        end
    end
end

local function runAttractMode()
    local fakeName = "CPU"
    local fakeCredits = 999

    local function computeWin(bet)
        local function getSym(r, offset)
            return REELS[r][(reelPos[r] + offset - 1) % #REELS[r] + 1]
        end
        local function checkLine(offset)
            local s1, s2, s3 = getSym(1, offset), getSym(2, offset), getSym(3, offset)
            if s1 == s2 and s2 == s3 then return PAYOUTS[s1] end
            if s1 == "Cherry" and s2 == "Cherry" then return 5 end
            return 0
        end

        local win = 0
        if bet >= 1 then win = win + checkLine(1) end
        if bet >= 2 then win = win + checkLine(0) end
        if bet >= 3 then win = win + checkLine(2) end
        return win
    end

    local function demoSpinOnce(bet)
        -- Animation
        for _ = 1, 20 do
            for r = 1, 3 do
                reelPos[r] = (reelPos[r] % #REELS[r]) + 1
            end
            drawMachine(bet, "ATTRACTION MODE - Spinning... (Insert Disk)", fakeName, fakeCredits)
            audio.playShuffle()
            local brk = waitForBreakEvent(0.05)
            if brk and brk.type == "disk" then return brk end
        end

        -- Stop one by one
        for r = 1, 3 do
            for i = 1, 10 do
                reelPos[r] = (reelPos[r] % #REELS[r]) + 1
                for k = r + 1, 3 do
                    reelPos[k] = (reelPos[k] % #REELS[k]) + 1
                end
                drawMachine(bet, "ATTRACTION MODE - Spinning... (Insert Disk)", fakeName, fakeCredits)
                local brk = waitForBreakEvent(0.05 + i * 0.01)
                if brk and brk.type == "disk" then return brk end
            end
            audio.playSlotStop()
        end

        local win = computeWin(bet)
        if win > 0 then
            audio.playWin()
            for _ = 1, 3 do
                drawMachine(bet, "ATTRACTION MODE - WINNER! " .. tostring(win), fakeName, fakeCredits)
                local brk = waitForBreakEvent(0.12)
                if brk and brk.type == "disk" then return brk end
                term.setBackgroundColor(colors.lime)
                term.clear()
                brk = waitForBreakEvent(0.08)
                if brk and brk.type == "disk" then return brk end
            end
        else
            audio.playLose()
            drawMachine(bet, "ATTRACTION MODE - Try again! (Insert Disk)", fakeName, fakeCredits)
            local brk = waitForBreakEvent(0.8)
            if brk and brk.type == "disk" then return brk end
        end
        return nil
    end

    while true do
        local bet = math.random(1, 3)
        drawMachine(bet, "ATTRACTION MODE - Insert Disk to Play", nil, nil)
        local brk = waitForBreakEvent(0.6)
        if brk and brk.type == "disk" then return brk end

        brk = demoSpinOnce(bet)
        if brk and brk.type == "disk" then return brk end

        drawMachine(bet, "ATTRACTION MODE - Next spin... (Insert Disk)", nil, nil)
        brk = waitForBreakEvent(0.8)
        if brk and brk.type == "disk" then return brk end
    end
end

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------

local function main()
    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        if w >= 34 and h >= 19 then
            -- Lobby art
            blitFill(1, 1, w, 1, " ", colors.white, colors.blue)
            centerTextIn(1, 1, w, " SUPER SLOTS ", colors.yellow, colors.blue)
            local artX = clamp(cx - 16, 2, w - 32)
            local artY = clamp(cy - 6, 2, h - 12)
            shadowRect(artX, artY, 32, 10, colors.black)
            frameRect(artX, artY, 32, 10, colors.gray, colors.lightGray)
            blitFill(artX + 1, artY + 1, 30, 1, " ", colors.white, colors.orange)
            centerTextIn(artX + 1, artY + 1, 30, " INSERT CARDS ", colors.white, colors.orange)

            frameRect(artX + 4, artY + 3, 7, 5, colors.gray, colors.white)
            frameRect(artX + 13, artY + 3, 7, 5, colors.gray, colors.white)
            frameRect(artX + 22, artY + 3, 7, 5, colors.gray, colors.white)
            centerTextIn(artX + 4, artY + 5, 7, "@@@", colors.red, colors.white)
            centerTextIn(artX + 13, artY + 5, 7, "===", colors.lightGray, colors.white)
            centerTextIn(artX + 22, artY + 5, 7, "777", colors.red, colors.white)

            drawCenter(artY + 10, "Insert Cards (Max 3)", colors.white, colors.black)
            drawCenter(artY + 12, "[C] Start   [R] Exit", colors.gray, colors.black)
        else
            drawCenter(h/2 - 2, "SUPER SLOTS", colors.gold, colors.black)
            drawCenter(h/2, "Insert Cards (Max 3)", colors.white, colors.black)
            drawCenter(h/2 + 2, "[C] Start   [R] Exit", colors.gray, colors.black)
        end
        
        -- Lobby Loop
        local detectedCards = {}
        local attractDelay = 8
        local attractTimer = os.startTimer(attractDelay)
        while true do
            local event, p1 = os.pullEvent()

            if event == "timer" and p1 == attractTimer and #detectedCards == 0 then
                -- CPU demo until a disk is inserted (attract mode)
                runAttractMode()

                -- Redraw lobby after attract mode
                term.setBackgroundColor(colors.black)
                term.clear()
                if w >= 34 and h >= 19 then
                    blitFill(1, 1, w, 1, " ", colors.white, colors.blue)
                    centerTextIn(1, 1, w, " SUPER SLOTS ", colors.yellow, colors.blue)
                    local artX = clamp(cx - 16, 2, w - 32)
                    local artY = clamp(cy - 6, 2, h - 12)
                    shadowRect(artX, artY, 32, 10, colors.black)
                    frameRect(artX, artY, 32, 10, colors.gray, colors.lightGray)
                    blitFill(artX + 1, artY + 1, 30, 1, " ", colors.white, colors.orange)
                    centerTextIn(artX + 1, artY + 1, 30, " INSERT CARDS ", colors.white, colors.orange)

                    frameRect(artX + 4, artY + 3, 7, 5, colors.gray, colors.white)
                    frameRect(artX + 13, artY + 3, 7, 5, colors.gray, colors.white)
                    frameRect(artX + 22, artY + 3, 7, 5, colors.gray, colors.white)
                    centerTextIn(artX + 4, artY + 5, 7, "@@@", colors.red, colors.white)
                    centerTextIn(artX + 13, artY + 5, 7, "===", colors.lightGray, colors.white)
                    centerTextIn(artX + 22, artY + 5, 7, "777", colors.red, colors.white)

                    drawCenter(artY + 10, "Insert Cards (Max 3)", colors.white, colors.black)
                    drawCenter(artY + 12, "[C] Start   [R] Exit", colors.gray, colors.black)
                else
                    drawCenter(h/2 - 2, "SUPER SLOTS", colors.gold, colors.black)
                    drawCenter(h/2, "Insert Cards (Max 3)", colors.white, colors.black)
                    drawCenter(h/2 + 2, "[C] Start   [R] Exit", colors.gray, colors.black)
                end

                -- Refresh cards and reset timer
                detectedCards = creditsAPI.findCards()
                attractTimer = os.startTimer(attractDelay)
            end

            -- Arcade button controls (works for redstone + key-based configs)
            local button = input.getButton(event, p1)
            if button == "CENTER" then
                if #detectedCards > 0 then break end
                drawCenter(h/2 + 4, "No players detected!", colors.red, colors.black)
                sleep(1)
                term.setCursorPos(1, h/2+4) term.clearLine()
                attractTimer = os.startTimer(attractDelay)
            elseif button == "RIGHT" then
                term.setBackgroundColor(colors.black)
                term.clear()
                if fs.exists("menu.lua") then shell.run("menu.lua") end
                return
            end

            if event == "key" then
                local key = keys.getName(p1)
                if key == "enter" or key == "space" then -- Start
                    if #detectedCards > 0 then break end
                    drawCenter(h/2 + 4, "No players detected!", colors.red, colors.black)
                    sleep(1)
                    term.setCursorPos(1, h/2+4) term.clearLine()
                    attractTimer = os.startTimer(attractDelay)
                elseif key == "backspace" or key == "e" then -- Exit
                     term.setBackgroundColor(colors.black)
                     term.clear()
                     if fs.exists("menu.lua") then shell.run("menu.lua") end
                     return
                end
            elseif event == "disk" or event == "disk_eject" then
                -- Refresh cards
                detectedCards = creditsAPI.findCards()
                attractTimer = os.startTimer(attractDelay)
                term.setCursorPos(1, h/2 + 4)
                term.clearLine()
                local msg = "Players: "
                for i, c in ipairs(detectedCards) do
                    msg = msg .. c.name .. " "
                end
                drawCenter(h/2 + 4, msg, colors.yellow, colors.black)
            end
            
            -- Initial scan
             if #detectedCards == 0 then
                 detectedCards = creditsAPI.findCards()
                 if #detectedCards > 0 then
                    attractTimer = os.startTimer(attractDelay)
                    term.setCursorPos(1, h/2 + 4)
                    term.clearLine()
                    local msg = "Players: "
                    for i, c in ipairs(detectedCards) do
                        msg = msg .. c.name .. " "
                    end
                    drawCenter(h/2 + 4, msg, colors.yellow, colors.black)
                end
            end
        end
        
        local players = {}
        for i, card in ipairs(detectedCards) do
            if i > 3 then break end
            creditsAPI.lock(card.path)
            table.insert(players, {
                bet=1, 
                name=card.name,
                mountPath=card.path 
            })
        end
        
        -- Game Loop
        local msg = "Welcome!"
        while true do
            local allQuit = false
            
            for i, p in ipairs(players) do
                while true do
                    drawMachine(p.bet, p.name .. ": " .. msg, p.name, creditsAPI.get(p.mountPath))
                    local action = waitKey()
                    
                    if action == "LEFT" then
                        p.bet = (p.bet % 3) + 1
                        audio.playChip()
                        msg = "Bet changed"
                    elseif action == "CENTER" then
                        msg = spin(p)
                        break -- Turn done
                    elseif action == "RIGHT" then
                        -- Player leaving?
                        allQuit = true
                        break
                    end
                end
                if allQuit then break end
            end
            
            if allQuit then break end
        end
        
        -- Unlock cards
        for _, p in ipairs(players) do
            creditsAPI.unlock(p.mountPath)
        end
    end
end

main()
