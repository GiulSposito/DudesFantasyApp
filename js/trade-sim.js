// Trade simulator - pure logic, no DOM (also imported by tests/web/trade-sim.check.mjs).
//
// A trade is valued like the 4for4 / FantasyPros analyzers do: rebuild each
// team's optimal starting lineup before and after, under the league's real slot
// rules, and take the difference. That makes cross-position swaps (WR for RB)
// exact - the flex and the bench absorb the position change. Every lens is
// measured in the same unit, points per week of the optimal starting lineup:
//
//   week     this week's simulated mean (sim_mean)
//   horizon  mean over this week + the next ones (W0..W3): each week its own
//            optimal lineup - W0 on sim_mean, W1..W3 on ESPN's weekly
//            projection (p.horizon, an array of the future weeks' points)
//   season   ESPN rest-of-season projection per remaining team game
//   perf     actual points so far per team game played
//
// Player rows come from the rosters / free_agents marts (+ p.horizon attached
// by the caller from the horizon_projections mart). The horizon lens only
// exists when some player carries p.horizon.

export const LENSES = ["week", "horizon", "season", "perf"];
const BENCH_SLOTS = new Set([20, 21]); // BE, IR
const Z90 = 1.2815516;                 // P90 z-score

const num = (x) => (x == null || Number.isNaN(Number(x)) ? null : Number(x));

// value of one player in one lens (points per week); null-safe, 0 when unknown.
// "hz0".."hz2" = one future week (internal: horizon is their per-week optimum)
export function lensValue(p, lens) {
  if (lens === "week") return num(p.sim_mean) ?? 0;
  if (lens.startsWith("hz")) return num(p.horizon?.[Number(lens.slice(2))]) ?? 0;
  if (lens === "horizon") {
    const h = p.horizon ?? [];
    return ((num(p.sim_mean) ?? 0) + h.reduce((s, x) => s + (num(x) ?? 0), 0)) / (1 + h.length);
  }
  if (lens === "season") return p.ros_games > 0 ? (num(p.ros_points) ?? 0) / p.ros_games : 0;
  return p.games_played > 0 ? (num(p.season_points) ?? 0) / p.games_played : 0;
}

// weekly spread of that value: sim_sd for week/season (weekly volatility), the
// standard error of the per-game average for perf (few games = noisy)
export function lensSd(p, lens) {
  const sd = num(p.sim_sd) ?? 0;
  if (lens === "perf") return p.games_played > 0 ? sd / Math.sqrt(p.games_played) : sd;
  return sd;
}

// this week's lineup excludes IR / OUT players, like the decision engine; the
// future weeks exclude IR only (same as the engine's horizon roster); the
// season projection already discounts injuries, and perf is history
function available(p, lens) {
  if (lens.startsWith("hz") || lens === "horizon") return !p.is_ir;
  if (lens !== "week") return true;
  return !p.is_ir && String(p.injury_status || "").toUpperCase() !== "OUT";
}

export const slotSet = (p) => new Set(String(p.eligible_slot_ids ?? "").split(",").filter(Boolean).map(Number));

// p.horizon = [W1, W2, W3] ESPN weekly points (0 when missing) for the horizon
// lens. hz = data.getHorizon() (Map player_id -> rows)
export function withHorizon(players, hz) {
  const weeks = [...new Set([...hz.values()].flat().map((x) => x.target_week))].sort((a, b) => a - b);
  if (!weeks.length) return players;
  return players.map((p) => {
    const rows = hz.get(String(p.player_id)) ?? [];
    return { ...p, horizon: weeks.map((w) => rows.find((x) => x.target_week === w)?.projection ?? 0) };
  });
}

// starting slots, one entry per seat: [{slot_id, slot}]
export function startingSeats(slots) {
  return slots.filter((s) => !BENCH_SLOTS.has(Number(s.lineup_slot_id)) && s.slot_count > 0)
    .flatMap((s) => Array.from({ length: s.slot_count }, () => ({ slot_id: Number(s.lineup_slot_id), slot: s.slot_label })));
}

// ESPN starters placed on the league's starting seats, in slot order. A seat
// nobody fills comes back with player = null: an empty slot in the ESPN lineup,
// which scores 0 (the engine sums only the starters ESPN reports).
export function fillSeats(starters, slots) {
  const left = [...starters];
  const seats = startingSeats(slots).sort((a, b) => a.slot_id - b.slot_id).map((seat) => {
    const i = left.findIndex((p) => Number(p.lineup_slot_id) === seat.slot_id);
    return { ...seat, player: i < 0 ? null : left.splice(i, 1)[0] };
  });
  // a starter in a slot the league no longer has: keep it visible
  return [...seats, ...left.map((p) => ({ slot_id: Number(p.lineup_slot_id), slot: p.lineup_slot, player: p }))];
}

// Optimal starting lineup by lens value. Greedy, most restrictive seat first.
// ponytail: optimal for nested eligibility (QB/RB/WR/TE + an RB/WR flex, this
// league); a superflex / OP league would need the R branch-and-bound
// (R/decision/lineup_optimizer.R) ported.
export function optimalLineup(players, slots, lens) {
  const pool = players.filter((p) => available(p, lens))
    .map((p) => ({ p, v: lensValue(p, lens), elig: slotSet(p) }))
    .sort((a, b) => b.v - a.v);
  const seats = startingSeats(slots);
  const nElig = (sid) => pool.filter((c) => c.elig.has(sid)).length;
  seats.sort((a, b) => nElig(a.slot_id) - nElig(b.slot_id));
  const used = new Set();
  const lineup = [];
  for (const seat of seats) {
    const pick = pool.find((c) => !used.has(c) && c.elig.has(seat.slot_id));
    if (!pick) continue;
    used.add(pick);
    lineup.push({ ...seat, player: pick.p, value: pick.v });
  }
  return lineup;
}

// team total for a lineup: mean and SD (players independent)
export function teamStats(lineup, lens) {
  const mu = lineup.reduce((s, x) => s + x.value, 0);
  const sd = Math.sqrt(lineup.reduce((s, x) => s + lensSd(x.player, lens) ** 2, 0));
  return { mu, sd };
}

// standard normal CDF (Abramowitz-Stegun 7.1.26, |error| < 1.5e-7)
export function normCdf(x) {
  const t = 1 / (1 + 0.3275911 * Math.abs(x) / Math.SQRT2);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
    * t * Math.exp(-(x * x) / 2);
  return x >= 0 ? (1 + y) / 2 : (1 - y) / 2;
}

export const winProb = (me, opp) => normCdf((me.mu - opp.mu) / Math.sqrt(me.sd ** 2 + opp.sd ** 2 || 1));

// best free agent value per position (waiver-wire replacement level, VORP)
export function replacementLevels(freeAgents, lens) {
  const out = {};
  for (const p of freeAgents) {
    if (!available(p, lens)) continue;
    const v = lensValue(p, lens);
    if (out[p.position] == null || v > out[p.position]) out[p.position] = v;
  }
  return out;
}

// points per position group of the optimal starters (flex counted at the
// player's own position)
export function positionStrength(players, slots, lens) {
  const out = {};
  for (const x of optimalLineup(players, slots, lens)) out[x.player.position] = (out[x.player.position] || 0) + x.value;
  return out;
}

// 1 = strongest; ties share the better rank
function rankOf(value, values) {
  return 1 + values.filter((v) => v > value + 1e-9).length;
}

// ctx: { rosters, freeAgents, slots, matchups, myTeamId, giveId, partnerId,
//        receiveId, weeksLeft }
export function evaluateTrade(ctx) {
  const id = (x) => String(x);
  const byTeam = new Map();
  for (const p of ctx.rosters) {
    const k = id(p.team_id);
    if (!byTeam.has(k)) byTeam.set(k, []);
    byTeam.get(k).push(p);
  }
  const me = id(ctx.myTeamId), them = id(ctx.partnerId);
  const mine = byTeam.get(me) || [], theirs = byTeam.get(them) || [];
  const give = mine.find((p) => id(p.player_id) === id(ctx.giveId));
  const recv = theirs.find((p) => id(p.player_id) === id(ctx.receiveId));
  if (!give || !recv) return null;

  const mineAfter = [...mine.filter((p) => p !== give), { ...recv, team_id: ctx.myTeamId }];
  const theirsAfter = [...theirs.filter((p) => p !== recv), { ...give, team_id: ctx.partnerId }];
  const afterTeams = new Map(byTeam);
  afterTeams.set(me, mineAfter);
  afterTeams.set(them, theirsAfter);

  // horizon team value = mean of each week's own optimal lineup (exact: a bye
  // week is covered by the bench that week), not one lineup on averaged values
  const nHz = Math.max(0, ...ctx.rosters.map((p) => p.horizon?.length ?? 0));
  const hzWeeks = ["week", ...Array.from({ length: nHz }, (_, i) => `hz${i}`)];
  const stats = (players, lens) => {
    if (lens !== "horizon") return teamStats(optimalLineup(players, ctx.slots, lens), lens);
    const ws = hzWeeks.map((l) => teamStats(optimalLineup(players, ctx.slots, l), l).mu);
    return { mu: ws.reduce((s, x) => s + x, 0) / ws.length, sd: lensSd({}, lens), weeks: ws };
  };
  const lenses = {};
  for (const lens of ctx.lenses ?? LENSES.filter((l) => l !== "horizon" || nHz > 0)) {
    const repl = replacementLevels(ctx.freeAgents, lens);
    const mb = stats(mine, lens), ma = stats(mineAfter, lens);
    const tb = stats(theirs, lens), ta = stats(theirsAfter, lens);
    const player = (p) => {
      const v = lensValue(p, lens);
      return { value: v, sd: lensSd(p, lens), vor: repl[p.position] == null ? null : v - repl[p.position] };
    };
    lenses[lens] = {
      me: { before: mb, after: ma, delta: ma.mu - mb.mu },
      them: { before: tb, after: ta, delta: ta.mu - tb.mu },
      give: player(give), receive: player(recv),
    };

    // league position strength, before / after, with ranks for both teams
    const strength = (teams) => new Map([...teams].map(([k, ps]) => [k, positionStrength(ps, ctx.slots, lens)]));
    const sb = strength(byTeam), sa = strength(afterTeams);
    const positions = [...new Set([...sb.values(), ...sa.values()].flatMap((o) => Object.keys(o)))];
    lenses[lens].strength = positions.map((pos) => {
      const val = (m, k) => m.get(k)?.[pos] ?? 0;
      const leagueBefore = [...sb.keys()].map((k) => val(sb, k));
      const leagueAfter = [...sa.keys()].map((k) => val(sa, k));
      const side = (k) => ({
        before: val(sb, k), after: val(sa, k),
        rankBefore: rankOf(val(sb, k), leagueBefore), rankAfter: rankOf(val(sa, k), leagueAfter),
      });
      return { position: pos, league: [...sb.keys()].map((k) => ({ team_id: k, value: val(sb, k) })),
        me: side(me), them: side(them) };
    });
  }

  // week: chance of beating this week's opponent. The opponent is held at its
  // simulated ESPN starters (matchups mart, same convention as the engine)
  // unless the partner IS the opponent - then its optimal lineup before/after.
  const m = ctx.matchups.find((x) => id(x.home_team_id) === me || id(x.away_team_id) === me);
  const week = lenses.week;
  week.partnerIsOpponent = false;
  if (m) {
    const side = id(m.home_team_id) === me ? "away" : "home";
    const oppId = id(m[`${side}_team_id`]);
    let oppBefore, oppAfter;
    if (oppId === them) {
      week.partnerIsOpponent = true;
      oppBefore = week.them.before;
      oppAfter = week.them.after;
    } else {
      const sd = Math.max(0, (num(m[`${side}_p90`]) - num(m[`${side}_p10`])) / (2 * Z90)) || 0;
      oppBefore = oppAfter = { mu: num(m[`${side}_expected`]) ?? 0, sd };
    }
    week.opponent = { team_id: oppId, before: oppBefore, after: oppAfter };
    week.me.winBefore = winProb(week.me.before, oppBefore);
    week.me.winAfter = winProb(week.me.after, oppAfter);
  }

  // season: total over the remaining fantasy weeks, with a P10-P90 band from
  // the two players' weekly volatility (independent weeks)
  const season = lenses.season;
  const sdDelta = Math.sqrt(season.give.sd ** 2 + season.receive.sd ** 2);
  season.weeksLeft = ctx.weeksLeft;
  season.me.total = season.me.delta * ctx.weeksLeft;
  season.me.band = Z90 * sdDelta * Math.sqrt(Math.max(ctx.weeksLeft, 0));
  season.them.total = season.them.delta * ctx.weeksLeft;

  const perf = lenses.perf;
  perf.give.games = give.games_played ?? 0;
  perf.receive.games = recv.games_played ?? 0;

  return {
    give, receive: recv, lenses,
    locked: Boolean(give.is_locked || recv.is_locked),
  };
}

// weighted score in points per week over the lenses the result has (weights
// need not sum to 1)
export function weightedScore(result, weights, side = "me") {
  const ls = Object.keys(result.lenses);
  const tot = ls.reduce((s, l) => s + (weights[l] || 0), 0) || 1;
  return ls.reduce((s, l) => s + (weights[l] || 0) * result.lenses[l][side].delta, 0) / tot;
}
