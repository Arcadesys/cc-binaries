#!/bin/sh
# Regenerate the furball parity fixtures used by pine-ball, pine-lanes and pine-links.
#   tools/furball-fixtures/update.sh [FURBALL_REPO] [GIT_REF]
# Exports the pure kernels from furball-simulator at GIT_REF (default origin/main), runs
# them under Node (>= 23, native TypeScript), and writes each game's tests/fixtures/*.json.
# Then run each game's tools/test_craftos.sh: any failing parity test is a tuning change
# that the Lua port has not picked up yet.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GAMES=$(CDPATH= cd -- "$HERE/../.." && pwd)
FURBALL=${1:-$GAMES/../../furball-simulator}
REF=${2:-origin/main}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/furball-fixtures.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
git -C "$FURBALL" archive "$REF" src/sim src/sports/bowling/sim src/sports/golf/course.ts src/sports/golf/golf-core.ts | tar -x -C "$WORK"
find "$WORK/src" -name '*.test.ts' -delete
# Node resolves ESM imports literally: add the .ts extension furball's bundler infers.
find "$WORK/src" -name '*.ts' -exec perl -pi -e 's/from\s+(["\x27])(\.[^"\x27]+?)(?<!\.ts)\1/from $1$2.ts$1/g' {} \;
cp "$HERE/gen.ts" "$WORK/gen.ts"
(cd "$WORK" && node gen.ts out >/dev/null)
node -e '
const fs=require("fs"); const [src,games]=process.argv.slice(1);
const f=JSON.parse(fs.readFileSync(src+"/out/fixtures.json"));
const w=(p,o)=>fs.writeFileSync(games+"/"+p,JSON.stringify(o));
w("pine-lanes/tests/fixtures/furball_bowling.json",{rng:f.rng,bowling:f.bowling,previews:f.previews});
w("pine-links/tests/fixtures/furball_golf.json",{golf:f.golf,lies:f.lies});
w("pine-ball/tests/fixtures/furball_baseball.json",{rng:f.rng,weightedCases:f.weightedCases,pitchCases:f.pitchCases,cpuPitches:f.cpuPitches,
  games:f.games.map(g=>({seed:g.seed,steps:g.steps.map(s=>({event:s.event,callouts:s.callouts,scored:s.scored,pae:s.plateAppearanceOver,
    state:{inning:s.state.inning,half:s.state.half,outs:s.state.outs,balls:s.state.balls,strikes:s.state.strikes,score:s.state.score,bases:s.state.bases,batterIndex:s.state.batterIndex,status:s.state.status}}))})),
  catches:f.catches,fieldingRng:f.fieldingRng});
' "$WORK" "$GAMES"
echo "Fixtures updated from $FURBALL @ $(git -C "$FURBALL" rev-parse --short "$REF")"
