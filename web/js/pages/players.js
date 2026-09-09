// Player Explorer — terminal-style forecast table + detail drawer.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, mount } from "../app.js";
import { sectionLabel, posBadge, coverageDot, rankTable, drawer } from "../components.js";
import { dotPlot } from "../charts.js";

let search = "";
let cov = "ALL";

async function detail(row) {
  const sources = await data.getSourceProjections(row.ffa_id).catch(() => []);
  const stat = (label, val) => el("div", { style: "display:flex;justify-content:space-between;padding:2px 0" },
    el("span", { style: "color:#9298ae" }, label), el("span", { style: "font-variant-numeric:tabular-nums" }, val));
  const d = drawer(`${row.player_name}`,
    el("div", { style: "margin-bottom:8px" }, posBadge(row.position), " ", el("span", { style: "color:#9298ae" }, row.nfl_team || "")),
    stat("Projection", fmt.points(row.projection)),
    stat("Simulation mean", fmt.points(row.sim_mean)),
    stat("Historical bias", fmt.points(row.historical_bias, 1)),
    stat("Sim sd", fmt.points(row.sim_sd)),
    sectionLabel("Quantiles"),
    stat("P05 / P10 / P25", `${fmt.points(row.p05)} / ${fmt.points(row.p10)} / ${fmt.points(row.p25)}`),
    stat("P50", fmt.points(row.p50)),
    stat("P75 / P90 / P95", `${fmt.points(row.p75)} / ${fmt.points(row.p90)} / ${fmt.points(row.p95)}`),
    sectionLabel("Threshold probabilities"),
    stat("P(>10 / >15)", `${fmt.prob(row.prob_gt_10)} / ${fmt.prob(row.prob_gt_15)}`),
    stat("P(>20 / >25)", `${fmt.prob(row.prob_gt_20)} / ${fmt.prob(row.prob_gt_25)}`),
    sectionLabel("Coverage"),
    stat("Sources", `${row.n_sources} · ${row.coverage_class}`),
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
    
    el("div", { style: "display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:10px" },
      el("input", { class: "form-control form-control-sm", style: "width:220px", placeholder: "Search player…",
        value: search, oninput: (e) => { search = e.target.value; debounced(root); } }),
      ...["ALL", "QB", "RB", "WR", "TE", "K", "DST"].map((p) =>
        el("button", { class: "btn btn-sm " + (p === position ? "btn-info" : "btn-outline-secondary"),
          onclick: () => state.set({ position: p }) }, p)),
      el("span", { style: "color:#9298ae;font-size:12px" }, "coverage"),
      ...["ALL", "ensemble", "sparse", "single"].map((c) =>
        el("button", { class: "btn btn-sm " + (c === cov ? "btn-info" : "btn-outline-secondary"),
          onclick: () => { cov = c; render(root); } }, c))),
    sectionLabel(`${rows.length} players${rows.length > shown.length ? ` (showing ${shown.length})` : ""}`),
    rankTable(shown, [
      { key: "player_name", label: "Player" },
      { key: "position", label: "Pos", fmt: (v) => posBadge(v) },
      { key: "nfl_team", label: "Tm" },
      { key: "projection", label: "Proj", align: "right", fmt: (v) => fmt.points(v) },
      { key: "sim_mean", label: "Sim", align: "right", fmt: (v) => fmt.points(v) },
      { key: "p10", label: "P10", align: "right", fmt: (v) => fmt.points(v) },
      { key: "p50", label: "P50", align: "right", fmt: (v) => fmt.points(v) },
      { key: "p90", label: "P90", align: "right", fmt: (v) => fmt.points(v) },
      { key: "prob_gt_20", label: "P(>20)", align: "right", fmt: (v) => fmt.prob(v, 0) },
      { key: "n_sources", label: "Src", align: "right" },
      { key: "coverage_class", label: "Cov", align: "right", fmt: (v) => coverageDot(v) },
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
