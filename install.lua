-- cc-binaries installer: choose an existing project installer.
local DEFAULT_BASE = "https://raw.githubusercontent.com/Arcadesys/cc-binaries/main"
local args = {...}
local base, choice, forwarded = DEFAULT_BASE, nil, {}
local i = 1
while i <= #args do
    local arg = args[i]
    if arg == "--base" then
        i = i + 1
        if not args[i] or args[i]:sub(1, 2) == "--" then error("--base needs a URL", 0) end
        base = args[i]
    elseif not choice then
        choice = arg:lower()
    else
        forwarded[#forwarded + 1] = arg
    end
    i = i + 1
end
base = base:gsub("/+$", "")

local projects = {
    { id = "arcadeos", label = "ArcadeOS (Advanced Computer)", path = "arcadeos/install.lua" },
    { id = "arcade", label = "Pine games and arcade", path = "cc-arcade/get.lua" },
    { id = "turtleos", label = "TurtleOS (turtle jobs)", path = "cc-turtleos/install.lua" },
    { id = "factory", label = "cc-factory (turtle automation)", path = "cc-factory/dist/factory.lua", directory = "/cc-factory" },
    { id = "screensaver", label = "Screensaver", path = "cc-screensaver/install.lua", subbase = "/cc-screensaver" },
}

local function showMenu()
    print("cc-binaries installer")
    for n, project in ipairs(projects) do print(n .. ". " .. project.label) end
    print("Enter a number, or Q to quit:")
end
if not choice then
    while true do
        showMenu()
        local answer = read()
        if not answer or answer:lower() == "q" then print("Cancelled."); return end
        local number = tonumber(answer)
        if number and projects[number] then choice = projects[number].id; break end
        print("Please enter a listed number or Q.")
    end
end
if choice == "--help" or choice == "help" or choice == "list" then
    showMenu()
    print("Or: install <arcadeos|arcade|turtleos|factory|screensaver> [options]")
    print("Use --base URL for a fork or branch.")
    return
end
local selected
for _, project in ipairs(projects) do
    if project.id == choice then selected = project; break end
end
if not selected then error("Unknown project: " .. choice .. ". Run install list.", 0) end
if not http then error("HTTP is disabled. Enable it in the server's ComputerCraft settings.", 0) end
local command = {"run", base .. "/" .. selected.path}
if selected.directory and #forwarded > 0 then error("cc-factory does not accept installer options.", 0) end
for _, arg in ipairs(forwarded) do command[#command + 1] = arg end
if not selected.directory then
    command[#command + 1] = "--base"
    command[#command + 1] = base .. (selected.subbase or "")
end
if selected.directory then
    if fs.exists(selected.directory) then
        if not fs.isDir(selected.directory) then error(selected.directory .. " is not a directory.", 0) end
        if #fs.list(selected.directory) > 0 then
            print(selected.directory .. " already contains files.")
            print("The installer will overwrite its existing modules. Continue? [y/N]")
            local answer = read()
            if not answer or answer:lower() ~= "y" then print("Cancelled."); return end
        end
    else
        fs.makeDir(selected.directory)
    end
end
print("Opening " .. selected.label .. " installer...")
local oldDir = shell.dir()
if selected.directory then shell.setDir(selected.directory) end
local ok, result = pcall(shell.run, "wget", table.unpack(command))
if selected.directory then shell.setDir(oldDir) end
if not ok or not result then
    error("Could not run the selected installer. Check HTTP access and the URL.", 0)
end
if selected.directory then print("Run: cd /cc-factory then turtle_os") end
