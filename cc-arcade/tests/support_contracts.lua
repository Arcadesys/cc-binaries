-- Self-tests for the deterministic support layer, also runnable inside CC.
local json = require('tests.support.json')
local platform = require('tests.support.platform')
local checks = 0
local function check(condition, message)
 checks = checks + 1
 assert(condition, message)
end

local payload = {name = 'A "quoted" card\nline\t\\end', balance = 123,
 nested = {enabled = false, values = {1, 2, 3}}, empty = {}}
local wire = json.encode(payload)
check(wire:sub(1, 1) == '{' and wire:find('"balance":123', 1, true), 'Serialization creates JSON bytes')
local decoded = json.decode(wire)
check(decoded.name == payload.name and decoded.nested.enabled == false, 'Escapes and booleans round trip')
check(decoded.nested.values[3] == 3 and next(decoded.empty) == nil, 'Arrays and objects round trip')
decoded.nested.values[1] = 99
check(payload.nested.values[1] == 1, 'Decoded tables never alias input tables')
check(json.decode('"\\u0041\\u00e9\\ud83d\\ude00"') == 'A' .. string.char(195, 169, 240, 159, 152, 128), 'Unicode escape decoding')
check(json.decode('-1.25e2') == -125, 'JSON number grammar')
check(json.encode(json.empty_array) == '[]' and json.encode({}) == '{}', 'Empty array and object differ')
check(json.decode('null', {parse_null = true}) == json.null, 'Explicit null sentinel')
for _, invalid in ipairs({'', '{partial', '{"x":1,}', '[1,]', '01', '1.', '1e', 'true false', '"\\q"', '"\\ud800"', '"\n"'}) do
 local ok = pcall(json.decode, invalid)
 check(not ok, 'Reject malformed JSON: ' .. invalid)
end
local recursive = {}; recursive.self = recursive
check(not pcall(json.encode, recursive), 'Recursive tables rejected')
check(not pcall(json.encode, 0/0), 'NaN rejected')

local a, b = platform.new(), platform.new()
local file = assert(a.fs.open('/save/sub/state.json', 'w'))
file.write(wire); file.close()
check(a.fs.isDir('/save/sub') and a.fs.exists('/save/sub/state.json'), 'Writing creates parent directories')
check(not b.fs.exists('/save/sub/state.json'), 'Computer filesystems are isolated')
file = assert(a.fs.open('/save/sub/state.json', 'r'))
local fromDisk = a.textutils.unserializeJSON(file.readAll()); file.close()
check(fromDisk.balance == 123 and fromDisk.name == payload.name, 'Persisted bytes deserialize')
check(not pcall(file.readAll), 'Closed file handles reject reads')
check(a.fs.getDir('/save/sub/state.json') == 'save/sub', 'CC-style getDir')
check(a.fs.combine('/save', './sub', '../other') == 'save/other', 'CC-style combine')
check(a.fs.list('/save/sub')[1] == 'state.json', 'Directory listing')
check(a.files['/save/sub/state.json'] == wire, 'Fault fixtures expose actual bytes')
local invalid, errorMessage = a.textutils.unserializeJSON('{partial')
check(invalid == nil and type(errorMessage) == 'string', 'Invalid JSON returns nil and an error')
local reopened = platform.new({files = a.files})
check(reopened.fs.exists('/save/sub/state.json'), 'Filesystem snapshots can seed reboot fixtures')
a.fs.delete('/save')
check(not a.fs.exists('/save/sub/state.json') and reopened.fs.exists('/save/sub/state.json'), 'Deletion remains isolated')
check(a.fs.open('/missing', 'r') == nil, 'Missing file returns nil')
print(('PASS support contracts (%d assertions)'):format(checks))
return checks
