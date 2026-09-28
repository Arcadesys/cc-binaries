-- Launch every registered app, let it run briefly, and check it didn't crash,
-- then close it and check the palette is back to the theme.
local H = require("helpers")
local apps = require("sys.apps")

local function screenText(parent)
    local w, h = parent.getSize()
    local all = {}
    for y = 1, h do all[#all + 1] = (parent.getLine(y)) end
    return table.concat(all, "\n")
end

local cases = {}
for _, m in ipairs(apps.scan("arcadeos", { turtle = false })) do
    if not m.skipSmoke then
        cases[#cases + 1] = { "launches " .. m.id, function(T)
            H.withKernel(function(k, parent)
                if m.requires.speaker and not peripheral.find("speaker") and periphemu then
                    periphemu.create("top", "speaker")
                end
                local id, err = k:launch(m.id)
                T.ok(id, "launch failed: " .. tostring(err))
                H.pump(k, m.smokeSeconds or 0.6)
                local p = k:byId(id)
                T.ok(p and not p.dead, m.id .. " exited early" .. (p and p.error and (": " .. p.error) or ""))
                local text = screenText(parent)
                T.ok(not text:find("Program ended with an error", 1, true), m.id .. " crashed:\n" .. text)
                T.ok(not text:find("No such program", 1, true), m.id .. " entry missing:\n" .. text)
                k:close(p)
                H.pump(k, 0.1)
                if not p.dead then k:kill(p); k:reap() end
                k:render()
                T.ok(H.paletteIsTheme(parent), m.id .. " left the palette modified")
            end)
        end }
    end
end
return cases
