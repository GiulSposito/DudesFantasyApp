// Lineup Lab — optimizer output as an actionable start/sit interface.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, deltaSpan, rankTable, playerRow, badge } from "../components.js";
import { opportunityScatter } from "../charts.js";

function comparison(ev) {
  const row = (label, cur, opt, isProb) => ({
    metric: label,
    current: isProb ? fmt.prob(cur) : fmt.points(cur),
    optimal: isProb ? fmt.prob(opt) : fmt.points(opt),
    _d: opt - cur, _isProb: isProb,
  });
  const rows = [
    row("Expected", ev.current_expected, ev.optimal_expected),
    row("P10 (floor)", ev.current_p10, ev.optimal_p10),
    row("Median", ev.current_p50, ev.optimal_p50),
    row("P90 (ceiling)", ev.current_p90, ev.optimal_p90),
    row("Win probability", ev.current_win_probability, ev.optimal_win_probability, true),
  ];
  return rankTable(rows, [
    { key: "metric", label: "" },
    { key: "current", label: "Current", num: true },
    { key: "optimal", label: "Optimal", num: true },
    { key: "_d", label: "Δ", num: true, fmt: (v, r) => deltaSpan(v, r._isProb ? "pp" : "pts") },
  ]);
}

function playerLine(p, rec) {
  const rb = rec === "in" ? badge("↑ start", "start")
    : rec === "out" ? badge("↓ bench", "out") : null;
  return playerRow(p, { badge: rb, optimal: p.is_optimal_starter });
}

export async function render(root) {
  const { teamId } = state.get();
  const [roster, ev, recs] = await Promise.all([
    data.getRoster(teamId), data.getLineupEvaluation(teamId), data.getLineupRecommendations(teamId),
  ]);
  if (!ev) { mount(root,
    banner("empty", "No lineup evaluation for this team/run.")); return; }

  const inIds = new Set(recs.map((r) => String(r.player_in_id)));
  const outIds = new Set(recs.map((r) => String(r.player_out_id)));
  const recOf = (p) => inIds.has(String(p.player_id)) ? "in" : outIds.has(String(p.player_id)) ? "out" : null;

  const starters = roster.filter((p) => p.is_starter).sort((a, b) => a.lineup_slot_id - b.lineup_slot_id);
  const bench = roster.filter((p) => !p.is_starter && !p.is_ir).sort((a, b) => b.sim_mean - a.sim_mean);
  const ir = roster.filter((p) => p.is_ir);

  mount(root,
    
    sectionLabel("Current vs optimal"),
    card(comparison(ev),
      el("div", { class: "stat__sub", style: "margin-top:10px" },
        `${ev.n_substitutions} substitution${ev.n_substitutions === 1 ? "" : "s"} · bench value ${fmt.points(ev.bench_value)}` +
        (ev.optimal_win_probability < ev.current_win_probability
          ? " · note: the max-points lineup matches up slightly worse against this opponent" : ""))),

    sectionLabel("Recommended moves"),
    recs.length ? rankTable(recs, [
      { key: "recommendation_rank", label: "#", num: true },
      { key: "player_in_name", label: "Start" },
      { key: "player_out_name", label: "Bench" },
      { key: "slot", label: "Slot" },
      { key: "delta_expected", label: "Δ pts", num: true, fmt: (v) => deltaSpan(v, "pts") },
      { key: "delta_win_probability", label: "Δ win", num: true, fmt: (v) => deltaSpan(v, "pp") },
    ]) : banner("empty", "No lineup substitutions recommended — the current lineup is already optimal."),

    sectionLabel(`Starters (${starters.length})`),
    el("div", { class: "cockpit-card cockpit-card--tight" }, ...starters.map((p) => playerLine(p, recOf(p)))),
    sectionLabel(`Bench (${bench.length})`),
    el("div", { class: "cockpit-card cockpit-card--tight" }, ...bench.map((p) => playerLine(p, recOf(p)))),
    ir.length ? sectionLabel(`IR (${ir.length})`) : null,
    ir.length ? el("div", { class: "cockpit-card cockpit-card--tight" }, ...ir.map((p) => playerLine(p, null))) : null,

    sectionLabel("Opportunity map — value vs risk"),
    card(el("div", { id: "lineup-opp" })),
  );

  opportunityScatter(document.getElementById("lineup-opp"),
    roster.filter((p) => p.sim_mean != null).map((p) => ({
      player_name: p.player_name, sim_mean: p.sim_mean, sim_sd: p.sim_sd, pos: fmt.pos(p.position),
    })));
}
