// Comparison map - pure logic, no DOM (also imported by tests/web/compare.check.mjs).
//
// docs/comparison_map.md: compare players BY SLOT against the real
// alternatives - my starters, my bench, the best free agents - in three lenses:
//
//   week  this week's simulated mean with its P10-P90 band
//   next  this week (x) against the mean of the next weeks (y, ESPN weekly
//         projection, bye = 0) - p.horizon from trade-sim.withHorizon()
//   real  projected x actual points per game over the season's closed weeks
//         (history/player_weeks rows, grouped by ffa_id)
//
// "a superar" is the weakest starter of my optimal lineup (rosters mart
// optimal_slot) the player could replace: an RB / WR has to beat the flex, a TE
// only the TE.

import { startingSeats, slotSet, lensValue } from "./trade-sim.js";

export const MAP_LENSES = { week: "Semana", next: "Próx. 4", real: "Realizado" };

// the league's starting slots, one entry per slot: [{id, label}]
export function startingSlots(slots) {
  const out = new Map();
  for (const s of startingSeats(slots)) out.set(s.slot_id, s.slot);
  return [...out].map(([id, label]) => ({ id, label })).sort((a, b) => a.id - b.id);
}

// starting slot ids a player is eligible for
export function slotsOf(p, starting) {
  const e = slotSet(p);
  return new Set(starting.map((s) => s.id).filter((id) => e.has(id)));
}

export const sharesSlot = (p, group) => [...slotSet(p)].some((id) => group.has(id));

// starting slots reachable by the players eligible for slotId: RB -> RB + the
// RB/WR flex; RB/WR -> RB, RB/WR, WR; TE -> TE
export function slotGroup(slotId, players, starting) {
  const out = new Set([slotId]);
  for (const p of players) if (slotSet(p).has(slotId)) for (const id of slotsOf(p, starting)) out.add(id);
  return out;
}

// weakest of my optimal starters seated in the group's slots, or null
// ponytail: fixed on this week's optimal lineup; per lens / future week if it
// ever misleads
export function lineToBeat(roster, group, starting) {
  const labels = new Set(starting.filter((s) => group.has(s.id)).map((s) => s.label));
  return roster.filter((p) => p.is_optimal_starter && labels.has(p.optimal_slot))
    .reduce((a, p) => (a == null || (p.sim_mean ?? 0) < (a.sim_mean ?? 0) ? p : a), null);
}

// a player's closed weeks with a stat row: per-game means, bias and calibration
// against the P10-P90 band projected before each game. null when none.
export function realizedStats(rows) {
  const g = (rows ?? []).filter((r) => r.actual_points != null && r.sim_mean != null);
  if (!g.length) return null;
  const mean = (f) => g.reduce((s, r) => s + f(r), 0) / g.length;
  return {
    n: g.length,
    proj: mean((r) => r.sim_mean),
    actual: mean((r) => r.actual_points),
    bias: mean((r) => r.actual_points - r.sim_mean),
    inBand: g.filter((r) => r.actual_points >= r.p10 && r.actual_points <= r.p90).length,
    booms: g.filter((r) => r.actual_points > r.p90).length,
    busts: g.filter((r) => r.actual_points < r.p10).length,
  };
}

// one player's coordinates in a lens; null when the lens has no data for him
export function mapPoint(p, lens, weeksByFfa = new Map()) {
  if (lens === "week") {
    return p.sim_mean == null ? null : { x: p.sim_mean, lo: p.p10 ?? p.sim_mean, hi: p.p90 ?? p.sim_mean };
  }
  if (lens === "next") {
    if (!p.horizon?.length) return null;
    return { x: p.sim_mean ?? 0, y: p.horizon.reduce((s, v) => s + (v ?? 0), 0) / p.horizon.length };
  }
  const st = realizedStats(weeksByFfa.get(String(p.ffa_id)));
  return st && { x: st.proj, y: st.actual, n: st.n };
}

// how free agents are ranked into the map: this week's mean, the W0..W3 mean,
// or total actual points (a one-game spike does not outrank a steady starter)
function rankValue(p, pt, lens) {
  return lens === "next" ? lensValue(p, "horizon") : lens === "real" ? pt.y * pt.n : pt.x;
}

// The map's points: my players eligible for slotId ("ALL" = the whole roster)
// + the nFa best free agents eligible for it. kind: starter (my optimal
// lineup) / bench / fa. [{x, y?, lo?, hi?, n?, p, kind}]
export function mapSet({ roster, freeAgents = [], slotId = "ALL", lens, nFa = 0, weeksByFfa }) {
  const elig = (p) => slotId === "ALL" || slotSet(p).has(slotId);
  const points = (rows, kind) => rows.filter(elig).map((p) => {
    const pt = mapPoint(p, lens, weeksByFfa);
    return pt && { ...pt, p, kind: kind ?? (p.is_optimal_starter ? "starter" : "bench"), v: rankValue(p, pt, lens) };
  }).filter(Boolean);
  const mine = new Set(roster.map((p) => String(p.player_id)));
  const fa = points(freeAgents.filter((p) => !mine.has(String(p.player_id))), "fa")
    .sort((a, b) => b.v - a.v).slice(0, nFa);
  return [...points(roster), ...fa];
}

// the slot most of these players are eligible for (the flex): the default view
export function defaultSlot(starting, players) {
  const n = (id) => players.filter((p) => slotSet(p).has(id)).length;
  return starting.reduce((a, s) => (a == null || n(s.id) > n(a.id) ? s : a), null)?.id ?? "ALL";
}
