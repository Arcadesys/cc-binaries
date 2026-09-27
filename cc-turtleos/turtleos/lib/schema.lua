-- turtleos/lib/schema.lua

local schema = {}

function schema.load(path)
    if not fs.exists(path) then
        return nil, "Schema file not found: " .. path
    end

    local file = fs.open(path, "r")
    local content = file.readAll()
    file.close()

    local data = textutils.unserializeJSON(content)
    if not data then
        return nil, "Failed to parse schema JSON"
    end

    return data
end

return schema
