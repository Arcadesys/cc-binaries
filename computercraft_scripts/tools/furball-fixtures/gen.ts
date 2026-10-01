// Golden fixtures from the furball-simulator TS kernels, consumed by the Lua ports. Run via update.sh.
import { writeFileSync, mkdirSync } from "node:fs";
import { createRng, weighted } from "./src/sim/rng.ts";
import { resolvePitch, cpuPitch, contactTier, sprayDirection } from "./src/sim/batting.ts";
import { applyPitchEvent, createGame } from "./src/sim/gameState.ts";
import { planCatch, DEFAULT_FIELDING } from "./src/sim/fielding.ts";
import { resolveControlledBowlingShot, bowlingPreviewTrajectory, bowlingTrajectoryX } from "./src/sports/bowling/sim/trajectory.ts";
import { newHole, strike, stepGolf, type Club } from "./src/sports/golf/golf-core.ts";
import { lieAt } from "./src/sports/golf/course.ts";

const out = process.argv[2]!;
mkdirSync(out, { recursive: true });
const r = (n: number) => Number(n.toPrecision(15));

// ---------- rng
const rng = [1, 123, 0, 4294967295, 2654435769, 77].map(seed => {
  const g = createRng(seed); return { seed, values: Array.from({ length: 8 }, () => g()) };
});
const wg = createRng(9);
const weightedCases = Array.from({ length: 30 }, () => weighted(wg, { a: 1, b: 2.5, c: 0, d: 4 }));

// ---------- baseball
const pitchCases: any[] = [];
{
  const g = createRng(2024);
  for (let i = 0; i < 400; i++) {
    const pitch = cpuPitch(g);
    const take = g() < 0.15;
    const offset = take ? null : Math.round((g() * 2 - 1) * 160);
    const aim = { x: [-1, 0, 1][Math.floor(g() * 3)]!, y: [-1, 0, 1][Math.floor(g() * 3)]! };
    const bats = g() < 0.5 ? "R" : "L";
    const seed = Math.floor(g() * 1e9);
    const event = resolvePitch(pitch, { timingOffsetMs: offset, aim, bats }, createRng(seed));
    pitchCases.push({ pitch, offset, aim, bats, seed, event, tier: offset === null ? null : contactTier(pitch.location, offset) });
  }
}
const cpuPitches = (() => { const g = createRng(31337); return Array.from({ length: 50 }, () => cpuPitch(g)); })();
// Full games: random events through the reducer, recording state after each.
const games: any[] = [];
for (const seed of [1, 2, 3, 4, 5, 6]) {
  const g = createRng(seed * 7919);
  let state = createGame({ light: ["l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9"], dark: ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9"] });
  const steps: any[] = [];
  const results = ["GROUND_OUT_LEFT", "GROUND_OUT_RIGHT", "FLY_OUT_LEFT", "FLY_OUT_CENTER", "FLY_OUT_RIGHT", "SINGLE_LEFT", "SINGLE_CENTER", "SINGLE_RIGHT", "DOUBLE_LEFT_CENTER", "DOUBLE_RIGHT_CENTER", "TRIPLE_LEFT", "TRIPLE_CENTER", "TRIPLE_RIGHT", "HOME_RUN_LEFT", "HOME_RUN_CENTER", "HOME_RUN_RIGHT", "ERROR_LEFT", "ERROR_CENTER", "ERROR_RIGHT"];
  for (let i = 0; i < 400 && state.status === "playing"; i++) {
    const k = g();
    const event: any = k < 0.25 ? { kind: "BALL" } : k < 0.4 ? { kind: "CALLED_STRIKE" } : k < 0.5 ? { kind: "SWINGING_STRIKE" } : k < 0.62 ? { kind: "FOUL" }
      : { kind: "IN_PLAY", result: results[Math.floor(g() * results.length)] };
    const t = applyPitchEvent(state, event);
    steps.push({ event, state: t.state, callouts: t.callouts, scored: t.scored, plateAppearanceOver: t.plateAppearanceOver });
    state = t.state;
  }
  games.push({ seed, steps });
}
const catches = (() => {
  const g = createRng(55);
  return Array.from({ length: 40 }, () => {
    const distance = g() * 40, roll = g();
    return { distance, roll, plan: planCatch(distance, 1800, DEFAULT_FIELDING, roll) };
  });
})();
const fieldingRng = (() => { const g = createRng((123 ^ 0x9e3779b9) >>> 0); const g2 = createRng(123 ^ 0x9e3779b9); return { unsigned: [g(), g()], signed: [g2(), g2()] }; })();

// ---------- bowling
const bowling: any[] = [];
{
  const g = createRng(4242);
  const shot = (position: number, angle: number, spin: number, power: number, seed: number, standing: number[]) => {
    const res = resolveControlledBowlingShot({ position, angle, spin, power, seed, standing });
    const last = res.pinAction.frames.at(-1)!;
    const tr = res.trajectory;
    return { input: { position, angle, spin, power, seed, standing }, kind: res.kind, knockedDown: res.knockedDown, remaining: res.remaining,
      durationMs: res.pinAction.durationMs, frameCount: res.pinAction.frames.length, eventCount: res.pinAction.events.length,
      events: res.pinAction.events.slice(0, 12).map(e => ({ timeMs: r(e.timeMs), pinId: e.pinId, source: e.source, sourcePinId: e.sourcePinId, toppled: e.toppled, impulse: r(e.impulse) })),
      gutterProgress: tr.gutterProgress, gutterSide: tr.gutterSide, maxProgress: tr.maxProgress,
      firstContactRow: tr.firstContactRow, contactPinIds: tr.contactPinIds,
      samples: [0, 0.2, 0.5, 0.8, 1].map(p => r(bowlingTrajectoryX(tr, p))),
      finalPins: last.pins.map(p => ({ pinId: p.pinId, x: r(p.x), z: r(p.z), fall: r(p.fallAmount), yaw: r(p.yaw), fx: r(p.fallDirectionX), fz: r(p.fallDirectionZ), toppled: p.toppled })) };
  };
  const full = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  bowling.push(shot(0, 0, 0, 100, 123, full));
  bowling.push(shot(-10, 2, 0, 80, 7, full));
  bowling.push(shot(30, -6, 18, 72, 9, full));
  bowling.push(shot(100, 30, 100, 100, 1, full)); // gutter
  bowling.push(shot(0, 0, 0, 10, 2, full)); // short
  bowling.push(shot(-80, 0, 60, 60, 3, full));
  for (let i = 0; i < 60; i++) {
    const standing = i % 3 === 0 ? full.filter(() => g() < 0.55) : full;
    if (standing.length === 0) standing.push(1);
    bowling.push(shot(Math.round((g() * 2 - 1) * 60), Math.round((g() * 2 - 1) * 25), Math.round((g() * 2 - 1) * 80), Math.round(15 + g() * 85), Math.floor(g() * 1e6), standing));
  }
}
const previews = [{ position: 50, angle: 40, spin: -100, power: 60 }, { position: -100, angle: -10, spin: 100, power: 100 }, { position: 0, angle: 0, spin: 0, power: 5 }]
  .map(c => { const t = bowlingPreviewTrajectory(c); return { controls: c, gutterProgress: t.gutterProgress, gutterSide: t.gutterSide, maxProgress: t.maxProgress }; });

// ---------- golf
const golf: any[] = [];
{
  const g = createRng(808);
  const clubs: Club[] = ["5i", "7i", "wedge", "putter"];
  const play = (shots: { club: Club; aim: number; power: number }[]) => {
    const s = newHole();
    const states: any[] = [];
    for (const shot of shots) {
      if (s.phase !== "ready") break;
      const ok = strike(s, shot);
      let ticks = 0; const path: number[][] = [];
      while (s.phase === "moving") { stepGolf(s); ticks++; if (ticks % 60 === 0) path.push([r(s.ball.x), r(s.ball.y), r(s.ball.z)]); }
      states.push({ shot, ok, ball: { x: r(s.ball.x), y: r(s.ball.y), z: r(s.ball.z) }, lie: s.lie, strokes: s.strokes, penalties: s.penalties, phase: s.phase, ticks: s.ticks, lastCarry: r(s.lastCarry), message: s.message, path });
    }
    return states;
  };
  golf.push(play([{ club: "5i", aim: 0, power: 94 }, { club: "putter", aim: 0, power: 30 }]));
  golf.push(play([{ club: "5i", aim: 25, power: 100 }])); // likely OB/trees
  golf.push(play([{ club: "7i", aim: -4, power: 100 }, { club: "wedge", aim: 3, power: 40 }]));
  for (let i = 0; i < 30; i++) {
    const shots = Array.from({ length: 4 }, () => ({ club: clubs[Math.floor(g() * 4)]!, aim: Math.round((g() * 2 - 1) * 300) / 10, power: Math.round(5 + g() * 95) }));
    golf.push(play(shots));
  }
}
const lies = (() => { const g = createRng(17); return Array.from({ length: 200 }, () => { const x = (g() * 2 - 1) * 45, z = -20 + g() * 230; return { x, z, lie: lieAt(x, z) }; }); })();

writeFileSync(`${out}/fixtures.json`, JSON.stringify({ rng, weightedCases, pitchCases, cpuPitches, games, catches, fieldingRng, bowling, previews, golf, lies }));
console.log("bowling kinds", bowling.map(b => b.kind + ":" + b.knockedDown.length).join(" "));
console.log("golf finals", golf.map(s => s.at(-1)?.phase + "/" + s.at(-1)?.strokes).join(" "));
console.log("fieldingRng", fieldingRng);
