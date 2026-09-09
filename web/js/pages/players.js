// Player Explorer — terminal-style forecast table + detail drawer.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, mount } from "../app.js";
import { sectionLabel, posBadge, coverageDot, rankTable, drawer, kv, statusBadge, sparkline } from "../components.js";
import { dotPlot } from "../charts.js";

let search = "";
let cov = "ALL";

async function detail(row) {
  const [sources, hist] = await Promise.all([
    data.getSourceProjections(row.ffa_id).catch(() => []),
    data.getPlayerHistory(row.ffa_id).catch(() => []),
  ]);
  const weekly = hist.filter((h) => h.week > 0).sort((a, b) => a.season - b.season || a.week - b.week)
    .map((h) => h.actual_points);
  const d = drawer(`${row.player_name}`,
    el("div", { style: "margin-bottom:10px" }, posBadge(row.position), " ",
      el("span", { class: "stat__sub" }, row.nfl_team || ""),
      statusBadge(row.injury_status) ? el("span", {}, " ", statusBadge(row.injury_status)) : null),
    weekly.length > 1 ? el("div", { style: "margin-bottom:10px" },
      el("div", { class: "stat__sub" }, "weekly actual points"), sparkline(weekly, { w: 260, h: 32 })) : null,
    kv("Projection", fmt.points(row.projection)),
    kv("Simulation mean", fmt.points(row.sim_mean)),
    kv("Historical bias", fmt.points(row.historical_bias, 1)),
    kv("Sim sd", fmt.points(row.sim_sd)),
    sectionLabel("Quantiles"),
    kv("P05 / P10 / P25", `${fmt.points(row.p05)} / ${fmt.points(row.p10)} / ${fmt.points(row.p25)}`),
    kv("P50", fmt.points(row.p50)),
    kv("P75 / P90 / P95", `${fmt.points(row.p75)} / ${fmt.points(row.p90)} / ${fmt.points(row.p95)}`),
    sectionLabel("Threshold probabilities"),
    kv("P(>10 / >15)", `${fmt.prob(row.prob_gt_10)} / ${fmt.prob(row.prob_gt_15)}`),
    kv("P(>20 / >25)", `${fmt.prob(row.prob_gt_20)} / ${fmt.prob(row.prob_gt_25)}`),
    sectionLabel("Coverage"),
    kv("Sources", `${row.n_sources} · ${row.coverage_class}`),
    sources.length ? sectionLabel("Source projections") : null,
    sources.length ? el("div", { id: "pl-sources" }) : null);
  if (sources.length) {
    dotPlot(d.querySelector("#pl-sources"), [{
      label: row.player_name.split(" ").slice(-1)[0],
      values: Object.fromEntries(sources.map((s) => [s.data_src, s.projected_points])),
      consensus: row.projection,
    }], { xTitle: "projected points" });
  }
}

export async function render(root) {
  const { position } = state.get();
  let rows = await data.getForecasts({ position, search });
  if (cov !== "ALL") rows = rows.filter((r) => r.coverage_class === cov);
  const shown = rows.slice(0, 200);

  mount(root,
    
    el("div", { class: "toolbar" },
      el("input", { class: "field", style: "width:220px", placeholder: "Search player…",
        value: search, oninput: (e) => { search = e.target.value; debounced(root); } }),
      ...["ALL", "QB", "RB", "WR", "TE", "K", "DST"].map((p) =>
        el("button", { class: "chip" + (p === position ? " active" : ""),
          onclick: () => state.set({ position: p }) }, p)),
      el("span", { class: "stat__sub" }, "coverage"),
      ...["ALL", "ensemble", "sparse", "single"].map((c) =>
        el("button", { class: "chip" + (c === cov ? " active" : ""),
          onclick: () => { cov = c; render(root); } }, c))),
    sectionLabel(`${rows.length} players${rows.length > shown.length ? ` (showing ${shown.length})` : ""}`),
    rankTable(shown, [
      { key: "player_name", label: "Player" },
      { key: "position", label: "Pos", fmt: (v) => posBadge(v) },
      { key: "nfl_team", label: "Tm" },
      { key: "projection", label: "Proj", num: true, fmt: (v) => fmt.points(v) },
      { key: "sim_mean", label: "Sim", num: true, fmt: (v) => fmt.points(v) },
      { key: "p10", label: "P10", num: true, fmt: (v) => fmt.points(v) },
      { key: "p50", label: "P50", num: true, fmt: (v) => fmt.points(v) },
      { key: "p90", label: "P90", num: true, fmt: (v) => fmt.points(v) },
      { key: "prob_gt_20", label: "P(>20)", num: true, fmt: (v) => fmt.prob(v, 0) },
      { key: "n_sources", label: "Src", num: true },
      { key: "coverage_class", label: "Cov", num: true, fmt: (v) => coverageDot(v) },
    ], { onRow: detail }),
  );

  if (search) {
    const inp = root.querySelector("input");
    inp.focus();
    inp.setSelectionRange(search.length, search.length);
  }
}

let _t;
function debounced(root) { clearTimeout(_t); _t = setTimeout(() => render(root), 250); }
