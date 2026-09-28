-- MS-DOS Executive: program launcher and file manager.
local ui = arcadeos.lib("ui")
local dialog = arcadeos.lib("dialog")

local view = arcadeos.getSetting("executive.view", "programs")
local dir = ""
local list = ui.list({})
local R = ui.roles()

local function setMenus()
    arcadeos.setMenus({
        { label = "File", items = {
            { id = "run", label = "Run..." },
            { id = "open", label = "Open" },
            { id = "rename", label = "Rename...", disabled = view ~= "files" },
            { id = "delete", label = "Delete", disabled = view ~= "files" },
            { id = "mkdir", label = "Make Directory...", disabled = view ~= "files" },
            "-",
            { id = "about", label = "About ArcadeOS..." },
            { id = "exit", label = "Exit ArcadeOS..." },
        } },
        { label = "View", items = {
            { id = "programs", label = "Programs", checked = view == "programs" },
            { id = "files", label = "Files", checked = view == "files" },
            "-",
            { id = "refresh", label = "Refresh" },
        } },
    })
end

local function sizeText(n)
    if n >= 10240 then return math.floor(n / 1024) .. "K" end
    return tostring(n)
end

local function programItems()
    local items, group = {}, nil
    for _, m in ipairs(arcadeos.apps()) do
        if not m.hidden then
            if m.group ~= group then
                group = m.group
                items[#items + 1] = { label = group, header = true, fg = R.titleActive }
            end
            items[#items + 1] = { label = "  " .. m.name, right = m.icon, app = m }
        end
    end
    return items
end

local function fileItems()
    local items = {}
    if dir ~= "" then items[#items + 1] = { label = "..", path = fs.getDir(dir), dir = true } end
    local ok, names = pcall(fs.list, "/" .. dir)
    if not ok then names = {} end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local files = {}
    for _, n in ipairs(names) do
        local p = fs.combine(dir, n)
        if fs.isDir(p) then
            items[#items + 1] = { label = n, right = "<DIR>", path = p, dir = true, fg = R.titleActive }
        else
            files[#files + 1] = { label = n, right = sizeText(fs.getSize(p)), path = p }
        end
    end
    for _, f in ipairs(files) do items[#items + 1] = f end
    return items
end

local function refresh(keep)
    list:setItems(view == "programs" and programItems() or fileItems(), keep)
end

local function draw()
    local w, h = term.getSize()
    term.setCursorBlink(false)
    local header = view == "programs" and " Programs" or (" /" .. dir)
    ui.text(1, 1, ui.pad(header, w), R.selectText, R.scrollThumb)
    list:place(1, 2, w, h - 1)
    list:draw()
end

local function setView(v)
    view = v
    arcadeos.setSetting("executive.view", v)
    setMenus()
    refresh()
end

local function cd(path)
    dir = path == ".." and "" or path
    refresh()
end

local function activate(item)
    if not item then return end
    if item.app then
        arcadeos.launch(item.app.id)
    elseif item.dir then
        cd(item.path)
    elseif item.path then
        arcadeos.open("/" .. item.path)
    end
end

local function runCommand()
    local line = dialog.prompt("Run", "Command line:", "")
    if not line or line:match("^%s*$") then return end
    local words = {}
    for w in line:gmatch("%S+") do words[#words + 1] = w end
    local path = shell.resolveProgram(words[1])
    if not path then
        dialog.alert("Run", "Cannot find program: " .. words[1])
        return
    end
    arcadeos.run("/" .. path, table.unpack(words, 2))
end

local function selectedFile()
    local it = list:selected()
    if view == "files" and it and it.path and it.label ~= ".." then return it end
end

local function onMenu(id)
    if id == "programs" or id == "files" then setView(id)
    elseif id == "refresh" then refresh(true)
    elseif id == "run" then runCommand()
    elseif id == "open" then activate(list:selected())
    elseif id == "about" then
        dialog.alert("About ArcadeOS", ("ArcadeOS Version %s\nA Windows 1.0-style shell for ComputerCraft.\n\n%d bytes free")
            :format(arcadeos.getVersion(), fs.getFreeSpace("/")))
    elseif id == "exit" then arcadeos.exit()
    elseif id == "mkdir" then
        local name = dialog.prompt("Make Directory", "Directory name:", "")
        if name and name ~= "" then
            local ok, err = pcall(fs.makeDir, fs.combine(dir, name))
            if not ok then dialog.alert("Make Directory", err) end
            refresh(true)
        end
    elseif id == "rename" then
        local it = selectedFile()
        if not it then return end
        local name = dialog.prompt("Rename", "Rename " .. fs.getName(it.path) .. " to:", fs.getName(it.path))
        if name and name ~= "" and name ~= fs.getName(it.path) then
            local ok, err = pcall(fs.move, it.path, fs.combine(fs.getDir(it.path), name))
            if not ok then dialog.alert("Rename", err) end
            refresh(true)
        end
    elseif id == "delete" then
        local it = selectedFile()
        if not it then return end
        if dialog.confirm("Delete", "Delete " .. fs.getName(it.path) .. "?") then
            local ok, err = pcall(fs.delete, it.path)
            if not ok then dialog.alert("Delete", err) end
            refresh(true)
        end
    end
end

setMenus()
refresh()
while true do
    draw()
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "arcadeos_menu" then
        onMenu(ev[2])
    elseif name == "key" and ev[2] == keys.backspace and view == "files" and dir ~= "" then
        cd(fs.getDir(dir))
    elseif name == "key" and ev[2] == keys.delete and view == "files" then
        onMenu("delete")
    elseif name == "key" or name == "mouse_click" or name == "mouse_scroll" or name == "mouse_drag" then
        local what, item = list:handle(name, ev[2], ev[3], ev[4])
        if what == "activate" then activate(item) end
    end
end
