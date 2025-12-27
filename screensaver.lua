-- ComputerCraft:Tweaked screensaver shuffler
-- Scans a directory for .lua files and runs them one-by-one for a fixed interval.

local args = { ... }

local function parseArgs(argv)
	local opts = {
		dir = "/screensavers",
		interval = 20,
		list = false,
	}

	local i = 1
	while i <= #argv do
		local a = argv[i]
		if a == "--dir" then
			i = i + 1
			opts.dir = argv[i]
		elseif a == "--interval" then
			i = i + 1
			opts.interval = tonumber(argv[i])
		elseif a == "--list" then
			opts.list = true
		elseif a == "--help" or a == "-h" then
			print("Usage:")
			print("  screensaver [--dir /screensavers] [--interval 20] [--list]")
			return nil
		else
			print("Unknown arg: " .. tostring(a))
			print("Run with --help for usage")
			return nil
		end
		i = i + 1
	end

	if type(opts.interval) ~= "number" or opts.interval < 1 then
		print("--interval must be a number >= 1")
		return nil
	end

	if type(opts.dir) ~= "string" or opts.dir == "" then
		print("--dir must be a non-empty string")
		return nil
	end

	return opts
end

local function seedRng()
	-- os.epoch exists in CC:Tweaked; fall back if not.
	local ok, v = pcall(function() return os.epoch("utc") end)
	if ok and type(v) == "number" then
		math.randomseed(v)
	else
		math.randomseed(math.floor(os.clock() * 1000000))
	end
	math.random(); math.random(); math.random()
end

local function listScreensavers(dir)
	if not fs.exists(dir) then
		return nil, "Directory does not exist: " .. dir
	end
	if not fs.isDir(dir) then
		return nil, "Not a directory: " .. dir
	end

	local out = {}
	for _, name in ipairs(fs.list(dir)) do
		if type(name) == "string" and name:sub(-4) == ".lua" then
			local full = fs.combine(dir, name)
			if fs.isDir(full) == false then
				table.insert(out, full)
			end
		end
	end

	table.sort(out)
	return out
end

local function shuffleInPlace(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local function sleepRaw(seconds)
	local timerId = os.startTimer(seconds)
	while true do
		local event, p1 = os.pullEventRaw()
		if event == "terminate" then
			error("Terminated", 0)
		end
		if event == "timer" and p1 == timerId then
			return
		end
	end
end

local function runForSeconds(path, seconds)
	local function runner()
		-- Run program in a fresh environment that inherits globals.
		local env = setmetatable({}, { __index = _G })
		local ok, err = pcall(function()
			os.run(env, path)
		end)
		if not ok then
			-- "Terminated" can happen if the user presses Ctrl+T.
			if tostring(err) == "Terminated" then
				error("Terminated", 0)
			else
				printError("Error in " .. path .. ": " .. tostring(err))
			end
		end
	end

	local function timer()
		sleepRaw(seconds)
	end

	parallel.waitForAny(runner, timer)
end

local opts = parseArgs(args)
if not opts then
	return
end

seedRng()

local screensavers, err = listScreensavers(opts.dir)
if not screensavers then
	printError(err)
	return
end

if #screensavers == 0 then
	printError("No .lua screensavers found in: " .. opts.dir)
	return
end

if opts.list then
	for _, p in ipairs(screensavers) do
		print(p)
	end
	return
end

print("Found " .. tostring(#screensavers) .. " screensavers in " .. opts.dir)
print("Shuffling; interval " .. tostring(opts.interval) .. "s")

while true do
	local batch = {}
	for i = 1, #screensavers do batch[i] = screensavers[i] end
	shuffleInPlace(batch)

	for _, path in ipairs(batch) do
		term.setCursorPos(1, 1)
		term.clear()
		print("Running: " .. path)
		runForSeconds(path, opts.interval)
	end
end
