-- Ensure package path includes root for sub-processes
if not package.path:find("/?.lua") then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local strategies_dir = "turtleos/strategies"

-- Helper: Get list of roles (directories)
local function get_roles()
    local roles = {}
    local files = fs.list(strategies_dir)
    for _, file in ipairs(files) do
        if fs.isDir(fs.combine(strategies_dir, file)) then
            table.insert(roles, file)
        end
    end
    table.sort(roles)
    return roles
end

-- Helper: Get list of strategies for a role
local function get_strategies(role)
    local strats = {}
    local path = fs.combine(strategies_dir, role)
    if fs.exists(path) and fs.isDir(path) then
        local files = fs.list(path)
        for _, file in ipairs(files) do
            if file:sub(-4) == ".lua" then
                table.insert(strats, file:sub(1, -5)) -- Remove .lua
            end
        end
    end
    table.sort(strats)
    return strats
end

local function draw_menu(title, options, selected)
    term.clear()
    term.setCursorPos(1, 1)
    textutils.slowPrint(title, 50) -- Nice little effect, very fast
    print(string.rep("-", #title))
    
    local w, h = term.getSize()
    local start_y = 3
    local max_items = h - start_y
    
    -- Pagination start index
    local start_idx = 1
    if selected > max_items then
        start_idx = selected - max_items + 1
    end

    for i = 0, max_items - 1 do
        local idx = start_idx + i
        if idx > #options then break end
        
        term.setCursorPos(1, start_y + i)
        local prefix = (idx == selected) and "> " or "  "
        print(prefix .. options[idx].label)
    end
end

local function run_menu()
    local state = "main" -- main, role
    local current_role = nil
    
    local main_selected = 1
    local role_selected = 1
    
    while true do
        local options = {}
        local title = ""
        local selected_ptr = 1
        
        if state == "main" then
            title = "Start Menu (Select Role)"
            local roles = get_roles()
            for _, r in ipairs(roles) do
                table.insert(options, {label = r:gsub("^%l", string.upper), value = r, type = "role"})
            end
            table.insert(options, {label = "Reboot", type = "cmd", action = os.reboot})
            table.insert(options, {label = "Shutdown", type = "cmd", action = os.shutdown})
            
            selected_ptr = main_selected
            
        elseif state == "role" then
            title = "Role: " .. current_role:gsub("^%l", string.upper)
            local strats = get_strategies(current_role)
            for _, s in ipairs(strats) do
                table.insert(options, {label = s, value = s, type = "strat"})
            end
            table.insert(options, {label = "< Back", type = "back"})
            
            selected_ptr = role_selected
        end
        
        draw_menu(title, options, selected_ptr)
        
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            selected_ptr = selected_ptr - 1
            if selected_ptr < 1 then selected_ptr = #options end
        elseif key == keys.down then
            selected_ptr = selected_ptr + 1
            if selected_ptr > #options then selected_ptr = 1 end
        elseif key == keys.enter then
            local action = options[selected_ptr]
            
            if state == "main" then
                main_selected = selected_ptr
                if action.type == "role" then
                    current_role = action.value
                    role_selected = 1
                    state = "role"
                elseif action.type == "cmd" then
                    term.clear()
                    term.setCursorPos(1,1)
                    print("Executing...")
                    action.action()
                end
                
            elseif state == "role" then
                role_selected = selected_ptr
                if action.type == "back" then
                    state = "main"
                elseif action.type == "strat" then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Starting " .. current_role .. " role with strategy: " .. action.value)
                    
                    local role_mod_name = "turtleos.roles." .. current_role
                    package.loaded[role_mod_name] = nil -- Reload role
                    
                    local success, role = pcall(require, role_mod_name)
                    if success and type(role) == "table" and role.run then
                        -- Construct a minimal schema for the role
                        local run_schema = {
                            role = current_role,
                            strategy = action.value
                        }
                        
                        -- Run the role (this will likely loop forever)
                        local ok, err = pcall(role.run, run_schema)
                        if not ok then
                            print("\nRole Execution Error: " .. tostring(err))
                        end
                    else
                        print("\nError: Failed to load role module '" .. current_role .. "' or missing 'run'.")
                        if not success then print(tostring(role)) end
                        
                        -- Fallback: try running strategy directly if role fails? 
                        -- No, better to be explicit.
                    end
                    
                    print("\nProcess ended. Press any key to return.")
                    os.pullEvent("key")
                end
            end
        end
        
        -- Update the persisted selection pointers
        if state == "main" then main_selected = selected_ptr
        elseif state == "role" then role_selected = selected_ptr end
    end
end

run_menu()
