// Self-check for web/js/trade-sim.js. Run from the project root:
//   node tests/web/trade-sim.check.mjs
import assert from "node:assert/strict";
import { optimalLineup, normCdf, evaluateTrade, weightedScore } from "../../web/js/trade-sim.js";

// league slots of this league: QB, 2 RB, RB/WR flex, 2 WR, TE (K / D/ST omitted)
const slots = [
  { lineup_slot_id: 0, slot_label: "QB", slot_count: 1 },
  { lineup_slot_id: 2, slot_label: "RB", slot_count: 2 },
  { lineup_slot_id: 3, slot_label: "RB/WR", slot_count: 1 },
  { lineup_slot_id: 4, slot_label: "WR", slot_count: 2 },
  { lineup_slot_id: 6, slot_label: "TE", slot_count: 1 },
  { lineup_slot_id: 20, slot_label: "BE", slot_count: 6 },
];
const E = { QB: "0,20,21", RB: "2,3,23,20,21", WR: "3,4,5,23,20,21", TE: "5,6,23,20,21" };
let pid = 0;
const P = (team_id, position, sim_mean, extra = {}) => ({
  player_id: ++pid, team_id, position, sim_mean, sim_sd: 5, eligible_slot_ids: E[position],
  ros_points: sim_mean * 10, ros_games: 10, season_points: sim_mean * 4, games_played: 4, ...extra,
});

// normCdf against tabulated values
assert.ok(Math.abs(normCdf(0) - 0.5) < 1e-7);
assert.ok(Math.abs(normCdf(1.2815516) - 0.9) < 1e-6);
assert.ok(Math.abs(normCdf(-1.959964) - 0.025) < 1e-6);

// flex takes the best remaining RB/WR, never the TE; IR / OUT sit this week
const A = [P(1, "QB", 20), P(1, "RB", 15), P(1, "RB", 12), P(1, "RB", 9), P(1, "WR", 14), P(1, "WR", 11),
  P(1, "WR", 8), P(1, "TE", 10), P(1, "TE", 9.5), P(1, "WR", 30, { is_ir: true })];
const lineup = optimalLineup(A, slots, "week");
assert.equal(lineup.length, 7);
const flex = lineup.find((x) => x.slot_id === 3);
assert.equal(flex.player.sim_mean, 9);           // RB 9 beats WR 8; TE not eligible
assert.equal(lineup.reduce((s, x) => s + x.value, 0), 20 + 15 + 12 + 9 + 14 + 11 + 10);
assert.ok(!lineup.some((x) => x.player.is_ir));
assert.equal(optimalLineup(A, slots, "season").find((x) => x.slot_id === 4).player.is_ir, true); // IR counts ROS

// cross-position trade: A gives WR 11, gets RB 13 from B
const B = [P(2, "QB", 18), P(2, "RB", 16), P(2, "RB", 13), P(2, "WR", 17), P(2, "WR", 15), P(2, "WR", 6),
  P(2, "TE", 7)];
const give = A.find((p) => p.position === "WR" && p.sim_mean === 11);
const recv = B.find((p) => p.position === "RB" && p.sim_mean === 13);
const r = evaluateTrade({
  rosters: [...A, ...B], freeAgents: [P(0, "RB", 5), P(0, "WR", 7)], slots,
  matchups: [{ home_team_id: 1, away_team_id: 2, home_expected: 0, away_expected: 90, home_p10: 0, home_p90: 0, away_p10: 80, away_p90: 100 }],
  myTeamId: 1, giveId: give.player_id, partnerId: 2, receiveId: recv.player_id, weeksLeft: 10,
});
// A before: QB20 RB15,12 WR14,11 flex RB9 TE10 = 91
// A after:  QB20 RB15,13 WR14,8 flex RB12 TE10 = 92  (+1: the WR8 now starts)
assert.ok(Math.abs(r.lenses.week.me.delta - 1) < 1e-9, `me delta ${r.lenses.week.me.delta}`);
// B before: QB18 RB16,13 WR17,15 flex WR6 TE7 = 92
// B after:  one RB left, second RB seat empty: QB18 RB16 WR17,15 flex WR11 TE7 = 84 (-8)
assert.ok(Math.abs(r.lenses.week.them.delta + 8) < 1e-9, `them delta ${r.lenses.week.them.delta}`);
assert.ok(r.lenses.week.partnerIsOpponent);
assert.ok(r.lenses.week.me.winAfter > r.lenses.week.me.winBefore);
// VORP: RB 13 over the best FA RB 5
assert.equal(r.lenses.week.receive.vor, 8);
// season / perf also count the IR WR30 (ROS already discounts injuries):
// before QB20 RB15,12 WR30,14 flex WR11 TE10 = 112; after RB15,13 WR30,14 flex RB12 = 114 (+2)
assert.ok(Math.abs(r.lenses.season.me.delta - 2) < 1e-9, `season delta ${r.lenses.season.me.delta}`);
assert.ok(Math.abs(r.lenses.season.me.total - 20) < 1e-9);       // x 10 weeks left
assert.ok(Math.abs(r.lenses.perf.me.delta - 2) < 1e-9);
// same unit across lenses -> equal weights average the deltas: (1 + 2 + 2) / 3
assert.ok(Math.abs(weightedScore(r, { week: 1, season: 1, perf: 1 }) - 5 / 3) < 1e-9);
// position strength ranks: A's RB group goes up
const rb = r.lenses.week.strength.find((s) => s.position === "RB");
assert.ok(rb.me.after > rb.me.before);

console.log("trade-sim: all checks passed");
