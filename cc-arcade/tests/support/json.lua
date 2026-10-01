-- Actual JSON bytes for the standalone harness, never a table/token registry.
-- Deliberately covers the JSON subset used by the house: string-keyed objects,
-- dense arrays, finite numbers, booleans, strings and null. Not an NBT parser or
-- a full textutils replacement. Native CC textutils is preferred by platform.lua.
local M = {null = {}, empty_array = {}}

local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
 ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
local function quote(value)
 return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
  return escapes[character] or ('\\u%04x'):format(character:byte())
 end) .. '"'
end

function M.encode(value)
 local active = {}
 local function encode(item)
  if item == M.null or item == nil then return 'null' end
  if item == M.empty_array then return '[]' end
  local kind = type(item)
  if kind == 'string' then return quote(item) end
  if kind == 'boolean' then return tostring(item) end
  if kind == 'number' then
   assert(item == item and item ~= math.huge and item ~= -math.huge, 'Non-finite JSON number')
   return tostring(item)
  end
  assert(kind == 'table', 'Unsupported JSON value: ' .. kind)
  assert(not active[item], 'Recursive JSON table')
  active[item] = true
  local count, maximum, array, keys = 0, 0, true, {}
  for key in pairs(item) do
   count = count + 1
   if type(key) == 'number' and key >= 1 and key % 1 == 0 then
    maximum = math.max(maximum, key)
   else
    array = false
   end
   keys[#keys + 1] = key
  end
  local parts = {}
  if array and count > 0 then
   assert(maximum == count, 'Sparse JSON array is outside the harness subset')
   for index = 1, maximum do parts[index] = encode(item[index]) end
   active[item] = nil
   return '[' .. table.concat(parts, ',') .. ']'
  end
  for _, key in ipairs(keys) do assert(type(key) == 'string', 'JSON object keys must be strings') end
  table.sort(keys)
  for _, key in ipairs(keys) do parts[#parts + 1] = quote(key) .. ':' .. encode(item[key]) end
  active[item] = nil
  return '{' .. table.concat(parts, ',') .. '}'
 end
 return encode(value)
end

local function unicode(code)
 if code < 0x80 then return string.char(code) end
 if code < 0x800 then return string.char(0xc0 + math.floor(code / 64), 0x80 + code % 64) end
 if code < 0x10000 then
  return string.char(0xe0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
 end
 return string.char(0xf0 + math.floor(code / 262144), 0x80 + math.floor(code / 4096) % 64,
  0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

function M.decode(source, options)
 assert(type(source) == 'string', 'JSON source must be a string')
 options = options or {}
 local position, length = 1, #source
 local function fail(message) error(message .. ' at JSON byte ' .. position, 0) end
 local function skip()
  while source:sub(position, position):match('[ \t\r\n]') do position = position + 1 end
 end
 local function hex()
  local digits = source:sub(position, position + 3)
  if #digits ~= 4 or not digits:match('^%x%x%x%x$') then fail('Invalid Unicode escape') end
  position = position + 4
  return tonumber(digits, 16)
 end
 local reverse = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
 local function string_value()
  position = position + 1
  local parts = {}
  while position <= length do
   local character = source:sub(position, position)
   position = position + 1
   if character == '"' then return table.concat(parts) end
   if character == '\\' then
    local escape = source:sub(position, position)
    position = position + 1
    if escape == 'u' then
     local code = hex()
     if code >= 0xd800 and code <= 0xdbff then
      if source:sub(position, position + 1) ~= '\\u' then fail('Missing low surrogate') end
      position = position + 2
      local low = hex()
      if low < 0xdc00 or low > 0xdfff then fail('Invalid low surrogate') end
      code = 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00
     elseif code >= 0xdc00 and code <= 0xdfff then fail('Unexpected low surrogate') end
     parts[#parts + 1] = unicode(code)
    else
     if not reverse[escape] then fail('Invalid string escape') end
     parts[#parts + 1] = reverse[escape]
    end
   else
    if character:byte() < 32 then fail('Unescaped control character') end
    parts[#parts + 1] = character
   end
  end
  fail('Unterminated string')
 end
 local value
 local function number_value()
  local start = position
  if source:sub(position, position) == '-' then position = position + 1 end
  if source:sub(position, position) == '0' then
   position = position + 1
  else
   if not source:sub(position, position):match('[1-9]') then fail('Invalid number') end
   repeat position = position + 1 until not source:sub(position, position):match('%d')
  end
  if source:sub(position, position) == '.' then
   position = position + 1
   if not source:sub(position, position):match('%d') then fail('Missing fraction') end
   repeat position = position + 1 until not source:sub(position, position):match('%d')
  end
  if source:sub(position, position):match('[eE]') then
   position = position + 1
   if source:sub(position, position):match('[+-]') then position = position + 1 end
   if not source:sub(position, position):match('%d') then fail('Missing exponent') end
   repeat position = position + 1 until not source:sub(position, position):match('%d')
  end
  local result = tonumber(source:sub(start, position - 1))
  if not result or result == math.huge or result == -math.huge then fail('Invalid finite number') end
  return result
 end
 value = function()
  skip()
  local character = source:sub(position, position)
  if character == '"' then return string_value() end
  if character == '{' or character == '[' then
   local object, result, index = character == '{', {}, 1
   local ending = object and '}' or ']'
   position = position + 1; skip()
   if source:sub(position, position) == ending then
    position = position + 1
    if not object and options.parse_empty_array ~= false then return M.empty_array end
    return result
   end
   while true do
    local key = index
    if object then
     skip()
     if source:sub(position, position) ~= '"' then fail('Expected object key') end
     key = string_value(); skip()
     if source:sub(position, position) ~= ':' then fail('Expected colon') end
     position = position + 1
    end
    result[key] = value(); index = index + 1; skip()
    local separator = source:sub(position, position)
    position = position + 1
    if separator == ending then return result end
    if separator ~= ',' then fail('Expected comma or closing bracket') end
   end
  end
  for _, literal in ipairs({'true', 'false', 'null'}) do
   if source:sub(position, position + #literal - 1) == literal then
    position = position + #literal
    if literal == 'null' then return options.parse_null and M.null or nil end
    return literal == 'true'
   end
  end
  if character == '-' or character:match('%d') then return number_value() end
  fail('Expected JSON value')
 end
 local result = value(); skip()
 if position <= length then fail('Unexpected trailing content') end
 return result
end

return M
