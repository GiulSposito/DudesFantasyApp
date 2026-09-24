// Jogadores — forecast table for every projected player + detail drawer.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, mount, team } from "../app.js";
import { sectionLabel, posBadge, coverageDot, rankTable, drawer, kv, statusBadge, sparkline, avatar, rangeBar, teamBadge } from "../components.js";
import { dotPlot } from "../charts.js";

let search = "";
let cov = "ALL";
let owner = "ALL";            // ALL | MINE | OTHERS | FA
let sort = { key: "sim_mean", dir: "desc" };
let limit = 100;

async function detail(row) {
  const [sources, hist] = await Promise.all([
    data.getSourceProjections(row.ffa_id).catch(() => []),
    data.getPlayerHistory(row.ffa_id).catch(() => []),
  ]);
  const weekly = hist.filter((h) => h.week > 0).sort((a, b) => a.season - b.season || a.week - b.week)
    .map((h) => h.actual_points);
  const d = drawer(`${row.player_name}`,
    el("div", { style: "display:flex;gap:12px;align-items:center;margin-bottom:12px" },
      avatar(row, { size: 64 }),
      el("div", {}, posBadge(row.position), " ", el("span", { class: "stat__sub" }, fmt.nflAbbr(row.nfl_team)),
        statusBadge(row.injury_status) ? el("span", {}, " ", statusBadge(row.injury_status)) : null,
        el("div", { style: "margin-top:4px" }, row._team ? teamBadge(team(row._team), { size: 20 }) : el("span", { class: "stat__sub" }, "free agent")))),
    weekly.length > 1 ? el("div", { style: "margin-bottom:10px" },
      el("div", { class: "stat__sub" }, "pontos reais por semana (histórico)"), sparkline(weekly, { w: 260, h: 32 })) : null,
    kv("Projeção (consenso)", fmt.points(row.projection)),
    kv("Média simulada", fmt.points(row.sim_mean)),
    kv("Viés histórico", fmt.points(row.historical_bias, 1)),
    kv("Desvio da simulação", fmt.points(row.sim_sd)),
    sectionLabel("Quantis"),
    kv("P05 / P10 / P25", `${fmt.points(row.p05)} / ${fmt.points(row.p10)} / ${fmt.points(row.p25)}`),
    kv("P50", fmt.points(row.p50)),
    kv("P75 / P90 / P95", `${fmt.points(row.p75)} / ${fmt.points(row.p90)} / ${fmt.points(row.p95)}`),
    sectionLabel("Chance de passar de"),
    kv("10 / 15 pontos", `${fmt.prob(row.prob_gt_10)} / ${fmt.prob(row.prob_gt_15)}`),
    kv("20 / 25 pontos", `${fmt.prob(row.prob_gt_20)} / ${fmt.prob(row.prob_gt_25)}`),
    sectionLabel("Cobertura"),
    kv("Fontes", `${row.n_sources} · ${fmt.coverage(row.coverage_class).label}`),
    sources.length ? sectionLabel("Projeção de cada fonte") : null,
    sources.length ? el("div", { id: "pl-sources" }) : null);
  if (sources.length) {
    dotPlot(d.querySelector("#pl-sources"), [{
      label: row.player_name.split(" ").slice(-1)[0],
      values: Object.fromEntries(sources.map((s) => [s.data_src, s.projected_points])),
      consensus: row.projection,
    }], { xTitle: "pontos projetados" });
  }
}

function chips(values, current, onPick, labels = {}) {
  return values.map((v) => el("button", { class: "chip" + (v === current ? " active" : ""),
    onclick: () => onPick(v) }, labels[v] || v));
}

export async function render(root) {
  const { position, teamId } = state.get();
  const [all, rosters, espnOf] = await Promise.all([
    data.getForecasts({ position, search }), data.getAllRosters(), data.getEspnIdByFfa()]);
  const teamOf = new Map(rosters.map((r) => [String(r.ffa_id), r.team_id]));

  let rows = all.map((r) => ({ ...r, player_id: espnOf.get(String(r.ffa_id)) ?? r.espn_id,
    _team: teamOf.get(String(r.ffa_id)) ?? null }));
  if (cov !== "ALL") rows = rows.filter((r) => r.coverage_class === cov);
  if (owner === "MINE") rows = rows.filter((r) => String(r._team) === String(teamId));
  if (owner === "OTHERS") rows = rows.filter((r) => r._team != null && String(r._team) !== String(teamId));
  if (owner === "FA") rows = rows.filter((r) => r._team == null);
  const dir = sort.dir === "asc" ? 1 : -1;
  rows.sort((a, b) => {
    const x = a[sort.key], y = b[sort.key];
    if (typeof x === "string" || typeof y === "string") return dir * String(x ?? "").localeCompare(String(y ?? ""));
    return dir * ((x ?? -Infinity) - (y ?? -Infinity));
  });
  const shown = rows.slice(0, limit);
  const onSort = (key) => {
    sort = sort.key === key ? { key, dir: sort.dir === "asc" ? "desc" : "asc" } : { key, dir: key === "player_name" ? "asc" : "desc" };
    render(root);
  };

  mount(root,
    el("div", { class: "toolbar" },
      el("input", { class: "field", style: "width:220px;max-width:100%", placeholder: "Buscar jogador…", "aria-label": "Buscar jogador",
        value: search, oninput: (e) => { search = e.target.value; limit = 100; debounced(root); } }),
      ...chips(["ALL", "QB", "RB", "WR", "TE", "K", "DST"], position, (p) => { limit = 100; state.set({ position: p }); }, { ALL: "Todos" })),
    el("div", { class: "toolbar" },
      el("span", { class: "stat__sub" }, "dono"),
      ...chips(["ALL", "MINE", "OTHERS", "FA"], owner, (o) => { owner = o; limit = 100; render(root); },
        { ALL: "Todos", MINE: "Meu time", OTHERS: "Outros times", FA: "Free agents" }),
      el("span", { class: "stat__sub" }, "confiança"),
      ...chips(["ALL", "ensemble", "sparse", "single"], cov, (c) => { cov = c; limit = 100; render(root); },
        { ALL: "Todas", ensemble: "Alta", sparse: "Média", single: "Baixa" })),
    sectionLabel(`${rows.length} jogadores${rows.length > shown.length ? ` · mostrando ${shown.length}` : ""}`),
    rankTable(shown, [
      { key: "player_name", label: "Jogador", sortable: true,
        fmt: (v, r) => el("span", { class: "player-cell" }, avatar(r, { size: 30 }), posBadge(r.position), " ", v) },
      { key: "nfl_team", label: "Time NFL", fmt: (v) => fmt.nflAbbr(v) },
      { key: "_team", label: "Dono", fmt: (v) => v == null ? el("span", { class: "stat__sub" }, "FA") : teamBadge(team(v), { size: 18 }) },
      { key: "p10", label: "Faixa P10–P90", fmt: (v, r) => rangeBar(r.p10, r.p50, r.p90) },
      { key: "projection", label: "Consenso", num: true, sortable: true, fmt: (v) => fmt.points(v) },
      { key: "sim_mean", label: "Proj", num: true, sortable: true, fmt: (v) => el("b", {}, fmt.points(v)) },
      { key: "p90", label: "Teto", num: true, sortable: true, fmt: (v) => fmt.points(v) },
      { key: "prob_gt_20", label: "P(>20)", num: true, sortable: true, fmt: (v) => fmt.prob(v, 0) },
      { key: "n_sources", label: "Fontes", num: true, sortable: true },
      { key: "coverage_class", label: "Conf", num: true, fmt: (v) => coverageDot(v) },
    ], { onRow: detail, sort: { ...sort, onSort } }),
    rows.length > shown.length ? el("button", { class: "chip btn-more", onclick: () => { limit += 100; render(root); } },
      `Mostrar mais ${Math.min(100, rows.length - shown.length)}`) : null,
  );

  if (search) {
    const inp = root.querySelector("input");
    inp.focus();
    inp.setSelectionRange(search.length, search.length);
  }
}

let _t;
function debounced(root) { clearTimeout(_t); _t = setTimeout(() => render(root), 250); }
