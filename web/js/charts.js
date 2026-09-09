// Plotly wrappers on one shared dark layout. window.Plotly is loaded by
// js/head.html. Pages pass a container element + plain data; nothing here
// touches the data layer.
//
// M2 ships the shared layout + the charts Command Center / Matchup need.
// opportunityScatter / waiverScatter / tradeScatter / heatmap / dotPlot /
// divergingBars / slopegraph are added by their milestones (M4-M7).

const INK = "#d8d8d8";
const MUTED = "#9298ae";
const GRID = "rgba(255,255,255,0.06)";
const ACCENT = "#00fff9";
const BLUE = "#3860be";

export function baseLayout(overrides = {}) {
  return {
    paper_bgcolor: "rgba(0,0,0,0)",
    plot_bgcolor: "rgba(0,0,0,0)",
    font: { family: "Inter, sans-serif", color: INK, size: 12 },
    margin: { l: 48, r: 16, t: 24, b: 36 },
    xaxis: { gridcolor: GRID, zerolinecolor: GRID, tickfont: { color: MUTED } },
    yaxis: { gridcolor: GRID, zerolinecolor: GRID, tickfont: { color: MUTED } },
    legend: { font: { color: MUTED } },
    hoverlabel: { bgcolor: "#131b38", bordercolor: "#343855", font: { color: INK } },
    ...overrides,
  };
}

const CONFIG = { displayModeBar: false, responsive: true };

function draw(el, traces, layout) {
  window.Plotly.react(el, traces, layout, CONFIG);
}

// Horizontal win-probability split: [labelA valA] ============|===== [valB labelB]
export function probabilityBar(el, { labelA, probA, labelB, probB }) {
  draw(el, [
    { type: "bar", orientation: "h", x: [probA], y: [""], marker: { color: ACCENT }, name: labelA, hovertemplate: `${labelA}: %{x:.1%}<extra></extra>` },
    { type: "bar", orientation: "h", x: [probB], y: [""], marker: { color: BLUE }, name: labelB, hovertemplate: `${labelB}: %{x:.1%}<extra></extra>` },
  ], baseLayout({
    barmode: "stack",
    height: 70,
    margin: { l: 8, r: 8, t: 8, b: 8 },
    xaxis: { range: [0, 1], showticklabels: false, showgrid: false },
    yaxis: { showticklabels: false, showgrid: false },
    showlegend: false,
  }));
}

// p10 — p50 — p90 whisker per row (e.g. one row per team).
export function intervalRange(el, rows) {
  const traces = rows.map((r) => ({
    type: "scatter",
    x: [r.p10, r.p90],
    y: [r.label, r.label],
    mode: "lines+markers",
    line: { color: r.color || ACCENT, width: 3 },
    marker: { size: 6, color: r.color || ACCENT },
    hovertemplate: `${r.label}<br>P10 %{x:.1f}<extra></extra>`,
    showlegend: false,
  }));
  rows.forEach((r) => traces.push({
    type: "scatter", x: [r.p50], y: [r.label], mode: "markers",
    marker: { size: 12, color: "#fff", symbol: "line-ns-open", line: { width: 3 } },
    hovertemplate: `${r.label}<br>P50 %{x:.1f}<extra></extra>`, showlegend: false,
  }));
  draw(el, traces, baseLayout({ height: 60 + rows.length * 44, xaxis: { gridcolor: GRID } }));
}

// One bar per starter, expected points; bars coloured by position.
const POS_COLOR = { QB: "#f45b92", RB: "#39c6b5", WR: "#3db5e6", TE: "#f0a65a", K: "#a477e8", DST: "#6d85a6" };
export function contributionBars(el, players) {
  draw(el, [{
    type: "bar",
    x: players.map((p) => p.label),
    y: players.map((p) => p.value),
    marker: { color: players.map((p) => POS_COLOR[p.pos] || BLUE) },
    hovertemplate: "%{x}<br>Expected %{y:.1f}<extra></extra>",
  }], baseLayout({ height: 300, xaxis: { tickangle: -30, tickfont: { color: MUTED, size: 10 } } }));
}
