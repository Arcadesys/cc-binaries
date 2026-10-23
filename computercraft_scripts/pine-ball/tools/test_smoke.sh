#!/bin/sh
# Live event-loop smoke (tests/smoke.lua): real timers, queued keys, and an emulated monitor
# that is detached mid-game. Needs CraftOS-PC's GUI mode for monitors, so it opens a window.
set -eu
GAME_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CRAFTOS_BIN=${CRAFTOS_BIN:-/Applications/CraftOS-PC.app/Contents/MacOS/craftos}
RESULT_DIR=${1:-$(mktemp -d "${TMPDIR:-/tmp}/pine-ball-smoke.XXXXXX")}
mkdir -p "$RESULT_DIR"
RESULT_DIR=$(CDPATH= cd -- "$RESULT_DIR" && pwd)
"$CRAFTOS_BIN" --gui --directory "$RESULT_DIR/emulator" \
  --mount-ro "/game=$GAME_DIR" --mount-rw "/results=$RESULT_DIR" \
  --exec 'shell.setDir("/game"); local lines={}; print=function(...) local p={...}; for i=1,#p do p[i]=tostring(p[i]) end; lines[#lines+1]=table.concat(p," ") end; local ok,err=pcall(function() local env=setmetatable({}, {__index=_ENV}); env.require,env.package=require("cc.require").make(env,"/game"); env.require("tests.smoke") end); lines[#lines+1]=ok and "PASS smoke" or "FAIL "..tostring(err); local h=fs.open("/results/smoke.txt","w"); h.write(table.concat(lines,"\n").."\n"); h.close(); os.shutdown()' \
  > "$RESULT_DIR/emulator-stdout.log" 2>&1
cat "$RESULT_DIR/smoke.txt"
if ! grep -q '^PASS smoke' "$RESULT_DIR/smoke.txt"; then exit 1; fi
