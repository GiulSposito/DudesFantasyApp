// Plotly wrappers on one shared dark layout. window.Plotly is loaded by
// js/head.html. Pages pass a container element + plain data; nothing here
// touches the data layer. Frozen after M3 — pages depend on this surface.

const INK = "#d8d8d8";
const MUTED = "#9298ae";
const GRID = "rgba(255,255,255,0.06)";
const ACCENT = "#00fff9";
const BLUE = "#3860be";
const GOOD = "#28e757";
const WARN = "#ffae58";
const BAD = "#ff5b6e";

export const POS_COLOR = { QB: "#f45b92", RB: "#39c6b5", WR: "#3db5e6", TE: "#f0a65a", K: "#a477e8", DST: "#6d85a6" };

export function baseLayout(overrides = {}) {
  return {
    paper_bgcolor: "rgba(0,0,0,0)",
    plot_bgcolor: "rgba(0,0,0,0)",
    font: { family: "Inter, sans-serif", color: INK, size: 12 },
    margin: { l: 52, r: 16, t: 16, b: 40 },
    xaxis: { gridcolor: GRID, zerolinecolor: GRID, tickfont: { color: MUTED }, automargin: true },
    yaxis: { gridcolor: GRID, zerolinecolor: GRID, tickfont: { color: MUTED }, automargin: true },
    legend: { font: { color: MUTED } },
    hoverlabel: { bgcolor: "#131b38", bordercolor: "#343855", font: { color: INK } },
    ...overrides,
  };
}

const CONFIG = { displayModeBar: false, responsive: true };
function draw(el, traces, layout) { if (el) window.Plotly.react(el, traces, layout, CONFIG); }

// Horizontal win-probability split bar.
export function probabilityBar(el, { labelA, probA, labelB, probB }) {
  draw(el, [
    { type: "bar", orientation: "h", x: [probA], y: [""], marker: { color: ACCENT }, name: labelA, hovertemplate: `${labelA}: %{x:.1%}<extra></extra>` },
    { type: "bar", orientation: "h", x: [probB], y: [""], marker: { color: BLUE }, name: labelB, hovertemplate: `${labelB}: %{x:.1%}<extra></extra>` },
  ], baseLayout({
    barmode: "stack", height: 64, margin: { l: 4, r: 4, t: 4, b: 4 },
    xaxis: { range: [0, 1], showticklabels: false, showgrid: false },
    yaxis: { showticklabels: false, showgrid: false }, showlegend: false,
  }));
}

// P10 — P50 — P90 whisker per row.
export function intervalRange(el, rows) {
  const traces = rows.map((r) => ({
    type: "scatter", x: [r.p10, r.p90], y: [r.label, r.label], mode: "lines+markers",
    line: { color: r.color || ACCENT, width: 3 }, marker: { size: 7, color: r.color || ACCENT },
    hovertemplate: `${r.label}<br>P10 %{x:.1f}<extra></extra>`, showlegend: false,
  }));
  rows.forEach((r) => traces.push({
    type: "scatter", x: [r.p50], y: [r.label], mode: "markers",
    marker: { size: 14, color: "#fff", symbol: "line-ns-open", line: { width: 3 } },
    hovertemplate: `${r.label}<br>P50 %{x:.1f}<extra></extra>`, showlegend: false,
  }));
  draw(el, traces, baseLayout({ height: 50 + rows.length * 46, margin: { l: 130, r: 20, t: 8, b: 32 } }));
}

// One bar per starter, expected points, coloured by position.
export function contributionBars(el, players) {
  draw(el, [{
    type: "bar", x: players.map((p) => p.label), y: players.map((p) => p.value),
    marker: { color: players.map((p) => POS_COLOR[p.pos] || BLUE) },
    hovertemplate: "%{x}<br>Expected %{y:.1f}<extra></extra>",
  }], baseLayout({ height: 280, margin: { l: 40, r: 8, t: 8, b: 74 }, xaxis: { tickangle: -40, tickfont: { color: MUTED, size: 10 } } }));
}

// Generic labelled scatter. points: [{x,y,label,pos?,size?,color?}]
function scatter(el, points, { xTitle, yTitle, height = 360, quadrantAt } = {}) {
  const layout = baseLayout({
    height, xaxis: { title: { text: xTitle, font: { color: MUTED } }, gridcolor: GRID, zeroline: true, zerolinecolor: "#4c5579" },
    yaxis: { title: { text: yTitle, font: { color: MUTED } }, gridcolor: GRID, zeroline: true, zerolinecolor: "#4c5579" },
    showlegend: false,
  });
  if (quadrantAt) {
    layout.shapes = [
      { type: "line", x0: quadrantAt.x, x1: quadrantAt.x, yref: "paper", y0: 0, y1: 1, line: { color: "#4c5579", dash: "dot", width: 1 } },
      { type: "line", y0: quadrantAt.y, y1: quadrantAt.y, xref: "paper", x0: 0, x1: 1, line: { color: "#4c5579", dash: "dot", width: 1 } },
    ];
  }
  draw(el, [{
    type: "scatter", mode: "markers+text",
    x: points.map((p) => p.x), y: points.map((p) => p.y),
    text: points.map((p) => p.label), textposition: "top center", textfont: { color: MUTED, size: 9 },
    marker: {
      size: points.map((p) => p.size || 11),
      color: points.map((p) => p.color || (p.pos ? POS_COLOR[p.pos] : ACCENT) || ACCENT),
      line: { color: "#050921", width: 1 },
    },
    hovertext: points.map((p) => p.hover || p.label), hovertemplate: "%{hovertext}<extra></extra>",
  }], layout);
}

// Lineup Lab — x=sim_mean (value), y=sim_sd (risk).
export function opportunityScatter(el, players) {
  scatter(el, players.map((p) => ({ x: p.sim_mean, y: p.sim_sd, label: p.player_name?.split(" ").slice(-1)[0], pos: p.pos,
    hover: `${p.player_name}<br>mean ${p.sim_mean?.toFixed(1)} · sd ${p.sim_sd?.toFixed(1)}` })),
    { xTitle: "Expected points (sim mean)", yTitle: "Risk (sim sd)" });
}

// Waivers — x=Δ expected, y=Δ win probability. One point per add/drop.
export function waiverScatter(el, recs) {
  scatter(el, recs.map((r) => ({ x: r.delta_expected, y: r.delta_win_probability,
    label: r.add_player_name?.split(" ").slice(-1)[0], color: ACCENT,
    hover: `ADD ${r.add_player_name} / DROP ${r.drop_player_name}<br>+${r.delta_expected?.toFixed(1)} pts · ${(r.delta_win_probability * 100).toFixed(1)} pp` })),
    { xTitle: "Δ expected points", yTitle: "Δ win probability", quadrantAt: { x: 0, y: 0 } });
}

// Trades — x=my Δ, y=their Δ, bubble size ~ trade_score.
export function tradeScatter(el, recs) {
  const max = Math.max(1, ...recs.map((r) => r.trade_score || 0));
  scatter(el, recs.map((r) => ({ x: r.my_delta_expected, y: r.their_delta_expected,
    label: r.receive_player_name?.split(" ").slice(-1)[0],
    size: 8 + 22 * ((r.trade_score || 0) / max),
    color: r.partner_is_my_opponent ? WARN : ACCENT,
    hover: `GET ${r.receive_player_name} / GIVE ${r.give_player_name} (${r.other_team_name})<br>you +${r.my_delta_expected?.toFixed(1)} · partner +${r.their_delta_expected?.toFixed(1)} · score ${r.trade_score?.toFixed(1)}` })),
    { xTitle: "My Δ expected", yTitle: "Their Δ expected", quadrantAt: { x: 0, y: 0 } });
}

// Heatmap. z: 2D array; x: col labels; y: row labels.
//   scale: "diverging" (around zmid, red↔green) or "error" (low = good = cyan,
//   high = bad = red). goodHigh flips "error".
export function heatmap(el, { z, x, y, zmid = 0, hover, scale = "diverging" }) {
  const colorscale = scale === "error"
    ? [[0, ACCENT], [0.5, "#1a2447"], [1, BAD]]
    : [[0, BAD], [0.5, "#131b38"], [1, GOOD]];
  const trace = {
    type: "heatmap", z, x, y, colorscale,
    hovertemplate: hover || "%{y} · %{x}: %{z:.2f}<extra></extra>",
    xgap: 2, ygap: 2, colorbar: { tickfont: { color: MUTED }, outlinewidth: 0 },
  };
  if (scale === "diverging") trace.zmid = zmid;
  draw(el, [trace], baseLayout({ height: 60 + y.length * 30, margin: { l: 120, r: 16, t: 8, b: 60 } }));
}

// Dot plot — one row per category, dots at each series value.
export function dotPlot(el, rows, { xTitle } = {}) {
  const traces = [];
  const cats = rows.map((r) => r.label);
  const keys = new Set();
  rows.forEach((r) => Object.keys(r.values || {}).forEach((k) => keys.add(k)));
  for (const k of keys) {
    traces.push({
      type: "scatter", mode: "markers", name: k,
      y: cats, x: rows.map((r) => (r.values ? r.values[k] : null)),
      marker: { size: 10 },
      hovertemplate: `${k} · %{y}: %{x:.1f}<extra></extra>`,
    });
  }
  if (rows[0] && rows[0].consensus != null) {
    traces.push({
      type: "scatter", mode: "markers", name: "consensus",
      y: cats, x: rows.map((r) => r.consensus),
      marker: { size: 14, color: "#fff", symbol: "line-ns-open", line: { width: 3 } },
      hovertemplate: "consensus · %{y}: %{x:.1f}<extra></extra>",
    });
  }
  draw(el, traces, baseLayout({ height: 60 + cats.length * 34, margin: { l: 120, r: 16, t: 8, b: 40 },
    xaxis: { title: { text: xTitle, font: { color: MUTED } }, gridcolor: GRID } }));
}

// Diverging horizontal bars around 0 (e.g. source bias).
export function divergingBars(el, rows, { xTitle } = {}) {
  draw(el, [{
    type: "bar", orientation: "h",
    y: rows.map((r) => r.label), x: rows.map((r) => r.value),
    marker: { color: rows.map((r) => (r.value >= 0 ? WARN : ACCENT)) },
    hovertemplate: "%{y}: %{x:.2f}<extra></extra>",
  }], baseLayout({ height: 60 + rows.length * 26, margin: { l: 120, r: 16, t: 8, b: 40 },
    xaxis: { title: { text: xTitle, font: { color: MUTED } }, zeroline: true, zerolinecolor: "#4c5579", gridcolor: GRID } }));
}

// Slopegraph — two columns, one line per entity. rows: [{label, a, b}]
export function slopegraph(el, rows, { aLabel = "before", bLabel = "after" } = {}) {
  const traces = rows.map((r) => ({
    type: "scatter", mode: "lines+markers+text", x: [0, 1], y: [r.a, r.b],
    line: { color: r.b >= r.a ? GOOD : BAD, width: 2 }, marker: { size: 6 },
    text: [r.label, ""], textposition: "middle left", textfont: { color: MUTED, size: 10 },
    hovertemplate: `${r.label}: %{y:.1f}<extra></extra>`, showlegend: false,
  }));
  draw(el, traces, baseLayout({
    height: 40 + rows.length * 22 + 40,
    xaxis: { tickvals: [0, 1], ticktext: [aLabel, bLabel], range: [-0.35, 1.15], showgrid: false },
    yaxis: { gridcolor: GRID },
  }));
}
