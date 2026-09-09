// Projection Lab — why the model should be trusted. Source accuracy history
// + empirical check that source disagreement predicts error.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, mount } from "../app.js";
import { card, sectionLabel } from "../components.js";
import { heatmap, divergingBars, baseLayout } from "../charts.js";

const POSITIONS = ["QB", "RB", "WR", "TE", "K", "DST"];
let metric = "mae";
let season = null;

export async function render(root) {
  const acc = await data.getSourceAccuracy();
  const seasons = [...new Set(acc.map((r) => r.season))].sort((a, b) => b - a);
  if (season == null) season = seasons[0];
  const rows = acc.filter((r) => r.season === season);

  const sources = [...new Set(rows.map((r) => r.data_src))].sort();
  const val = (src, pos) => {
    const m = rows.find((r) => r.data_src === src && fmt.pos(r.position) === pos);
    return m ? m[metric] : null;
  };
  const z = sources.map((s) => POSITIONS.map((p) => val(s, p)));

  // aggregate bias per source (mean over positions weighted by n)
  const bias = sources.map((s) => {
    const rs = rows.filter((r) => r.data_src === s);
    const n = rs.reduce((a, r) => a + (r.n || 0), 0) || 1;
    return { label: s, value: rs.reduce((a, r) => a + (r.bias || 0) * (r.n || 0), 0) / n };
  }).sort((a, b) => a.value - b.value);

  mount(root,
    
    el("div", { style: "display:flex;gap:8px;align-items:center;margin-bottom:10px;flex-wrap:wrap" },
      ...["mae", "rmse", "bias"].map((m) =>
        el("button", { class: "btn btn-sm " + (m === metric ? "btn-info" : "btn-outline-secondary"),
          onclick: () => { metric = m; render(root); } }, m.toUpperCase())),
      el("span", { style: "color:#9298ae;font-size:12px" }, "season"),
      ...seasons.map((s) =>
        el("button", { class: "btn btn-sm " + (s === season ? "btn-info" : "btn-outline-secondary"),
          onclick: () => { season = s; render(root); } }, s))),

    sectionLabel(`Source accuracy — ${metric.toUpperCase()} by position (${season})`),
    card(el("div", { id: "pj-heat" })),

    sectionLabel("Source bias — under-projection ← 0 → over-projection"),
    card(el("div", { id: "pj-bias" })),

    sectionLabel("Does source disagreement predict error?"),
    card(el("div", { id: "pj-consensus" }),
      el("div", { style: "font-size:12px;color:#9298ae" },
        "Each point: one historical player-week. X = spread between sources, Y = |actual − projection|.")),
  );

  heatmap(document.getElementById("pj-heat"), {
    z, x: POSITIONS, y: sources,
    scale: metric === "bias" ? "diverging" : "error", zmid: 0,
    hover: `%{y} · %{x}: %{z:.2f} ${metric}<extra></extra>`,
  });
  divergingBars(document.getElementById("pj-bias"), bias, { xTitle: "mean bias (points)" });

  const ch = await data.getConsensusHistory({ season });
  const pts = ch.filter((r) => r.source_sd != null && r.abs_residual != null);
  window.Plotly.react(document.getElementById("pj-consensus"), [{
    type: "scattergl", mode: "markers",
    x: pts.map((r) => r.source_sd), y: pts.map((r) => r.abs_residual),
    marker: { size: 4, color: "#00fff9", opacity: 0.35 },
    hovertemplate: "spread %{x:.1f} · error %{y:.1f}<extra></extra>",
  }], baseLayout({
    height: 340,
    xaxis: { title: { text: "source sd", font: { color: "#9298ae" } } },
    yaxis: { title: { text: "|actual − projection|", font: { color: "#9298ae" } } },
    showlegend: false,
  }), { displayModeBar: false, responsive: true });
}
