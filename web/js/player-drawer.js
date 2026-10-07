// Player detail drawer, shared by every page. app.boot() registers openPlayer()
// with components.setPlayerOpener(), so any playerLink() / table row opens it.
import * as data from "./data.js";
import * as state from "./state.js";
import * as fmt from "./format.js";
import { el, team } from "./app.js";
import { sectionLabel, posBadge, drawer, kv, statusBadge, sparkline, avatar, rangeBar, teamBadge, oppLabel,
  playerLink } from "./components.js";
import { dotPlot, quantileDensity, densityPoints } from "./charts.js";

// one line of the comparison block; every line shares the grid tracks and the
// rangeBar scale so the bars line up. Other players' lines open their drawer.
function cmpRow(p, max, selected = false) {
  const row = el("div", { class: "cmp-row" + (selected ? " cmp-row--sel" : "") },
    avatar(p, { size: 28 }),
    el("div", { class: "cmp-row__name", title: p.player_name }, p.player_name),
    rangeBar(p.p10, p.p50, p.p90, max),
    el("div", { class: "cmp-row__num" }, fmt.points(p.sim_mean)));
  return selected ? row : playerLink(row, p);
}

// selected player + the header team's players at the same position
function comparison(row, posRows, teamOf) {
  const { teamId } = state.get();
  const t = team(teamId);
  const mates = posRows
    .filter((r) => String(teamOf.get(String(r.ffa_id))) === String(teamId) && String(r.ffa_id) !== String(row.ffa_id))
    .map((r) => ({ ...r, player_id: r.espn_id }))
    .sort((a, b) => b.sim_mean - a.sim_mean);
  const all = [row, ...mates];
  const max = Math.max(10, Math.ceil(Math.max(...all.map((r) => r.p90 ?? 0)) / 5) * 5);
  const pos = fmt.pos(row.position);
  return [
    sectionLabel(`Comparação · ${pos} de ${t.team_name}`),
    el("div", { class: "cmp-row cmp-row--head" },
      el("div", {}, ""), el("div", {}, "Jogador"),
      el("div", { title: "Faixa P10–P90, traço na mediana, escala comum" }, `0 – ${max} pts`),
      el("div", { class: "cmp-row__num" }, "Proj")),
    cmpRow(row, max, true),
    ...mates.map((r) => cmpRow(r, max)),
    mates.length ? null : el("div", { class: "note-inline" }, `${t.team_name} não tem outro ${pos}.`),
  ];
}

function header(row, owner) {
  return el("div", { style: "display:flex;gap:12px;align-items:center;margin-bottom:12px" },
    avatar(row, { size: 64 }),
    el("div", {}, posBadge(row.position), " ", el("span", { class: "stat__sub" }, fmt.nflAbbr(row.nfl_team)),
      statusBadge(row.injury_status) ? el("span", {}, " ", statusBadge(row.injury_status)) : null,
      el("div", { style: "margin-top:4px" }, owner != null ? teamBadge(team(owner), { size: 20 })
        : el("span", { class: "stat__sub" }, "free agent"))));
}

async function detail(row, teamOf) {
  const [sources, hist, posRows] = await Promise.all([
    data.getSourceProjections(row.ffa_id).catch(() => []),
    data.getPlayerHistory(row.ffa_id).catch(() => []),
    data.getForecasts({ position: fmt.pos(row.position) }).catch(() => []),
  ]);
  const hasDensity = densityPoints(row).length > 0;
  const weekly = hist.filter((h) => h.week > 0).sort((a, b) => a.season - b.season || a.week - b.week)
    .map((h) => h.actual_points);
  const d = drawer(`${row.player_name}`,
    header(row, teamOf.get(String(row.ffa_id))),
    weekly.length > 1 ? el("div", { style: "margin-bottom:10px" },
      el("div", { class: "stat__sub" }, "pontos reais por semana (histórico)"), sparkline(weekly, { w: 260, h: 32 })) : null,
    oppLabel(row) ? kv("Adversário", oppLabel(row, { long: true })) : null,
    row.pos_rank != null ? kv("Rank na posição", `${fmt.pos(row.position)}${row.pos_rank} de ${row.pos_count}`) : null,
    kv("Pontos na temporada", fmt.points(row.season_points)),
    kv("Projeção (consenso)", fmt.points(row.projection)),
    kv("Média simulada", fmt.points(row.sim_mean)),
    kv("Viés histórico", fmt.points(row.historical_bias, 1)),
    kv("Desvio da simulação", fmt.points(row.sim_sd)),
    sectionLabel("Quantis"),
    kv("P05 / P10 / P25", `${fmt.points(row.p05)} / ${fmt.points(row.p10)} / ${fmt.points(row.p25)}`),
    kv("P50", fmt.points(row.p50)),
    kv("P75 / P90 / P95", `${fmt.points(row.p75)} / ${fmt.points(row.p90)} / ${fmt.points(row.p95)}`),
    hasDensity ? el("div", { id: "pl-density", style: "margin-top:8px" }) : null,
    hasDensity ? el("div", { class: "note-inline", style: "margin-top:0" },
      "Densidade aproximada pelos quantis (P05–P95). Linha cheia = média; pontilhadas = P10 / P50 / P90.") : null,
    sectionLabel("Chance de passar de"),
    kv("10 / 15 pontos", `${fmt.prob(row.prob_gt_10)} / ${fmt.prob(row.prob_gt_15)}`),
    kv("20 / 25 pontos", `${fmt.prob(row.prob_gt_20)} / ${fmt.prob(row.prob_gt_25)}`),
    sectionLabel("Cobertura"),
    kv("Fontes", `${row.n_sources} · ${fmt.coverage(row.coverage_class).label}`),
    sources.length ? sectionLabel("Projeção de cada fonte") : null,
    sources.length ? el("div", { id: "pl-sources" }) : null,
    comparison(row, posRows, teamOf));
  if (hasDensity) quantileDensity(d.querySelector("#pl-density"), row);
  if (sources.length) {
    dotPlot(d.querySelector("#pl-sources"), [{
      label: row.player_name.split(" ").slice(-1)[0],
      values: Object.fromEntries(sources.map((s) => [s.data_src, s.projected_points])),
      consensus: row.projection,
    }], { xTitle: "pontos projetados" });
  }
}

// p: any player-shaped row with ffa_id and/or player_id / espn_id (ESPN).
// Resolves the selected run's forecast; without one, a minimal drawer.
export async function openPlayer(p) {
  const espnId = p.espn_id ?? p.player_id;
  const [byFfa, rosters] = await Promise.all([
    p.ffa_id != null ? data.getForecast(p.ffa_id) : null,
    data.getAllRosters().catch(() => []),
  ]);
  const fc = byFfa ?? (espnId != null ? await data.getForecastByEspnId(espnId) : null);
  if (!fc) {
    const owner = rosters.find((r) => String(r.player_id) === String(espnId))?.team_id;
    drawer(p.player_name || "Jogador", header(p, owner),
      el("div", { class: "note-inline" }, "Sem projeção para este jogador nesta captura."));
    return;
  }
  const teamOf = new Map(rosters.map((r) => [String(r.ffa_id), r.team_id]));
  await detail({ ...fc, player_id: fc.espn_id ?? espnId, injury_status: fc.injury_status ?? p.injury_status }, teamOf);
}
