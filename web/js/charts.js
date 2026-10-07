// Plotly wrappers on one shared dark layout. window.Plotly is loaded by
// js/head.html. Pages pass a container element + plain data; nothing here
// touches the data layer. Pages depend on the exported surface.

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
    separators: ",.",
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
    text: points.map((p) => p.label || ""), textposition: "top center", textfont: { color: MUTED, size: 10 },
    marker: {
      size: points.map((p) => p.size || 11),
      color: points.map((p) => p.color || (p.pos ? POS_COLOR[p.pos] : ACCENT) || ACCENT),
      line: { color: "#050921", width: 1 },
    },
    hovertext: points.map((p) => p.hover || p.label), hovertemplate: "%{hovertext}<extra></extra>",
  }], layout);
}

// Lineup — x=sim_mean (value), y=sim_sd (risk). Only starters get a text
// label (bench names collide); everyone has a hover.
export function opportunityScatter(el, players) {
  scatter(el, players.map((p) => ({ x: p.sim_mean, y: p.sim_sd,
    label: p.is_starter ? p.player_name?.split(" ").slice(-1)[0] : "", pos: p.pos,
    size: p.is_starter ? 13 : 9,
    hover: `${p.player_name}${p.is_starter ? " (titular)" : ""}<br>média ${p.sim_mean?.toFixed(1)} · desvio ${p.sim_sd?.toFixed(1)}` })),
    { xTitle: "Pontos esperados (média simulada)", yTitle: "Risco (desvio da simulação)" });
}

// Trades — x=my Δ, y=their Δ, bubble size ~ trade_score. Names only on hover.
export function tradeScatter(el, recs) {
  const max = Math.max(1, ...recs.map((r) => r.trade_score || 0));
  scatter(el, recs.map((r) => ({ x: r.my_delta_expected, y: r.their_delta_expected,
    size: 9 + 18 * ((r.trade_score || 0) / max),
    color: r.partner_is_my_opponent ? WARN : ACCENT,
    hover: `Recebe ${r.receive_player_name} · cede ${r.give_player_name}<br>${r.other_team_name}<br>você +${r.my_delta_expected?.toFixed(1)} · parceiro +${r.their_delta_expected?.toFixed(1)} · nota ${r.trade_score?.toFixed(1)}` })),
    { xTitle: "Seu ganho (pontos esperados)", yTitle: "Ganho do parceiro", quadrantAt: { x: 0, y: 0 } });
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

// Win-probability path across the week's snapshots. rows: [{tag, p, created_at}]
export function winProbLine(el, rows, { label = "" } = {}) {
  const x = rows.map((r, i) => `${i + 1}. ${r.tag}`);
  draw(el, [{
    type: "scatter", mode: "lines+markers", x, y: rows.map((r) => r.p),
    line: { color: ACCENT, width: 2, shape: "linear" }, marker: { size: 8, color: ACCENT, line: { color: "#050921", width: 1 } },
    hovertemplate: `${label}<br>%{x}: %{y:.1%}<extra></extra>`,
  }], baseLayout({
    height: 240, margin: { l: 48, r: 16, t: 8, b: 70 },
    yaxis: { range: [0, 1], tickformat: ".0%", gridcolor: GRID, zeroline: false, tickfont: { color: MUTED } },
    xaxis: { tickangle: -35, tickfont: { color: MUTED, size: 10 }, gridcolor: GRID },
    shapes: [{ type: "line", xref: "paper", x0: 0, x1: 1, y0: 0.5, y1: 0.5, line: { color: "#4c5579", dash: "dot", width: 1 } }],
    showlegend: false,
  }));
}

// url -> Promise<boolean>: whether the browser can load it (custom ESPN logo
// uploads answer 401 without a session). Cached for the page's lifetime.
const _logoOk = new Map();
function canLoad(url) {
  if (!url) return Promise.resolve(false);
  if (!_logoOk.has(url)) {
    _logoOk.set(url, new Promise((res) => {
      const img = new Image();
      img.onload = () => res(true);
      img.onerror = () => res(false);
      img.src = url;
    }));
  }
  return _logoOk.get(url);
}

// 14 categorical colours readable on the dark background, one per fantasy team.
const TEAM_COLORS = ["#00fff9", "#f45b92", "#28e757", "#ffae58", "#a477e8", "#3db5e6", "#ff5b6e",
  "#f0d35a", "#39c6b5", "#e07be0", "#8fd14f", "#5b8cff", "#ff8a3d", "#c8c8c8"];

// Bump chart (ggbump + ggimage look): one smooth line per team across weeks, the
// team logo on every point and a short label under it. rank 1 = top.
//   rows: [{ week, team_id, rank, label, hover, alert? }]  alert = red ring
//   teamOf(id) -> { team_name, abbrev, logo_url }; colours follow team_id order so
//   a team keeps its colour across the page's charts. selectedTeamId is drawn on
//   top, the others dimmed. A logo that fails to load falls back to the abbrev.
export async function bumpChart(el, rows, { teamOf, selectedTeamId = null } = {}) {
  const sel = selectedTeamId == null ? null : String(selectedTeamId);
  const ids = [...new Set(rows.map((r) => String(r.team_id)))].sort((a, b) => Number(a) - Number(b));
  const color = new Map(ids.map((id, i) => [id, TEAM_COLORS[i % TEAM_COLORS.length]]));
  const dim = (id) => sel != null && id !== sel;
  const order = [...ids.filter((id) => id !== sel), ...ids.filter((id) => id === sel)];

  const traces = order.map((id) => {
    const pts = rows.filter((r) => String(r.team_id) === id).sort((a, b) => a.week - b.week);
    return {
      type: "scatter", mode: "lines+markers+text", name: teamOf(id).team_name,
      x: pts.map((p) => p.week), y: pts.map((p) => p.rank),
      text: pts.map((p) => p.label), textposition: "bottom center",
      textfont: { color: dim(id) ? MUTED : INK, size: 10 },
      line: { color: color.get(id), width: id === sel ? 6 : 4, shape: "spline", smoothing: 0.8 },
      marker: { size: 34, color: "#1a2447",
        line: { color: pts.map((p) => (p.alert ? BAD : color.get(id))), width: pts.map((p) => (p.alert ? 3 : 2)) } },
      opacity: dim(id) ? 0.55 : 1,
      hovertext: pts.map((p) => p.hover), hovertemplate: "%{hovertext}<extra></extra>",
    };
  });

  const weeks = rows.map((r) => r.week);
  const nRanks = Math.max(...rows.map((r) => r.rank));
  const layout = baseLayout({
    height: 140 + nRanks * 52,
    margin: { l: 48, r: 16, t: 8, b: 40 },
    xaxis: { tickprefix: "Semana ", dtick: 1, gridcolor: GRID, zeroline: false,
      tickfont: { color: MUTED }, range: [Math.min(...weeks) - 0.4, Math.max(...weeks) + 0.4] },
    yaxis: { title: { text: "posição", font: { color: MUTED } }, dtick: 1, gridcolor: GRID, zeroline: false,
      tickfont: { color: MUTED }, range: [nRanks + 0.7, 0.4] },
    showlegend: true,
    legend: { orientation: "h", y: -0.04, yanchor: "top", font: { color: MUTED, size: 11 } },
  });
  const ok = new Map(await Promise.all(ids.map(async (id) => [id, await canLoad(teamOf(id).logo_url)])));
  layout.annotations = rows.filter((r) => !ok.get(String(r.team_id))).map((r) => ({
    xref: "x", yref: "y", x: r.week, y: r.rank, showarrow: false,
    text: (teamOf(String(r.team_id)).abbrev || "?").slice(0, 4), font: { color: INK, size: 10 },
  }));
  layout.images = rows.filter((r) => ok.get(String(r.team_id))).map((r) => ({
    source: teamOf(String(r.team_id)).logo_url, xref: "x", yref: "y", x: r.week, y: r.rank,
    sizex: 0.5, sizey: 0.62, xanchor: "center", yanchor: "middle", layer: "above",
    opacity: dim(String(r.team_id)) ? 0.8 : 1,
  }));
  draw(el, traces, layout);
}

// ---- trade simulator --------------------------------------------------

// two-team identity pair, validated (dataviz validate_palette, dark surface
// #0b1230: lightness band, CVD and contrast all pass). Before/after is carried by
// hollow vs filled markers + a connecting line, not by color.
export const SIM_ME = "#1aa3b0";
export const SIM_THEM = "#d4702c";
const SIM_POS_ORDER = ["QB", "RB", "WR", "TE", "K", "D/ST"];

// Position strength of every league team (gray), with my team and the trade
// partner drawn before (hollow) -> after (filled). rows: evaluateTrade()
// lenses[lens].strength. labels: {me, them}.
export function strengthStrip(el, rows, { me, them, unit = "pts/sem" } = {}) {
  const order = SIM_POS_ORDER.filter((p) => rows.some((r) => r.position === p));
  const byPos = new Map(rows.map((r) => [r.position, r]));
  const y = (pos, off) => order.length - 1 - order.indexOf(pos) + off;
  const traces = [{
    type: "scatter", mode: "markers", name: "outros times", showlegend: true,
    x: order.flatMap((p) => byPos.get(p).league.map((t) => t.value)),
    y: order.flatMap((p) => byPos.get(p).league.map(() => y(p, 0))),
    marker: { size: 8, color: "rgba(146,152,174,0.35)", line: { width: 0 } },
    hovertemplate: `%{x:.1f} ${unit}<extra>outro time</extra>`,
  }];
  const side = (key, name, color, off) => {
    const pts = order.map((p) => ({ pos: p, ...byPos.get(p)[key] }));
    traces.push({
      type: "scatter", mode: "lines", showlegend: false, hoverinfo: "skip",
      x: pts.flatMap((s) => [s.before, s.after, null]), y: pts.flatMap((s) => [y(s.pos, off), y(s.pos, off), null]),
      line: { color, width: 2 },
    }, {
      type: "scatter", mode: "markers", name: `${name} antes`, showlegend: false,
      x: pts.map((s) => s.before), y: pts.map((s) => y(s.pos, off)),
      marker: { size: 11, color: "rgba(0,0,0,0)", line: { color, width: 2 } },
      hovertemplate: pts.map((s) => `${name} · ${s.pos} antes: %{x:.1f} ${unit} (${s.rankBefore}º)<extra></extra>`),
    }, {
      type: "scatter", mode: "markers+text", name,
      x: pts.map((s) => s.after), y: pts.map((s) => y(s.pos, off)),
      text: pts.map((s) => (s.rankAfter !== s.rankBefore ? `${s.rankBefore}º→${s.rankAfter}º` : "")),
      textposition: off > 0 ? "top center" : "bottom center", textfont: { color: MUTED, size: 10 },
      marker: { size: 11, color, line: { color: "#0b1230", width: 2 } },
      hovertemplate: pts.map((s) => `${name} · ${s.pos} depois: %{x:.1f} ${unit} (${s.rankAfter}º de ${byPos.get(s.pos).league.length})<extra></extra>`),
    });
  };
  side("me", me, SIM_ME, 0.18);
  side("them", them, SIM_THEM, -0.18);
  draw(el, traces, baseLayout({
    height: 70 + order.length * 52, margin: { l: 52, r: 16, t: 8, b: 40 },
    xaxis: { title: { text: unit, font: { color: MUTED } }, gridcolor: GRID, zeroline: false, tickfont: { color: MUTED } },
    yaxis: { tickvals: order.map((p) => y(p, 0)), ticktext: order, gridcolor: GRID, zeroline: false,
      tickfont: { color: INK }, range: [-0.6, order.length - 0.4] },
    legend: { orientation: "h", y: -0.18, font: { color: MUTED } },
  }));
}

// My team's weekly total as a normal curve before vs after the trade, with the
// opponent's expected score as a reference line.
export function normalOverlay(el, { before, after, opp }) {
  const lo = Math.min(before.mu - 3 * before.sd, after.mu - 3 * after.sd);
  const hi = Math.max(before.mu + 3 * before.sd, after.mu + 3 * after.sd);
  const xs = Array.from({ length: 121 }, (_, i) => lo + ((hi - lo) * i) / 120);
  const pdf = (x, { mu, sd }) => Math.exp(-0.5 * ((x - mu) / sd) ** 2) / (sd * Math.sqrt(2 * Math.PI));
  const curve = (s, name, color, fill) => ({
    type: "scatter", mode: "lines", name, x: xs, y: xs.map((x) => pdf(x, s)),
    line: { color, width: 2 }, fill: fill ? "tozeroy" : "none", fillcolor: fill,
    hovertemplate: `${name}: média ${fmtN(s.mu)} · desvio ${fmtN(s.sd)}<extra></extra>`,
  });
  const shapes = opp ? [{ type: "line", x0: opp.mu, x1: opp.mu, yref: "paper", y0: 0, y1: 1, line: { color: MUTED, width: 1.5 } }] : [];
  const annotations = opp ? [{ x: opp.mu, yref: "paper", y: 1, text: "adversário", showarrow: false,
    font: { color: MUTED, size: 10 }, yanchor: "bottom" }] : [];
  draw(el, [curve(before, "antes", MUTED, null), curve(after, "depois", SIM_ME, SIM_ME + "33")], baseLayout({
    height: 200, margin: { l: 8, r: 8, t: 18, b: 36 }, shapes, annotations,
    xaxis: { title: { text: "pontos do seu time na semana", font: { color: MUTED } }, gridcolor: GRID, zeroline: false, tickfont: { color: MUTED } },
    yaxis: { visible: false, rangemode: "tozero" },
    legend: { orientation: "h", y: 1.12, x: 1, xanchor: "right", font: { color: MUTED } },
  }));
}
const fmtN = (x) => Number(x).toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

// Quantile-based density: each band between distinct quantiles holds Δp of the
// mass over Δq points; the curve is drawn at the quantiles themselves, each
// taking the harmonic mean of its two neighbouring bands (smooths the narrow
// band spikes), cut at P05 / P95. [] when degenerate (realized points).
// ponytail: coarse (7 quantiles, tails past P05/P95 cut); persist draw bins if
// the true shape ever matters
const Q_PROBS = [["p05", 0.05], ["p10", 0.10], ["p25", 0.25], ["p50", 0.50], ["p75", 0.75], ["p90", 0.90], ["p95", 0.95]];
export function densityPoints(f) {
  const pts = [];
  for (const [k, p] of Q_PROBS) {
    const q = f[k];
    if (q == null) continue;
    if (pts.length && Math.abs(q - pts[pts.length - 1].q) < 1e-9) pts[pts.length - 1].p = p;
    else pts.push({ q, p });
  }
  if (f.is_realized || pts.length < 2) return [];
  const band = pts.slice(1).map((b, i) => (b.p - pts[i].p) / (b.q - pts[i].q));
  return pts.map((k, i) => {
    const a = band[i - 1], b = band[i];
    return { x: k.q, y: a == null ? b : b == null ? a : (2 * a * b) / (a + b) };
  });
}

// Player drawer — approximate density with mean (accent) and P10/P50/P90
// (dotted) markers. Returns false and draws nothing when degenerate.
export function quantileDensity(el, f) {
  const pts = densityPoints(f);
  if (!pts.length) return false;
  const color = POS_COLOR[f.position] || ACCENT;
  const vline = (x, c, dash) => ({ type: "line", x0: x, x1: x, yref: "paper", y0: 0, y1: 1, line: { color: c, dash, width: 1.5 } });
  draw(el, [{
    type: "scatter", mode: "lines", x: pts.map((p) => p.x), y: pts.map((p) => p.y),
    line: { color, shape: "spline", smoothing: 1, width: 2 }, fill: "tozeroy", fillcolor: color + "33",
    hoverinfo: "skip",
  }], baseLayout({
    height: 150, margin: { l: 8, r: 8, t: 8, b: 32 }, showlegend: false,
    xaxis: { title: { text: "pontos", font: { color: MUTED } }, gridcolor: GRID, zeroline: false, tickfont: { color: MUTED } },
    yaxis: { visible: false, rangemode: "tozero" },
    shapes: [vline(f.p10, MUTED, "dot"), vline(f.p50, MUTED, "dot"), vline(f.p90, MUTED, "dot"), vline(f.sim_mean, ACCENT, "solid")],
  }));
  return true;
}
