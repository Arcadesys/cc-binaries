-- turtleos/lib/core.lua
local logger = require("turtleos.lib.logger")

local core = {}

function core.init()
    logger.info("TurtleOS initializing...")
    
    -- Simply launch the menu. The menu handles all user interaction.
    while true do
        local success = shell.run("turtleos/menu.lua")
        if not success then
            logger.error("Menu crashed or failed to load.")
            print("Press any key to retry or 'r' to reboot.")
            local event, key = os.pullEvent("char")
            if key == "r" then os.reboot() end
        end
    end
end

return core
