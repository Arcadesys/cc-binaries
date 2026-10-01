#!/bin/sh
set -eu
GAME_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CRAFTOS_BIN=${CRAFTOS_BIN:-/Applications/CraftOS-PC.app/Contents/MacOS/craftos}
RESULT_DIR=${1:-$(mktemp -d "${TMPDIR:-/tmp}/pine-face-tests.XXXXXX")}
mkdir -p "$RESULT_DIR"
RESULT_DIR=$(CDPATH= cd -- "$RESULT_DIR" && pwd)
"$CRAFTOS_BIN" --headless --directory "$RESULT_DIR/emulator" \
  --mount-ro "/game=$GAME_DIR" --mount-rw "/results=$RESULT_DIR" \
  --exec 'shell.setDir("/game"); local lines={}; print=function(...) local p={...}; for i=1,#p do p[i]=tostring(p[i]) end; lines[#lines+1]=table.concat(p," ") end; local ok,err=pcall(function() local env=setmetatable({}, {__index=_ENV}); env.require,env.package=require("cc.require").make(env,"/game"); env.require("tests.run") end); if not ok then lines[#lines+1]="FAIL "..tostring(err) end; local h=fs.open("/results/tests.txt","w"); h.write(table.concat(lines,"\n").."\n"); h.close(); os.shutdown()' \
  > "$RESULT_DIR/emulator-stdout.log" 2>&1
cat "$RESULT_DIR/tests.txt"
grep -q '^PASS Pine Face' "$RESULT_DIR/tests.txt"
