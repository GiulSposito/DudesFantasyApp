// Projeções e fontes — why the model should be trusted. Source accuracy history
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
        el("button", { class: "chip" + (m === metric ? " active" : ""),
          onclick: () => { metric = m; render(root); } }, m.toUpperCase())),
      el("span", { class: "stat__sub" }, "temporada"),
      ...seasons.map((s) =>
        el("button", { class: "chip" + (s === season ? " active" : ""),
          onclick: () => { season = s; render(root); } }, s))),

    sectionLabel(`Precisão de cada fonte: ${metric.toUpperCase()} por posição (${season})`),
    card(el("div", { id: "pj-heat" }),
      el("div", { class: "note-inline" }, "MAE: erro médio absoluto, em pontos. RMSE: pesa mais os erros grandes. Viés: positivo = a fonte projeta mais do que o jogador faz.")),

    sectionLabel("Viés de cada fonte: projeta de menos ← 0 → projeta demais"),
    card(el("div", { id: "pj-bias" })),

    sectionLabel("Quando as fontes discordam, o erro é maior?"),
    card(el("div", { id: "pj-consensus" }),
      el("div", { class: "stat__sub" },
        "Cada ponto é um jogador numa semana passada. X = desvio entre as fontes; Y = |real − projeção|.")),
  );

  heatmap(document.getElementById("pj-heat"), {
    z, x: POSITIONS, y: sources,
    scale: metric === "bias" ? "diverging" : "error", zmid: 0,
    hover: `%{y} · %{x}: %{z:.2f} ${metric}<extra></extra>`,
  });
  divergingBars(document.getElementById("pj-bias"), bias, { xTitle: "viés médio (pontos)" });

  const ch = await data.getConsensusHistory({ season });
  const pts = ch.filter((r) => r.source_sd != null && r.abs_residual != null);
  window.Plotly.react(document.getElementById("pj-consensus"), [{
    type: "scattergl", mode: "markers",
    x: pts.map((r) => r.source_sd), y: pts.map((r) => r.abs_residual),
    marker: { size: 4, color: "#00fff9", opacity: 0.35 },
    hovertemplate: "desvio %{x:.1f} · erro %{y:.1f}<extra></extra>",
  }], baseLayout({
    height: 340,
    xaxis: { title: { text: "desvio entre fontes", font: { color: "#9298ae" } } },
    yaxis: { title: { text: "|real − projeção|", font: { color: "#9298ae" } } },
    showlegend: false,
  }), { displayModeBar: false, responsive: true });
}
