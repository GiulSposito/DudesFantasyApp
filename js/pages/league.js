// League Analyzer — the whole league, not just my team.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, mount } from "../app.js";
import { card, sectionLabel, rankTable } from "../components.js";
import { heatmap, baseLayout } from "../charts.js";

const POSITIONS = ["QB", "RB", "WR", "TE", "K", "DST"];

export async function render(root) {
  const [standings, evals, optRows] = await Promise.all([
    data.getStandings(),
    data.q("SELECT team_id, optimal_expected FROM lineup_evaluations", "lineup_evaluations"),
    data.q("SELECT team_id, position, sim_mean FROM rosters WHERE is_optimal_starter = true", "rosters"),
  ]);

  const strength = new Map(optRows2Map(evals));
  const nameOf = new Map(standings.map((s) => [String(s.team_id), s.team_name]));

  // strength rank
  const ranked = standings.map((s) => ({ ...s, opt: strength.get(String(s.team_id)) ?? 0 }))
    .sort((a, b) => b.opt - a.opt)
    .map((s, i) => ({ ...s, strength_rank: i + 1 }));

  // team x position matrix, normalised against the league mean for that position
  const cell = {};
  for (const r of optRows) {
    const t = String(r.team_id), p = fmt.pos(r.position);
    cell[t] = cell[t] || {};
    cell[t][p] = (cell[t][p] || 0) + (r.sim_mean || 0);
  }
  const teamIds = ranked.map((r) => String(r.team_id));
  const posMean = {};
  for (const p of POSITIONS) {
    const vals = teamIds.map((t) => cell[t]?.[p] || 0);
    posMean[p] = vals.reduce((a, b) => a + b, 0) / (vals.length || 1);
  }
  const z = POSITIONS.map((p) => teamIds.map((t) => (cell[t]?.[p] || 0) - posMean[p]));

  mount(root,
    
    sectionLabel("Standings"),
    rankTable(ranked, [
      { key: "rank", label: "#", num: true },
      { key: "team_name", label: "Team" },
      { key: "wins", label: "W", num: true },
      { key: "losses", label: "L", num: true },
      { key: "points_for", label: "PF", num: true, fmt: (v) => fmt.points(v) },
      { key: "points_against", label: "PA", num: true, fmt: (v) => fmt.points(v) },
      { key: "opt", label: "Strength (optimal exp)", num: true, fmt: (v) => fmt.points(v) },
      { key: "strength_rank", label: "Str #", num: true },
    ]),

    sectionLabel("Position strength vs league average (optimal starters, sim mean)"),
    card(el("div", { id: "lg-heat" })),

    sectionLabel("Standings vs roster strength"),
    card(el("div", { id: "lg-quad" }),
      el("div", { class: "stat__sub" },
        "Upper-left: strong roster, weak record. Lower-right: weak roster, good record.")),
  );

  heatmap(document.getElementById("lg-heat"), {
    z, x: teamIds.map((t) => nameOf.get(t) || t), y: POSITIONS, zmid: 0,
    hover: "%{y} · %{x}: %{z:+.1f} vs league avg<extra></extra>",
  });

  const pts = ranked.map((r) => ({ x: r.rank, y: r.opt, label: r.team_name }));
  window.Plotly.react(document.getElementById("lg-quad"), [{
    type: "scatter", mode: "markers+text",
    x: pts.map((p) => p.x), y: pts.map((p) => p.y),
    text: pts.map((p) => p.label), textposition: "top center", textfont: { color: "#9298ae", size: 9 },
    marker: { size: 12, color: "#00fff9", line: { color: "#050921", width: 1 } },
    hovertemplate: "%{text}<br>rank %{x} · strength %{y:.1f}<extra></extra>",
  }], baseLayout({
    height: 380,
    xaxis: { title: { text: "standings rank (1 = best)", font: { color: "#9298ae" } }, autorange: "reversed" },
    yaxis: { title: { text: "roster strength (optimal expected)", font: { color: "#9298ae" } } },
    showlegend: false,
  }), { displayModeBar: false, responsive: true });
}

function optRows2Map(evals) {
  return evals.map((e) => [String(e.team_id), e.optimal_expected]);
}
