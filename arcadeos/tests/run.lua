-- Headless test runner. Writes /results/tests.txt; last line "PASS all N" on success.
package.path = "/arcadeos/?.lua;/arcadeos/?/init.lua;/arcadeos/tests/?.lua;" .. package.path

local only = { ... }
local SUITES = { "test_wm", "test_apps", "test_kernel", "test_ui", "test_smoke" }

local out = {}
local function log(line) out[#out + 1] = line end

local T = {}
T.failures = 0
function T.ok(v, msg)
    if not v then error("assertion failed: " .. tostring(msg), 2) end
end
function T.eq(a, b, msg)
    if a ~= b then
        error(("%s: expected %s, got %s"):format(msg or "eq", tostring(b), tostring(a)), 2)
    end
end
T.log = log

local total, failed = 0, 0
for _, suite in ipairs(SUITES) do
    local wanted = #only == 0
    for _, n in ipairs(only) do if n == suite or "test_" .. n == suite then wanted = true end end
    if wanted and fs.exists("/arcadeos/tests/" .. suite .. ".lua") then
        local okLoad, cases = pcall(require, suite)
        if not okLoad then
            failed = failed + 1
            log("FAIL " .. suite .. " (load): " .. tostring(cases))
        else
            for _, case in ipairs(cases) do
                total = total + 1
                local ok, err = pcall(case[2], T)
                if ok then
                    log("ok   " .. suite .. " :: " .. case[1])
                else
                    failed = failed + 1
                    log("FAIL " .. suite .. " :: " .. case[1] .. ": " .. tostring(err))
                end
            end
        end
    end
end

if failed == 0 then log("PASS all " .. total) else log(("FAILED %d of %d"):format(failed, total)) end
local h = fs.open("/results/tests.txt", "w")
h.write(table.concat(out, "\n") .. "\n")
h.close()
