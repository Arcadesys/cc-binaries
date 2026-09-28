package.path = "/pkg/factory/?.lua;" .. package.path
local ok, err = require("lib_designer").run()
if ok == false and err then printError(err) end
