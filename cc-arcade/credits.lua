local DEFAULT_CREDITS = 0 
local DEFAULT_NAME = "Guest"

local credits = {}

local function getFilePath(mountPath)
    return (mountPath or "disk") .. "/credits.json"
end

local function readData(mountPath)
    local path = getFilePath(mountPath)
    if not fs.exists(path) then
        return nil
    end
    
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    
    local data = textutils.unserializeJSON(content)
    return data
end

local function writeData(mountPath, data)
    local path = getFilePath(mountPath)
    -- Only write if the directory exists (disk is present)
    local dir = fs.getDir(path)
    if not fs.exists(dir) then
        return false 
    end

    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serializeJSON(data))
        f.close()
        return true
    end
    return false
end

-- Find all connected disks with credits info
function credits.findCards()
    local cards = {}
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "drive" then
            local path = disk.getMountPath(side)
            if path then
                local data = readData(path)
                if data then
                    table.insert(cards, {
                        path = path, 
                        side = side,
                        name = data.name or DEFAULT_NAME,
                        credits = data.credits or DEFAULT_CREDITS
                    })
                end
            end
        end
    end
    return cards
end

function credits.get(mountPath)
    if _G.ARCADE_DEV_MODE then
        return math.huge
    end

    local data = readData(mountPath)
    if not data or not data.credits then
        return DEFAULT_CREDITS
    end
    
    return tonumber(data.credits) or DEFAULT_CREDITS
end

function credits.getName(mountPath)
    local data = readData(mountPath)
    if not data or not data.name then
        return nil
    end
    return data.name
end

function credits.set(amount, mountPath)
    if _G.ARCADE_DEV_MODE then
        return true 
    end

    local data = readData(mountPath) or { name = DEFAULT_NAME }
    data.credits = math.floor(amount)
    
    return writeData(mountPath, data)
end

function credits.add(amount, mountPath)
    local current = credits.get(mountPath)
    local newAmount = current + amount
    credits.set(newAmount, mountPath)
    return newAmount
end

function credits.remove(amount, mountPath)
    if _G.ARCADE_DEV_MODE then
        return true 
    end

    local current = credits.get(mountPath)
    if current >= amount then
        credits.set(current - amount, mountPath)
        return true
    else
        return false
    end
end

function credits.setName(name, mountPath)
    local data = readData(mountPath) or { credits = DEFAULT_CREDITS }
    data.name = name
    return writeData(mountPath, data)
end

function credits.lock(mountPath)
    local data = readData(mountPath)
    if data then
        data.in_game = true
        writeData(mountPath, data)
    end
end

function credits.unlock(mountPath)
    local data = readData(mountPath)
    if data then
        data.in_game = false
        writeData(mountPath, data)
    end
end

return credits
