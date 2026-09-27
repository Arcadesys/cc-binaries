-- turtleos/lib/logger.lua

local logger = {}

function logger.log(message)
    print("[LOG] " .. message)
    -- In a real implementation, we might write to a file
end

function logger.error(message)
    printError("[ERROR] " .. message)
end

function logger.warn(message)
    print("[WARN] " .. message)
end

function logger.info(message)
    print("[INFO] " .. message)
end

return logger
