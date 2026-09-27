-- cc-screensaver installer (ComputerCraft:Tweaked)
-- Usage:
--   wget run <RAW_URL_TO_INSTALL_LUA>
-- Or (after copying install.lua onto the computer):
--   install [--base <raw_base_url>] [--branch <branch>] [--force] [--startup]

local args = { ... }

local function parseArgs(argv)
	local opts = {
		-- Point this at the directory containing the repo files (raw HTTP).
		-- Example:
		-- https://raw.githubusercontent.com/<owner>/<repo>/<branch>
		base = nil,
		branch = "main",
		force = false,
		startup = false,
	}

	local i = 1
	while i <= #argv do
		local a = argv[i]
		if a == "--base" then
			i = i + 1
			opts.base = argv[i]
		elseif a == "--branch" then
			i = i + 1
			opts.branch = argv[i]
		elseif a == "--force" then
			opts.force = true
		elseif a == "--startup" then
			opts.startup = true
		elseif a == "--help" or a == "-h" then
			print("cc-screensaver installer")
			print("Usage:")
			print("  install --base <raw_base_url> [--branch main] [--force] [--startup]")
			print("Notes:")
			print("  raw_base_url should be a directory URL containing screensaver.lua, startup.lua, and screensavers/*")
			return nil
		else
			print("Unknown arg: " .. tostring(a))
			print("Run with --help for usage")
			return nil
		end
		i = i + 1
	end

	return opts
end

local function trimTrailingSlash(s)
	if s:sub(-1) == "/" then
		return s:sub(1, -2)
	end
	return s
end

local function ensureDir(path)
	if path == "" or path == "/" then return end
	if fs.exists(path) then return end
	fs.makeDir(path)
end

local function writeFile(path, content)
	ensureDir(fs.getDir(path))
	local f = fs.open(path, "w")
	if not f then error("Unable to open for write: " .. path, 0) end
	f.write(content)
	f.close()
end

local function httpEnabled()
	-- settings.get may not exist in older versions; pcall for safety.
	local ok, v = pcall(function() return settings.get("http.enable") end)
	if ok and v == false then return false end
	return true
end

local function fetch(url)
	local ok, resp = pcall(function()
		-- Some CC:Tweaked versions support an options table; keep it simple.
		return http.get(url)
	end)
	if not ok or not resp then
		return nil, "HTTP GET failed: " .. url
	end
	local body = resp.readAll()
	resp.close()
	if not body or body == "" then
		return nil, "Empty response: " .. url
	end
	return body
end

local function installOne(base, remotePath, destPath, force)
	if (not force) and fs.exists(destPath) then
		print("skip  " .. destPath .. " (exists)")
		return true
	end

	local url = base .. "/" .. remotePath
	local body, err = fetch(url)
	if not body then
		printError("fail  " .. destPath)
		printError("      " .. err)
		return false
	end

	writeFile(destPath, body)
	print("ok    " .. destPath)
	return true
end

local opts = parseArgs(args)
if not opts then return end

if not httpEnabled() then
	printError("HTTP is disabled. Enable it in ComputerCraft config (http.enable=true) and try again.")
	return
end

-- If --base isn't provided, default to a placeholder that the user should replace.
if not opts.base then
	printError("Missing --base.")
	print("Example:")
	print("  install --base https://raw.githubusercontent.com/<owner>/<repo>/" .. opts.branch .. " --startup")
	return
end

local base = trimTrailingSlash(opts.base)

local manifest = {
	{ remote = "screensaver.lua", dest = "/screensaver.lua" },
	{ remote = "screensavers/example-bounce.lua", dest = "/screensavers/example-bounce.lua" },
	{ remote = "screensavers/game-of-life.lua", dest = "/screensavers/game-of-life.lua" },
	{ remote = "screensavers/roulette-wheel.lua", dest = "/screensavers/roulette-wheel.lua" },
	{ remote = "screensavers/pipes-3d.lua", dest = "/screensavers/pipes-3d.lua" },
	{ remote = "screensavers/disco-floor.lua", dest = "/screensavers/disco-floor.lua" },
}

if opts.startup then
	table.insert(manifest, { remote = "startup.lua", dest = "/startup.lua" })
end

print("Installing cc-screensaver...")
print("Base: " .. base)
print("Force: " .. tostring(opts.force) .. " | Startup: " .. tostring(opts.startup))

ensureDir("/screensavers")

local okAll = true
for _, item in ipairs(manifest) do
	local ok = installOne(base, item.remote, item.dest, opts.force)
	if not ok then okAll = false end
end

if not okAll then
	printError("Install completed with errors.")
	return
end

print("Done.")
print("Run: screensaver")
if opts.startup then
	print("(Auto-start enabled via /startup.lua)")
else
	print("Tip: re-run installer with --startup to auto-start on boot")
end
