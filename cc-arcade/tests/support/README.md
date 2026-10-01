# Standalone contract-test support

These are test doubles, not a Minecraft/CC emulator. They do not open real
peripherals, send network packets, or write a computer's state to the host disk.

Run from any working directory:

```sh
python3 /path/to/repo/cc-arcade/tools/test_contracts.py
```

The runner uses an installed Lua 5.3/5.4 executable, or `luatex --luaonly` when
standalone Lua is absent. LuaTeX runs a real Lua VM; it does not render a document.
Python needs only its standard library. Nothing is downloaded automatically.
On Ubuntu, `sudo apt-get install lua5.4` provides the normal runtime. Set
`PINE_LUA=lua5.4` or pass `--lua lua5.4` to choose it explicitly. Scripts run with
`cc-arcade` as their working directory, and a failing assertion or timeout exits
nonzero. The default timeout is 60 seconds (`--timeout SECONDS`).

The support self-tests are independently runnable:

```sh
python3 cc-arcade/tools/test_contracts.py --suite tests/support_contracts.lua
```

Inside CC: Tweaked, change to the installed arcade root and run
`tests/support_contracts.lua`. The support layer uses native `textutils` JSON
functions when available while keeping each fake computer's filesystem isolated.

## API

```lua
local platform = require('tests.support.platform')
local computer = platform.new()
local reboot = platform.new({files = computer.files})
-- Supply computer.fs and computer.textutils to the module's isolated environment.
```

Each call returns independent `fs`, `textutils`, and `files` fields:

- `fs` implements `combine`, `getDir`, `getName`, `exists`, `isDir`, `makeDir`,
  `list`, `getSize`, `delete`, and text-mode `open` (`r`, `w`, `a`). Handles expose
  the appropriate `read`, `readLine`, `readAll`, `write`, `writeLine`, `flush`, and
  `close` methods. Missing-file reads return `nil`; closed handles fail.
- `files` maps canonical absolute paths to actual byte strings. It can seed a
  fresh computer or deliberately corrupt a saved generation for a fault test.
- `textutils` uses native CC JSON where available, otherwise the pure-Lua JSON
  implementation. Both US and UK spelling aliases are available.

The fallback JSON implementation serializes and parses real JSON, so persistence
crosses a byte boundary and reloads fresh tables. It handles string-keyed objects,
dense arrays, finite numbers, booleans, escaped strings, and JSON null/empty-array
sentinels. Empty Lua tables serialize as `{}`. Invalid JSON returns `nil` plus an
error through `textutils.unserializeJSON`. The fallback accepts UTF-8 bytes and
decodes Unicode escapes; native CC's legacy 8-bit string conversion, NBT syntax,
mixed-key/sparse arrays, serialization options, and other `textutils` operations
are outside this test double's scope. The exercised ledger data uses the common
JSON subset. Filesystem capacity, permissions, disk latency, crash-time buffering,
and device attachment are also outside the support model.

CC API reference: [textutils](https://tweaked.cc/module/textutils.html) and
[fs](https://tweaked.cc/module/fs.html).
