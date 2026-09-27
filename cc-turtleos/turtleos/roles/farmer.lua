-- turtleos/roles/farmer.lua
local logger = require("turtleos.lib.logger")

local farmer = {}

function farmer.run(schema)
    logger.info("Starting Farmer Role...")
    
    local strategyName = schema.strategy
    if not strategyName then
        logger.error("No strategy defined for Farmer")
        return
    end

    local strategyPath = "turtleos.strategies.farmer." .. strategyName
    local success, strategy = pcall(require, strategyPath)

    if not success then
        logger.error("Failed to load strategy: " .. strategyPath)
        logger.error(strategy)
        return
    end

    logger.info("Executing strategy: " .. strategyName)
    
    while true do
        if strategy.execute then
            strategy.execute(schema)
        else
            logger.error("Strategy missing 'execute' function")
            break
        end
        sleep(1) -- Prevent infinite loop crash if strategy is instant
    end
end

return farmer
