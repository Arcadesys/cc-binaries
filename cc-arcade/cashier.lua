-- cashier.lua
-- Arcade Cashier System
-- Handles Credit Cards (Floppy Disks) and Currency Exchange

local input = require("input")
local credits = require("credits")
local audio = require("audio")

-- === CONFIGURATION ===
local RATES_INPUT = {
    ["minecraft:diamond"] = 1,
    ["minecraft:obsidian"] = 4,
    ["minecraft:ender_eye"] = 16
}

local RATES_OUTPUT = {
    ["minecraft:diamond"] = 1,
    ["minecraft:ender_pearl"] = 16
}

local SCREENSAVER_TIMEOUT = 10 -- Seconds of inactivity before screensaver
local SCREENSAVER_DIR = "screensavers"

-- === PERIPHERALS ===
local drive = peripheral.find("drive")
local bridge = nil -- Deprecated: Replaced by Bank Chest
local monitors = { peripheral.find("monitor") }

-- Find all connected inventories
local function findAllInventories()
    local invs = {}
    for _, name in ipairs(peripheral.getNames()) do
        -- Wrap the peripheral
        local p = peripheral.wrap(name)
        
        -- Check if it's an inventory (has .list and .size)
        -- Also explicitly exclude things we know aren't "storage" chests for our purpose
        -- (like disk drives which technically have inventory space sometimes, or strict exclusions)
        local type = peripheral.getType(p)
        
        -- Exclude common non-chest peripherals
        if type ~= "drive" and type ~= "monitor" and type ~= "speaker" and type ~= "modem" and type ~= "computer" then
            -- Verify it has inventory methods
            if p.list and p.size and p.pushItems and p.pullItems then
                table.insert(invs, p)
            end
        end
    end
    return invs
end

local allInventories = findAllInventories()

local mon = nil
if #monitors > 0 then
    mon = monitors[1]
    mon.setTextScale(1)
    if mon.isColor() then
        term.redirect(mon)
    end
end

local w, h = term.getSize()

-- === STATE MANAGEMENT ===
local lastActivity = os.clock()
local chestConfig = nil -- Will hold { customer = "name", bank = "name" }

local function resetActivity()
    lastActivity = os.clock()
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function centerText(y, text, color)
    term.setCursorPos(1, y)
    term.clearLine()
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    if color then term.setTextColor(color) end
    term.write(text)
end

-- === CONFIGURATION WIZARD ===

-- Rename a peripheral via wired modem (CC:Tweaked)
local function renamePeripheral(oldName, newName)
    -- Find the modem that this peripheral is connected to
    for _, modemName in ipairs(peripheral.getNames()) do
        local modem = peripheral.wrap(modemName)
        if modem and type(modem.getNameLocal) == "function" then
            -- Check if this modem has the peripheral
            local names = modem.getNamesRemote and modem.getNamesRemote() or {}
            for _, name in ipairs(names) do
                if name == oldName then
                    -- Found it! Rename via this modem
                    if modem.setNameLocal then
                        local ok = pcall(function() modem.setNameLocal(oldName, newName) end)
                        if ok then return newName end
                    end
                end
            end
        end
    end
    -- Fallback: return original name if rename failed
    return oldName
end

local function loadChestConfig()
    -- Try to load saved config first
    if fs.exists(".chest_config") then
        local f = fs.open(".chest_config", "r")
        if f then
            local data = f.readAll()
            f.close()
            local loaded = textutils.unserialize(data)
            if loaded and loaded.bank and loaded.customer then
                -- Verify the peripherals still exist
                local bankExists = peripheral.isPresent(loaded.bank)
                local customerExists = peripheral.isPresent(loaded.customer)
                if bankExists and customerExists then
                    return loaded
                end
            end
        end
    end
    return nil
end

local function configureChests()
    -- Priority 0: Load saved config if valid
    local savedConfig = loadChestConfig()
    if savedConfig then
        chestConfig = savedConfig
        return
    end

    -- Priority 1: Check for explicit "bank" and "drawer" named peripherals
    local hasBank = peripheral.isPresent("bank")
    local hasDrawer = peripheral.isPresent("drawer")

    if hasBank and hasDrawer then
        -- Rename to unique CLI-friendly names
        local drawerName = renamePeripheral("drawer", "cashier_drawer")
        local bankName = renamePeripheral("bank", "cashier_bank")
        
        chestConfig = { bank = bankName, customer = drawerName }
        
        -- Save config
        local f = fs.open(".chest_config", "w")
        f.write(textutils.serialize(chestConfig))
        f.close()
        return
    end
    
    -- Priority 1b: Check for already-renamed cashier chests
    local hasCashierBank = peripheral.isPresent("cashier_bank")
    local hasCashierDrawer = peripheral.isPresent("cashier_drawer")
    
    if hasCashierBank and hasCashierDrawer then
        chestConfig = { bank = "cashier_bank", customer = "cashier_drawer" }
        
        local f = fs.open(".chest_config", "w")
        f.write(textutils.serialize(chestConfig))
        f.close()
        return
    end

    -- Priority 2: Wizard (Mandatory if not named bank/drawer)
    while true do
        allInventories = findAllInventories()
        
        if #allInventories < 2 then
            clear()
            centerText(h/2-1, "SETUP ERROR", colors.red)
            centerText(h/2+1, "Need 2 Chests Connected", colors.white)
            centerText(h/2+2, "Found: " .. #allInventories, colors.gray)
            sleep(2)
        else
            clear()
            centerText(2, "PAYMENT CONFIG", colors.cyan)
            
            centerText(4, "Hardware Names:", colors.gray)
            centerText(5, "'bank' & 'drawer' not found.", colors.red)
            
            centerText(7, "Step 1: EMPTY All Chests", colors.yellow)
            centerText(9, "Step 2: Put 1 DIAMOND in", colors.yellow)
            centerText(10, "the DRAWER (Input) Chest", colors.yellow) 
            
            centerText(h-2, "Scanning...", colors.gray)
            
            -- Scan loop
            local customerChestName = nil
            local bankChestName = nil
            
            for _, inv in ipairs(allInventories) do
                local items = inv.list()
                for slot, item in pairs(items) do
                    if item.name == "minecraft:diamond" then
                        customerChestName = peripheral.getName(inv)
                        break
                    end
                end
                if customerChestName then break end
            end
            
            if customerChestName then
                -- Automatically assign the first OTHER chest as Bank
                for _, inv in ipairs(allInventories) do
                    local name = peripheral.getName(inv)
                    if name ~= customerChestName then
                        bankChestName = name
                        break
                    end
                end
                
                if bankChestName then
                   clear()
                   centerText(h/2-1, "CONFIG SUCCESS!", colors.lime)
                   centerText(h/2+1, "Renaming chests...", colors.yellow)
                   
                   -- Rename chests to unique, CLI-friendly names
                   local newDrawerName = renamePeripheral(customerChestName, "cashier_drawer")
                   local newBankName = renamePeripheral(bankChestName, "cashier_bank")
                   
                   -- Update names if rename succeeded
                   if newDrawerName ~= customerChestName then
                       customerChestName = newDrawerName
                   end
                   if newBankName ~= bankChestName then
                       bankChestName = newBankName
                   end
                   
                   clear()
                   centerText(h/2-1, "CONFIG SUCCESS!", colors.lime)
                   centerText(h/2+1, "Drawer: " .. customerChestName, colors.gray)
                   centerText(h/2+2, "Bank: " .. bankChestName, colors.gray)
                   
                   chestConfig = { customer = customerChestName, bank = bankChestName }
                   
                   local f = fs.open(".chest_config", "w")
                   f.write(textutils.serialize(chestConfig))
                   f.close()
                   
                   centerText(h-2, "Please Remove Diamond", colors.yellow)
                   sleep(3)
                   
                   -- Wait for diamond removal
                   while true do
                        local hasItem = false
                        local inv = peripheral.wrap(customerChestName)
                        for k,v in pairs(inv.list()) do hasItem = true end
                        if not hasItem then break end
                        sleep(0.5)
                   end
                   return
                end
            end
            sleep(1)
        end
    end
end

-- === ANIMATIONS ===

local function animateCountUp(startVal, endVal, y, labelColor, valColor)
    local steps = 10
    local delay = 0.05
    local diff = endVal - startVal
    
    if diff == 0 then return end
    
    for i = 1, steps do
        local current = math.floor(startVal + (diff * (i/steps)))
        centerText(y, "CREDITS: " .. current, valColor or colors.yellow)
        sleep(delay)
    end
end

local function animateScanning(y)
    local frames = {
        "ScAnNiNg...",
        "sCaNnInG...",
        "ScAnNiNg...",
        "sCaNnInG..."
    }
    for _, f in ipairs(frames) do
        centerText(y, f, colors.yellow)
        sleep(0.1)
    end
end

local function animateDispense(y)
    centerText(y, "Dispensing...", colors.yellow)
    audio.playCoinDispense()
    for i=1,3 do
        centerText(y, "Dispensing" .. string.rep(".", i), colors.yellow)
        sleep(0.15)
    end
end

-- === SCREENSAVER ===
local function runScreensaver()
    if not fs.exists(SCREENSAVER_DIR) or not fs.isDir(SCREENSAVER_DIR) then
        return
    end
    
    local files = fs.list(SCREENSAVER_DIR)
    if #files == 0 then return end
    
    local randomFile = files[math.random(1, #files)]
    local fullPath = fs.combine(SCREENSAVER_DIR, randomFile)
    
    local function screensaverRoutine()
        shell.run(fullPath)
    end
    
    local function inputWatcher()
        local ev, p1 = os.pullEvent()
        while true do
            if ev == "key" or ev == "mouse_click" or ev == "monitor_touch" or ev == "disk" then
                return true
            end
            ev, p1 = os.pullEvent()
        end
    end
    
    parallel.waitForAny(screensaverRoutine, inputWatcher)
    
    resetActivity()
    clear()
end

-- === LOGIC ===

local function scanIOChest()
    if not chestConfig then return 0, {} end
    local cust = peripheral.wrap(chestConfig.customer)
    if not cust then return 0, {} end
    
    local total = 0
    local items = {}
    
    for slot, item in pairs(cust.list()) do
        local rate = RATES_INPUT[item.name]
        if rate then
            local val = rate * item.count
            total = total + val
            table.insert(items, {slot=slot, name=item.name, count=item.count, value=val})
        else
             -- Also track invalid items to move them to bank (garbage collection)
             table.insert(items, {slot=slot, name=item.name, count=item.count, value=0, garbage=true})
        end
    end
    return total, items
end

local function safeTransfer(fromObj, fromName, toObj, toName, fromSlot, count)
    local moved = 0

    -- Attempt 1: Push from Source
    local pushOk, pushRes = pcall(function()
        return fromObj.pushItems(toName, fromSlot, count)
    end)

    if pushOk and type(pushRes) == "number" and pushRes > 0 then
        moved = pushRes
        if moved >= count then
            return moved
        end
    end

    -- Attempt 2: Pull remaining from Destination
    local remaining = count - moved
    local pullOk, pullRes = pcall(function()
        return toObj.pullItems(fromName, fromSlot, remaining)
    end)

    if pullOk and type(pullRes) == "number" and pullRes > 0 then
        moved = moved + pullRes
    end

    if moved > 0 then
        return moved
    end

    -- Return error info (includes successful 0-move results for debugging)
    local err = "Transfer Failed."
    err = err .. " Push: " .. tostring(pushRes)
    err = err .. " Pull: " .. tostring(pullRes)
    if not pushOk then err = err .. " (push error)" end
    if not pullOk then err = err .. " (pull error)" end
    return 0, err
end

local function depositItems(items)
    if not chestConfig then return false, "No Config" end
    local cust = peripheral.wrap(chestConfig.customer)
    local bank = peripheral.wrap(chestConfig.bank)
    
    if not cust or not bank then return false, "Chest Missing" end
    
    local totalCredits = 0
    local lastError = nil
    
    for _, item in ipairs(items) do
        -- Move item from Customer to Bank using safe transfer
        local moved, err = safeTransfer(cust, chestConfig.customer, bank, chestConfig.bank, item.slot, item.count)
        
        if moved and moved > 0 and not item.garbage then
             local rate = RATES_INPUT[item.name]
             if rate then
                totalCredits = totalCredits + (moved * rate)
             end
        elseif err then
            lastError = err
        end
    end
    
    return true, totalCredits, lastError
end

local function withdrawItem(itemName, count)
    if not chestConfig then return 0 end
    local cust = peripheral.wrap(chestConfig.customer)
    local bank = peripheral.wrap(chestConfig.bank)
    if not cust or not bank then return 0 end
    
    -- Find item in Bank
    local transferred = 0
    local hasAny = false
    local lastError = nil
    for slot, item in pairs(bank.list()) do
        if item.name == itemName then
            hasAny = true
            local needed = count - transferred
            
            -- Bank -> Customer
            local pushed, err = safeTransfer(bank, chestConfig.bank, cust, chestConfig.customer, slot, needed)
            if err then lastError = err end
            
            transferred = transferred + pushed
            if transferred >= count then break end
        end
    end

    if transferred > 0 then
        return transferred, "ok"
    end
    if not hasAny then
        return 0, "out_of_stock"
    end
    return 0, "transfer_failed", lastError
end

-- === MENUS ===

local function menuDeposit(cardPath)
    -- Initial scan
    local val, items = scanIOChest()
    
    while true do
        clear()
        centerText(2, "DEPOSIT ITEMS", colors.yellow)
        centerText(4, "Place items in chest", colors.white)
        centerText(5, "Diamonds (1), Obsidian (4)", colors.gray)
        centerText(6, "Eyes of Ender (16)", colors.gray)
        
        -- Sum only valid values for display
        local displayVal = 0
        for _, it in ipairs(items) do if not it.garbage then displayVal = displayVal + it.value end end
        
        if displayVal > 0 then
            centerText(8, "Detected: " .. displayVal .. " Credits", colors.lime)
        else
            centerText(8, "Scanning Chest...", colors.gray)
        end
        
        centerText(h-2, "[BTN 1] Confirm & Deposit", colors.lime)
        centerText(h-1, "[BTN 3] Back", colors.red)
        
        local timer = os.startTimer(0.5)
        local event, p1 = os.pullEvent()
        
        if event == "timer" then
             _, items = scanIOChest()
        else
            resetActivity()
            local btn = input.getButton(event, p1)
            
            if btn == "LEFT" then -- Button 1
                audio.playClick()
                -- Filter items list to ensure we actually have something to move (even garbage)
                if #items > 0 then
                    animateScanning(h-4)
                    local success, result, err = depositItems(items)
                    
                    if success then
                        if type(result) == "number" and result > 0 then
                             audio.playCashRegister()
                             credits.add(result, cardPath)
                             
                             clear()
                             centerText(h/2, "DEPOSIT SUCCESS", colors.lime)
                             centerText(h/2+1, "+" .. result .. " CREDITS", colors.yellow)
                             sleep(1.5)
                             return
                        elseif result == 0 then
                            -- Only garbage moved or transfer failed
                             clear()
                             if err and (string.find(err, "Target") or string.find(err, "target")) then
                                 centerText(h/2-2, "NETWORK ERROR", colors.red)
                                 centerText(h/2, "Chests cannot see each other", colors.white)
                                 centerText(h/2+1, "Connect WIRED MODEMS to BOTH", colors.yellow)
                                 centerText(h/2+2, "Chests/Barrels", colors.yellow)
                                 sleep(6)
                             else
                                 centerText(h/2, "Invalid Items Stored", colors.red)
                                 if err then
                                    centerText(h/2+2, string.sub(err, 1, 38), colors.gray) 
                                 end
                                 sleep(3.5)
                             end
                        else
                             audio.playError()
                             centerText(h-4, "Error: 0 Deposited", colors.red)
                             sleep(1)
                        end
                    else
                         audio.playError()
                         centerText(h-4, "Error: " .. tostring(result), colors.red)
                         sleep(2)
                    end
                    _, items = scanIOChest()
                else
                    audio.playError()
                    centerText(h-4, "Chest Empty", colors.red)
                    sleep(0.5)
                end
                
            elseif btn == "RIGHT" then -- Button 3
                audio.playClick()
                return
            end
        end
    end
end

local function menuWithdraw(cardPath)
    local currentSelection = 1 
    local options = {
        { name = "Diamond", id="minecraft:diamond", cost = 1, rate = 1, label="1 Credit -> 1 Diamond" },
        { name = "Ender Pearl", id="minecraft:ender_pearl", cost = 16, rate = 16, label="16 Credits -> 1 Pearl" }
    }
    
    while true do
        clear()
        local currentCreds = credits.get(cardPath)
        centerText(2, "CASH OUT", colors.yellow)
        centerText(3, "Credits: " .. currentCreds, colors.white)
        
        for i, opt in ipairs(options) do
            local y = 5 + (i * 3)
            local prefix = (i == currentSelection) and "> " or "  "
            local color = (i == currentSelection) and colors.lime or colors.gray
            centerText(y, prefix .. opt.name, color)
            centerText(y+1, "(" .. opt.label .. ")", colors.gray)
        end
        
        centerText(h-2, "[1] Select   [2] Confirm", colors.cyan)
        centerText(h-1, "[3] Back", colors.red)
        
        local event, p1 = os.pullEvent()
        resetActivity()
        local btn = input.getButton(event, p1)
        
        if btn == "LEFT" then -- Cycle Selection
            audio.playClick()
            currentSelection = currentSelection + 1
            if currentSelection > #options then currentSelection = 1 end
            
        elseif btn == "CENTER" then -- Confirm
            audio.playConfirm()
            local opt = options[currentSelection]
            
            if currentCreds >= opt.rate then
                clear()
                centerText(h/2-2, "Dispensing " .. opt.name, colors.white)
                
                local moved, status, err = withdrawItem(opt.id, 1)
                
                if moved and moved >= 1 then
                    animateDispense(h/2)
                    credits.remove(opt.rate, cardPath)
                    
                    clear()
                    centerText(h/2, "Please Take Item", colors.lime)
                    sleep(1)
                else
                    audio.playError()
                    if status == "out_of_stock" then
                        centerText(h/2+2, "Bank Empty!", colors.red)
                        sleep(1.5)
                    elseif err and (string.find(err, "Target") or string.find(err, "target")) then
                        centerText(h/2-2, "NETWORK ERROR", colors.red)
                        centerText(h/2, "Chests cannot see each other", colors.white)
                        centerText(h/2+1, "Connect WIRED MODEMS to BOTH", colors.yellow)
                        centerText(h/2+2, "Chests/Barrels", colors.yellow)
                        sleep(6)
                    else
                        centerText(h/2-1, "TRANSFER ERROR", colors.red)
                        if err then
                            centerText(h/2+1, string.sub(tostring(err), 1, 38), colors.gray)
                        end
                        sleep(3)
                    end
                end
            else
                audio.playError()
                centerText(h-3, "Insufficient Credits!", colors.red)
                sleep(1)
            end
            
        elseif btn == "RIGHT" then -- Back
            audio.playClick()
            return
        end
    end
end

local function menuMain(cardPath)
    local lastCredits = credits.get(cardPath)

    while true do
        if not drive or not drive.isDiskPresent() then return end 
        
        local name = credits.getName(cardPath) or "Player"
        local bal = credits.get(cardPath)
        
        clear()
        centerText(2, "WELCOME, " .. string.upper(name), colors.cyan)
        
        -- Credits Display
        centerText(4, "CREDITS: " .. bal, colors.yellow)
        
        centerText(7, "[1] DEPOSIT Items", colors.white)
        centerText(9, "[2] CASH OUT", colors.white)
        centerText(11, "[3] EJECT CARD", colors.red)
        
        -- Fun check for items waiting
        local val, _ = scanIOChest()
        if val > 0 then
             centerText(h-1, "Items Detected! Use [1]", colors.lime)
        end
        
        local event, p1 = os.pullEvent()
        resetActivity()
        local btn = input.getButton(event, p1)
        
        if btn == "LEFT" then -- Deposit
            audio.playClick()
            menuDeposit(cardPath)
        elseif btn == "CENTER" then -- Cash Out
            audio.playClick()
            menuWithdraw(cardPath)
        elseif btn == "RIGHT" then -- Eject
            audio.playClick()
            if drive then drive.ejectDisk() end
            return
        end
    end
end

local function promptNewCard(cardPath)
    -- If card has no data/corrupt, prompt for initials
    if not credits.getName(cardPath) then
        -- Initialize with 0 credits first
        credits.set(0, cardPath)
        
        -- 3-letter initials input like arcade high score
        local initials = {"A", "A", "A"}
        local currentPos = 1
        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        
        local function getAlphabetIndex(char)
            return alphabet:find(char) or 1
        end
        
        local function cycleChar(char, direction)
            local idx = getAlphabetIndex(char)
            idx = idx + direction
            if idx < 1 then idx = #alphabet end
            if idx > #alphabet then idx = 1 end
            return alphabet:sub(idx, idx)
        end
        
        while true do
            clear()
            centerText(3, "NEW PLAYER CARD", colors.cyan)
            centerText(5, "Enter Your Initials", colors.white)
            
            -- Draw the 3 letter slots
            local slotY = h/2
            local startX = math.floor(w/2) - 3
            
            for i = 1, 3 do
                local x = startX + (i-1) * 3
                local color = (i == currentPos) and colors.yellow or colors.gray
                
                term.setCursorPos(x, slotY - 1)
                term.setTextColor(color)
                if i == currentPos then
                    term.write(" ^")
                else
                    term.write("  ")
                end
                
                term.setCursorPos(x, slotY)
                term.setTextColor(color)
                term.write("[" .. initials[i] .. "]")
                
                term.setCursorPos(x, slotY + 1)
                if i == currentPos then
                    term.write(" v")
                else
                    term.write("  ")
                end
            end
            
            centerText(slotY + 4, "[1] Change Letter", colors.lime)
            centerText(slotY + 5, "[2] Next / Confirm", colors.cyan)
            centerText(slotY + 6, "[3] Previous", colors.gray)
            
            local event, p1 = os.pullEvent()
            resetActivity()
            local btn = input.getButton(event, p1)
            
            if btn == "LEFT" then
                -- Cycle current letter
                audio.playClick()
                initials[currentPos] = cycleChar(initials[currentPos], 1)
                
            elseif btn == "CENTER" then
                audio.playClick()
                if currentPos < 3 then
                    -- Move to next position
                    currentPos = currentPos + 1
                else
                    -- Confirm initials
                    audio.playConfirm()
                    local name = table.concat(initials)
                    credits.setName(name, cardPath)
                    
                    -- Also set the disk label
                    if drive then
                        drive.setDiskLabel(name)
                    end
                    
                    clear()
                    centerText(h/2 - 1, "WELCOME", colors.lime)
                    centerText(h/2 + 1, name, colors.yellow)
                    sleep(1.5)
                    break
                end
                
            elseif btn == "RIGHT" then
                audio.playClick()
                if currentPos > 1 then
                    currentPos = currentPos - 1
                end
            end
        end
    end
    menuMain(cardPath)
end



local function checkHardware()
    local errors = {}
    
    -- 1. Inventory Check
    allInventories = findAllInventories()
    if #allInventories < 2 then
        table.insert(errors, "Need 2 Connected Chests")
        table.insert(errors, "Found: " .. #allInventories)
    end
    
    -- 2. Speaker Check
    if not peripheral.find("speaker") then
        table.insert(errors, "Missing Speaker")
    end
    
    -- 3. Drive Check
    if not drive then
        table.insert(errors, "Missing Disk Drive")
    end
    
    -- 4. Redstone Config Check
    if not fs.exists(".button_config") then
        table.insert(errors, "Config Missing! Run config.lua")
    else
        local f = fs.open(".button_config", "r")
        local success, conf = pcall(function() return textutils.unserialize(f.readAll()) end)
        f.close()
        
        if not success or not conf or not conf.LEFT or not conf.CENTER or not conf.RIGHT then
            table.insert(errors, "Invalid Button Config")
        else
            local rsCount = 0
            if conf.LEFT.type == "redstone" then rsCount = rsCount + 1 end
            if conf.CENTER.type == "redstone" then rsCount = rsCount + 1 end
            if conf.RIGHT.type == "redstone" then rsCount = rsCount + 1 end
            
            if rsCount < 3 then
                table.insert(errors, "Need 3 Redstone Buttons")
            end
        end
    end
    
    if #errors > 0 then
        -- Force display to available output using standard print for safety
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        
        term.setTextColor(colors.red)
        print("HARDWARE CHECK FAILED")
        print("---------------------")
        
        term.setTextColor(colors.white)
        for i, err in ipairs(errors) do
            print("- " .. err)
        end
        
        print("")
        term.setTextColor(colors.yellow)
        print("Press any key to reboot...")
        os.pullEvent("key")
        os.reboot()
    end
    
    -- Config Wizard if needed
    configureChests()
    
    -- Success
    clear()
    centerText(h/2, "Hardware Verified", colors.lime)
    sleep(0.5)
end

-- === MAIN LOOP ===

local function main()
    checkHardware()

    while true do
        if not drive then
            clear()
            centerText(h/2, "Error: No Drive Found", colors.red)
            sleep(5)
            drive = peripheral.find("drive")
        else
            if drive.isDiskPresent() then
                resetActivity()
                local mount = drive.getMountPath()
                if mount then
                    promptNewCard(mount)
                else
                     sleep(0.5)
                end
            else
                -- IDLE STATE
                clear()
                centerText(h/2 - 1, "INSERT PLAYER CARD", colors.lime)
                
                -- Idle scan for customers putting things in input
                local val, _ = scanIOChest()
                if val > 0 then
                    resetActivity() 
                    centerText(h/2 + 1, "Items Detected!", colors.yellow)
                    centerText(h/2 + 2, "Insert Card to Deposit", colors.white)
                end
                
                if os.clock() - lastActivity > SCREENSAVER_TIMEOUT then
                    runScreensaver()
                end
                
                local timer = os.startTimer(1)
                local event, p1 = os.pullEvent()
                
                if event == "disk" then
                    resetActivity()
                elseif event == "timer" then
                    -- loop
                else
                    -- Input reset
                    local btn = input.getButton(event, p1)
                    if btn or event == "monitor_touch" or event == "mouse_click" or event == "char" or event == "key" then
                        resetActivity()
                    end
                end
            end
        end
    end
end

main()

