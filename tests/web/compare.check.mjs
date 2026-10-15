// Self-check for web/js/compare.js. Run from the project root:
//   node tests/web/compare.check.mjs
import assert from "node:assert/strict";
import { startingSlots, slotGroup, slotsOf, lineToBeat, realizedStats, mapPoint, mapSet, defaultSlot }
  from "../../web/js/compare.js";

// this league: QB, 2 RB, RB/WR flex, 2 WR, TE, D/ST, K; WR/TE and FLEX unused
const slots = [
  { lineup_slot_id: 0, slot_label: "QB", slot_count: 1 },
  { lineup_slot_id: 2, slot_label: "RB", slot_count: 2 },
  { lineup_slot_id: 3, slot_label: "RB/WR", slot_count: 1 },
  { lineup_slot_id: 4, slot_label: "WR", slot_count: 2 },
  { lineup_slot_id: 5, slot_label: "WR/TE", slot_count: 0 },
  { lineup_slot_id: 6, slot_label: "TE", slot_count: 1 },
  { lineup_slot_id: 16, slot_label: "D/ST", slot_count: 1 },
  { lineup_slot_id: 17, slot_label: "K", slot_count: 1 },
  { lineup_slot_id: 20, slot_label: "BE", slot_count: 6 },
  { lineup_slot_id: 23, slot_label: "FLEX", slot_count: 0 },
];
const E = { RB: "2,3,23,20,21", WR: "3,4,5,23,20,21", TE: "5,6,23,20,21" };
let pid = 0;
const P = (position, sim_mean, optimal_slot = null, extra = {}) => ({
  player_id: String(++pid), ffa_id: String(100 + pid), position, sim_mean, p10: sim_mean - 5, p90: sim_mean + 5,
  eligible_slot_ids: E[position], optimal_slot, is_optimal_starter: optimal_slot != null, ...extra,
});

const starting = startingSlots(slots);
assert.deepEqual(starting.map((s) => s.label), ["QB", "RB", "RB/WR", "WR", "TE", "D/ST", "K"]);

const roster = [P("RB", 15, "RB"), P("RB", 12, "RB"), P("WR", 14, "WR"), P("WR", 11, "WR"),
  P("WR", 9, "RB/WR"), P("RB", 6), P("TE", 10, "TE"), P("TE", 7)];
const [rb15, , , , wr9, , te10] = roster;

// groups: RB reaches the flex, the flex reaches RB + WR, TE only TE (WR/TE unused)
assert.deepEqual([...slotGroup(2, roster, starting)].sort(), [2, 3]);
assert.deepEqual([...slotGroup(3, roster, starting)].sort(), [2, 3, 4]);
assert.deepEqual([...slotGroup(6, roster, starting)], [6]);
assert.deepEqual([...slotsOf(rb15, starting)].sort(), [2, 3]);

// a superar: the WR in the flex for the RB group (not even plotted there); TE vs TE
assert.equal(lineToBeat(roster, slotGroup(2, roster, starting), starting), wr9);
assert.equal(lineToBeat(roster, slotGroup(6, roster, starting), starting), te10);

// realized: NA weeks ignored; bias, band, booms, busts
const weeks = [
  { week: 1, sim_mean: 10, p10: 5, p90: 15, actual_points: 20 },   // boom
  { week: 2, sim_mean: 10, p10: 5, p90: 15, actual_points: 10 },   // in band
  { week: 3, sim_mean: 10, p10: 5, p90: 15, actual_points: 3 },    // bust
  { week: 4, sim_mean: 10, p10: 5, p90: 15, actual_points: null }, // did not play
];
const st = realizedStats(weeks);
assert.deepEqual({ n: st.n, inBand: st.inBand, booms: st.booms, busts: st.busts }, { n: 3, inBand: 1, booms: 1, busts: 1 });
assert.ok(Math.abs(st.bias - 1) < 1e-9 && Math.abs(st.actual - 11) < 1e-9);
assert.equal(realizedStats([]), null);

// lenses: next = mean of the future weeks, bye counted as 0
assert.deepEqual(mapPoint({ ...rb15, horizon: [12, 0, 15] }, "next"), { x: 15, y: 9 });
assert.deepEqual(mapPoint(rb15, "week"), { x: 15, lo: 10, hi: 20 });
assert.equal(mapPoint(rb15, "next"), null);
assert.deepEqual(mapPoint(rb15, "real", new Map([[rb15.ffa_id, weeks]])), { x: 10, y: 11, n: 3 });

// map set: RB slot = my RBs + the best eligible FA; a rostered player never as FA
const fa = [P("RB", 13), P("RB", 8), P("WR", 20), rb15];
const set = mapSet({ roster, freeAgents: fa, slotId: 2, lens: "week", nFa: 1 });
assert.deepEqual(set.map((d) => [d.p.sim_mean, d.kind]), [[15, "starter"], [12, "starter"], [6, "bench"], [13, "fa"]]);
assert.equal(mapSet({ roster, slotId: "ALL", lens: "week" }).length, roster.length);
assert.equal(defaultSlot(starting, roster), 3);   // the flex

console.log("compare: all checks passed");
