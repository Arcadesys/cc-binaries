-- Runs in a fresh emulator after `install.lua --local /src --yes`. Writes /results/install.txt.
local out = {}
local function check(ok, msg) out[#out + 1] = (ok and "ok   " or "FAIL ") .. msg end

check(fs.exists("/arcadeos/boot.lua"), "boot.lua installed")
check(not fs.exists("/arcadeos/tests"), "tests not installed")
check(not fs.exists("/arcadeos/tools"), "tools not installed")
check(not fs.exists("/pkg/arcade/menu.lua"), "arcade menu excluded")
check(not fs.exists("/pkg/factory/dist"), "factory bundle excluded")
check(fs.exists("/home") and fs.exists("/midi"), "user folders created")
local h = fs.open("/startup.lua", "r")
check(h and h.readAll():find("/arcadeos/boot.lua", 1, true) ~= nil, "startup.lua boots ArcadeOS")
if h then h.close() end

package.path = "/arcadeos/?.lua;" .. package.path
local apps = require("sys.apps")
local list, errors = apps.scan("arcadeos", { turtle = false })
check(#errors == 0, "manifests load: " .. table.concat(errors, "; "))
local ids = {}
for _, m in ipairs(list) do ids[#ids + 1] = m.id end
check(#list >= 20, ("%d apps visible: %s"):format(#list, table.concat(ids, ",")))
for _, want in ipairs({ "blackjack", "pinelinks", "minesweeper", "jukebox", "notepad" }) do
    check(apps.find(list, want) ~= nil, want .. " available")
end
check(fs.getFreeSpace("/") > 0, ("free space after install: %d"):format(fs.getFreeSpace("/")))

local failed = 0
for _, l in ipairs(out) do if l:sub(1, 4) == "FAIL" then failed = failed + 1 end end
out[#out + 1] = failed == 0 and "PASS install" or ("FAILED " .. failed)
local f = fs.open("/results/install.txt", "w")
f.write(table.concat(out, "\n") .. "\n")
f.close()
