-- Minimal CC API doubles used by the contract suite. Every new() owns a separate
-- in-memory filesystem; no host files, peripherals or network are accessed here.
-- Source code is loaded by the harness, outside this virtual filesystem.
local json = require('tests.support.json')
local M = {}

local function normalize(path)
 assert(type(path) == 'string', 'Filesystem path must be a string')
 local parts = {}
 for part in path:gsub('\\', '/'):gmatch('[^/]+') do
  if part == '..' then
   assert(#parts > 0, 'Cannot traverse above virtual root')
   parts[#parts] = nil
  elseif part ~= '.' then parts[#parts + 1] = part end
 end
 return '/' .. table.concat(parts, '/')
end

local function json_api()
 -- Running inside CC uses its real implementation, including its byte-string
 -- handling. The standalone fallback supports the house's ordinary JSON data.
 if type(textutils) == 'table' and type(textutils.serializeJSON) == 'function'
   and type(textutils.unserializeJSON) == 'function' then return textutils end
 local api = {json_null = json.null, empty_json_array = json.empty_array}
 function api.serializeJSON(value, options)
  assert(options == nil or options == false, 'JSON options are outside the standalone harness subset')
  return json.encode(value)
 end
 function api.unserializeJSON(source, options)
  local ok, result = pcall(json.decode, source, options)
  if not ok then return nil, result end
  return result
 end
 api.serialiseJSON = api.serializeJSON
 api.unserialiseJSON = api.unserializeJSON
 return api
end

function M.new(options)
 options = options or {}
 local files, directories = {}, {['/'] = true}
 local fs = {}
 function fs.combine(...)
  return normalize(table.concat({...}, '/')):sub(2)
 end
 function fs.getDir(path)
  local result = normalize(path):match('^(.*)/[^/]*$') or ''
  return result == '' and '' or result:sub(2)
 end
 function fs.getName(path) return normalize(path):match('([^/]+)$') or '' end
 function fs.exists(path)
  path = normalize(path)
  return files[path] ~= nil or directories[path] == true
 end
 function fs.isDir(path) return directories[normalize(path)] == true end
 function fs.makeDir(path)
  path = normalize(path)
  local current = ''
  for part in path:gmatch('[^/]+') do
   current = current .. '/' .. part
   assert(files[current] == nil, 'Cannot create directory over a file: ' .. current)
   directories[current] = true
  end
 end
 function fs.list(path)
  path = normalize(path)
  assert(directories[path], 'Not a directory: ' .. path)
  local prefix = path == '/' and '/' or path .. '/'
  local names = {}
  for _, entries in ipairs({files, directories}) do
   for name in pairs(entries) do
    if name:sub(1, #prefix) == prefix then
     local child = name:sub(#prefix + 1):match('^([^/]+)$')
     if child then names[child] = true end
    end
   end
  end
  local result = {}; for name in pairs(names) do result[#result + 1] = name end
  table.sort(result)
  return result
 end
 function fs.getSize(path)
  path = normalize(path)
  assert(fs.exists(path), 'No such file: ' .. path)
  return files[path] and #files[path] or 0
 end
 function fs.delete(path)
  path = normalize(path)
  assert(path ~= '/', 'Cannot delete virtual root')
  for _, entries in ipairs({files, directories}) do
   for name in pairs(entries) do
    if name == path or name:sub(1, #path + 1) == path .. '/' then entries[name] = nil end
   end
  end
 end
 function fs.open(path, mode)
  path = normalize(path)
  assert(mode == 'r' or mode == 'w' or mode == 'a', 'Unsupported fake fs.open mode: ' .. tostring(mode))
  if directories[path] then return nil, 'Cannot open directory: ' .. path end
  if mode == 'r' and files[path] == nil then return nil, 'No such file: ' .. path end
  if mode ~= 'r' then
   -- CC creates parents when a file is opened for writing.
   fs.makeDir(fs.getDir(path))
   if mode == 'w' or files[path] == nil then files[path] = '' end
  end
  local closed, cursor = false, 1
  local function check() assert(not closed, 'Attempt to use a closed file') end
  local handle = {}
  function handle.close() check(); closed = true end
  if mode == 'r' then
   function handle.readAll()
    check(); local result = files[path]:sub(cursor); cursor = #files[path] + 1; return result
   end
   function handle.readLine(withTrailing)
    check()
    local content = files[path]
    if cursor > #content then return nil end
    local ending = content:find('\n', cursor, true)
    local result = content:sub(cursor, ending and (withTrailing and ending or ending - 1) or #content)
    cursor = ending and ending + 1 or #content + 1
    if not withTrailing then result = result:gsub('\r$', '') end
    return result
   end
   function handle.read(count)
    check(); count = count or 1
    assert(type(count) == 'number' and count >= 0 and count % 1 == 0, 'Invalid read count')
    if cursor > #files[path] then return nil end
    local result = files[path]:sub(cursor, cursor + count - 1); cursor = cursor + #result
    return result
   end
  else
   function handle.write(value) check(); files[path] = files[path] .. tostring(value) end
   function handle.writeLine(value) handle.write(tostring(value) .. '\n') end
   function handle.flush() check() end
  end
  return handle
 end
 for path, content in pairs(options.files or {}) do
  assert(type(content) == 'string', 'Seeded virtual file contents must be strings')
  local file = assert(fs.open(path, 'w')); file.write(content); file.close()
 end
 -- files is intentionally exposed for deterministic corruption/fault fixtures.
 -- Its keys are canonical absolute paths; its values are serialized byte strings.
 return {fs = fs, textutils = json_api(), files = files}
end

return M
