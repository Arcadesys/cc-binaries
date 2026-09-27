-- turtleos/roles/builder.lua
local logger = require("turtleos.lib.logger")

local builder = {}

function builder.run(schema)
    logger.info("Starting Builder Role...")
    -- Builder logic here
    -- Might load a blueprint from schema
end

return builder
