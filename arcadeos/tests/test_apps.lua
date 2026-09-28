local apps = require("sys.apps")

return {
    { "registry finds the built-in apps", function(T)
        local list, errors = apps.scan("arcadeos", { turtle = false })
        T.eq(#errors, 0, "manifest errors: " .. table.concat(errors, "; "))
        T.ok(apps.find(list, "executive"), "executive")
        T.ok(apps.find(list, "terminal"), "terminal")
    end },
    { "turtle-only apps are hidden on computers", function(T)
        local list = apps.scan("arcadeos", { turtle = false })
        for _, m in ipairs(list) do
            T.ok(not m.requires.turtle, m.id .. " should be hidden")
        end
    end },
    { "missing hardware is explained", function(T)
        local m = { name = "Jukebox", requires = { speaker = true } }
        T.ok(apps.missing(m, { speaker = false, color = true }), "no speaker")
        T.eq(apps.missing(m, { speaker = true, color = true }), nil, "speaker ok")
    end },
    { "manifest entries are absolute", function(T)
        for _, m in ipairs(apps.scan("arcadeos", { turtle = true })) do
            T.eq(m.entry:sub(1, 1), "/", m.id .. " entry absolute")
        end
    end },
}
