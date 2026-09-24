// Liga — standings, roster strength and where each team is strong or weak.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, mount, team } from "../app.js";
import { card, sectionLabel, rankTable, teamBadge, bar } from "../components.js";
import { heatmap, baseLayout } from "../charts.js";

const POSITIONS = ["QB", "RB", "WR", "TE", "K", "DST"];

export async function render(root) {
  const { teamId } = state.get();
  const [standings, evals, optRows] = await Promise.all([
    data.getStandings(),
    data.q("SELECT team_id, optimal_expected FROM lineup_evaluations", "lineup_evaluations"),
    data.q("SELECT team_id, position, sim_mean FROM rosters WHERE is_optimal_starter = true", "rosters"),
  ]);

  const strength = new Map(evals.map((e) => [String(e.team_id), e.optimal_expected]));
  const withStr = standings.map((s) => ({ ...s, opt: strength.get(String(s.team_id)) ?? 0 }));
  const byStrength = [...withStr].sort((a, b) => b.opt - a.opt).map((s, i) => ({ ...s, strength_rank: i + 1 }));
  const strRank = new Map(byStrength.map((s) => [String(s.team_id), s.strength_rank]));
  const byStanding = [...withStr].sort((a, b) => a.rank - b.rank)
    .map((s) => ({ ...s, strength_rank: strRank.get(String(s.team_id)) }));

  // team x position matrix, relative to the league mean for that position
  const cell = {};
  for (const r of optRows) {
    const t = String(r.team_id), p = fmt.pos(r.position);
    cell[t] = cell[t] || {};
    cell[t][p] = (cell[t][p] || 0) + (r.sim_mean || 0);
  }
  const teamIds = byStrength.map((r) => String(r.team_id));
  const posMean = {};
  for (const p of POSITIONS) {
    const vals = teamIds.map((t) => cell[t]?.[p] || 0);
    posMean[p] = vals.reduce((a, b) => a + b, 0) / (vals.length || 1);
  }
  const z = POSITIONS.map((p) => teamIds.map((t) => (cell[t]?.[p] || 0) - posMean[p]));

  const maxOpt = Math.max(...byStrength.map((s) => s.opt)), minOpt = Math.min(...byStrength.map((s) => s.opt));
  const power = card(...byStrength.map((s) => el("div", {
    class: "power-row" + (String(s.team_id) === String(teamId) ? " power-row--mine" : "") },
    el("span", { class: "power-row__rank" }, s.strength_rank),
    teamBadge(team(s.team_id), { size: 26 }),
    bar((s.opt - minOpt * 0.9) / (maxOpt - minOpt * 0.9)),
    el("span", { class: "power-row__v" }, fmt.points(s.opt)))));

  mount(root,
    sectionLabel("Classificação"),
    rankTable(byStanding, [
      { key: "rank", label: "Pos.", num: true, tight: true },
      { key: "team_name", label: "Time", fmt: (v, r) => teamBadge(team(r.team_id), { size: 24, strong: String(r.team_id) === String(teamId) }) },
      { key: "wins", label: "V", num: true },
      { key: "losses", label: "D", num: true },
      { key: "points_for", label: "Pontos pró", num: true, fmt: (v) => fmt.points(v) },
      { key: "points_against", label: "Pontos contra", num: true, fmt: (v) => fmt.points(v) },
      { key: "strength_rank", label: "Força", num: true, title: "Posição no ranking de força do elenco (escalação ótima desta semana)",
        fmt: (v) => `${v}º` },
    ]),

    el("div", { class: "grid-2", style: "margin-top:8px" },
      el("div", {}, sectionLabel("Ranking de força (pontos esperados da escalação ótima)"), power),
      el("div", {}, sectionLabel("Classificação x força do elenco"),
        card(el("div", { id: "lg-quad" }),
          el("div", { class: "note-inline" }, "Alto à esquerda: elenco forte, campanha fraca (deve subir). Baixo à direita: campanha melhor que o elenco.")))),

    sectionLabel("Força por posição contra a média da liga (titulares ótimos)"),
    card(el("div", { id: "lg-heat" }),
      el("div", { class: "note-inline" }, "Verde: acima da média da liga naquela posição, em pontos esperados. Vermelho: abaixo.")),
  );

  heatmap(document.getElementById("lg-heat"), {
    z, x: teamIds.map((t) => team(t).abbrev || team(t).team_name), y: POSITIONS, zmid: 0,
    hover: "%{y} · %{x}: %{z:+.1f} pts vs média<extra></extra>",
  });

  const pts = byStanding.map((r) => ({ x: r.rank, y: r.opt, t: team(r.team_id) }));
  const layout = baseLayout({
    height: 400,
    xaxis: { title: { text: "posição na classificação (1 = líder)", font: { color: "#9298ae" } }, autorange: "reversed", dtick: 1 },
    yaxis: { title: { text: "força do elenco (pontos esperados)", font: { color: "#9298ae" } } },
    showlegend: false,
  });
  // team logos as markers; the circle underneath stays for logos that fail
  const span = Math.max(...pts.map((p) => p.y)) - Math.min(...pts.map((p) => p.y));
  layout.images = pts.filter((p) => p.t.logo_url).map((p) => ({
    source: p.t.logo_url, xref: "x", yref: "y", x: p.x, y: p.y,
    sizex: 1.1, sizey: span * 0.11, xanchor: "center", yanchor: "middle", layer: "above",
  }));
  window.Plotly.react(document.getElementById("lg-quad"), [{
    type: "scatter", mode: "markers",
    x: pts.map((p) => p.x), y: pts.map((p) => p.y),
    text: pts.map((p) => p.t.team_name),
    marker: { size: 26, color: "#1a2447", line: { color: "#4c5579", width: 1 } },
    hovertemplate: "%{text}<br>%{x}º na classificação · força %{y:.1f}<extra></extra>",
  }], layout, { displayModeBar: false, responsive: true });
}
