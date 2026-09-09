// Lineup Lab — optimizer output as an actionable start/sit interface.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, posBadge, coverageDot, deltaSpan, rankTable } from "../components.js";
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
    { key: "current", label: "Current", align: "right" },
    { key: "optimal", label: "Optimal", align: "right" },
    { key: "_d", label: "Δ", align: "right", fmt: (v, r) => deltaSpan(v, r._isProb ? "pp" : "pts") },
  ]);
}

function playerLine(p, rec) {
  const arrow = rec === "in" ? el("span", { style: "color:#28e757;font-weight:600" }, " ↑ START")
    : rec === "out" ? el("span", { style: "color:#ff5b6e;font-weight:600" }, " ↓ BENCH") : null;
  return el("div", {
    style: "display:flex;align-items:center;gap:10px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06)" +
      (p.is_optimal_starter ? ";background:rgba(0,255,249,.04)" : ""),
  },
    el("span", { style: "width:34px" }, posBadge(p.position)),
    el("span", { style: "flex:1;color:#fff" }, p.player_name,
      p.injury_status && p.injury_status !== "ACTIVE" && p.injury_status !== "NORMAL"
        ? el("span", { style: "color:#ffae58;font-size:11px" }, ` ${p.injury_status}`) : null,
      arrow),
    el("span", { style: "width:44px;color:#9298ae;font-size:12px" }, p.nfl_team || ""),
    el("span", { style: "width:120px;color:#9298ae;font-size:12px;font-variant-numeric:tabular-nums" },
      `${fmt.points(p.p10)}–${fmt.points(p.p90)}`),
    el("span", { style: "width:52px;text-align:right;font-weight:600;font-variant-numeric:tabular-nums" }, fmt.points(p.sim_mean)),
    el("span", { style: "width:56px;text-align:right" }, coverageDot(p.coverage_class)));
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
      el("div", { style: "font-size:12px;color:#9298ae;margin-top:8px" },
        `${ev.n_substitutions} substitution${ev.n_substitutions === 1 ? "" : "s"} · bench value ${fmt.points(ev.bench_value)}` +
        (ev.optimal_win_probability < ev.current_win_probability
          ? " · note: the max-points lineup matches up slightly worse against this opponent" : ""))),

    sectionLabel("Recommended moves"),
    recs.length ? rankTable(recs, [
      { key: "recommendation_rank", label: "#", align: "right" },
      { key: "player_in_name", label: "Start" },
      { key: "player_out_name", label: "Bench" },
      { key: "slot", label: "Slot" },
      { key: "delta_expected", label: "Δ pts", align: "right", fmt: (v) => deltaSpan(v, "pts") },
      { key: "delta_win_probability", label: "Δ win", align: "right", fmt: (v) => deltaSpan(v, "pp") },
    ]) : banner("empty", "No lineup substitutions recommended — the current lineup is already optimal."),

    sectionLabel(`Starters (${starters.length})`),
    card(...starters.map((p) => playerLine(p, recOf(p)))),
    sectionLabel(`Bench (${bench.length})`),
    card(...bench.map((p) => playerLine(p, recOf(p)))),
    ir.length ? sectionLabel(`IR (${ir.length})`) : null,
    ir.length ? card(...ir.map((p) => playerLine(p, null))) : null,

    sectionLabel("Opportunity map — value vs risk"),
    card(el("div", { id: "lineup-opp" })),
  );

  opportunityScatter(document.getElementById("lineup-opp"),
    roster.filter((p) => p.sim_mean != null).map((p) => ({
      player_name: p.player_name, sim_mean: p.sim_mean, sim_sd: p.sim_sd, pos: fmt.pos(p.position),
    })));
}
