// Shared UI primitives — docs/app_design.md. Styling lives in css/theme.scss;
// these just assemble the markup. Frozen surface: pages depend on it.

import { el } from "./app.js";
import * as fmt from "./format.js";

export function sectionLabel(text) {
  return el("div", { class: "section-label" }, text);
}

export function card(...kids) {
  return el("div", { class: "cockpit-card" }, ...kids);
}
export function tightCard(...kids) {
  return el("div", { class: "cockpit-card cockpit-card--tight" }, ...kids);
}

// Big number tile. accent -> cyan value; xl -> hero size.
export function statTile(label, value, sub, { accent = false, xl = false } = {}) {
  return el("div", { class: "stat" },
    el("div", { class: "stat__label" }, label),
    el("div", { class: "stat__value" + (accent ? " stat__value--accent" : "") + (xl ? " stat__value--xl" : "") }, value),
    sub != null ? el("div", { class: "stat__sub" }, sub) : null);
}
export function statRow(tiles) {
  return el("div", { class: "stat-row" }, ...tiles);
}

export function posBadge(position) {
  const p = fmt.pos(position);
  return el("span", { class: fmt.posClass(p) }, p);
}

// injury / status pill; returns null for healthy states
export function statusBadge(injuryStatus) {
  const s = (injuryStatus || "").toUpperCase();
  if (!s || s === "ACTIVE" || s === "NORMAL" || s === "PLAYING") return null;
  if (s === "OUT" || s === "IR" || s === "SUSPENSION") return el("span", { class: "badge-pill badge-pill--out" }, s);
  if (s.startsWith("Q") || s === "DOUBTFUL" || s === "PROBABLE" || s === "DAY_TO_DAY")
    return el("span", { class: "badge-pill badge-pill--q" }, s === "DAY_TO_DAY" ? "DTD" : s.slice(0, 1) + (s === "DOUBTFUL" ? "D" : ""));
  return el("span", { class: "badge-pill badge-pill--q" }, s);
}
export function badge(text, kind = "accent") {
  return el("span", { class: `badge-pill badge-pill--${kind}` }, text);
}

export function coverageDot(coverageClass) {
  const c = fmt.coverage(coverageClass);
  return el("span", { class: `coverage-dot ${c.cls}`, title: coverageClass || "" }, "● " + c.label);
}

export function deltaSpan(x, kind = "pts") {
  if (x == null || Number.isNaN(x)) return el("span", { class: "delta delta--zero" }, "–");
  const cls = x > 0 ? "delta--pos" : x < 0 ? "delta--neg" : "delta--zero";
  const txt = kind === "pp" ? fmt.deltaPp(x)
    : kind === "raw" ? (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(1)
    : fmt.deltaPts(x);
  return el("span", { class: `delta ${cls}` }, txt);
}

// inline proportional bar, 0..1
export function bar(frac, color) {
  return el("div", { class: "bar" },
    el("div", { class: "bar__fill", style: `width:${Math.max(0, Math.min(1, frac || 0)) * 100}%` +
      (color ? `;background:${color}` : "") }));
}

// tiny inline SVG sparkline from a numeric series
export function sparkline(values, { w = 96, h = 22 } = {}) {
  const v = (values || []).filter((x) => x != null && !Number.isNaN(x));
  if (v.length < 2) return el("span", { class: "stat__sub" }, "–");
  const min = Math.min(...v), max = Math.max(...v), span = max - min || 1;
  const step = w / (v.length - 1);
  const d = v.map((x, i) => `${i === 0 ? "M" : "L"}${(i * step).toFixed(1)},${(h - ((x - min) / span) * (h - 4) - 2).toFixed(1)}`).join(" ");
  const svg = `<svg class="sparkline" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">` +
    `<path d="${d}"/></svg>`;
  return el("span", { class: "sparkline", html: svg });
}

// right-hand drawer. Returns the element; .remove() closes it.
export function drawer(titleText, ...body) {
  document.getElementById("cockpit-drawer")?.remove();
  const panel = el("div", { id: "cockpit-drawer" },
    el("div", { style: "display:flex;justify-content:space-between;align-items:center;margin-bottom:12px" },
      el("div", { class: "drawer__title" }, titleText),
      el("button", { class: "chip", onclick: () => panel.remove() }, "✕ close")),
    ...body.flat().filter((k) => k != null && k !== false));
  document.body.append(panel);
  return panel;
}
// key/value line for the drawer
export function kv(k, v) {
  return el("div", { class: "kv" }, el("span", {}, k), el("span", {}, v));
}

// ranking / data table. cols: [{key,label,fmt,num,tight}]. opts.onRow(row).
export function rankTable(rows, cols, opts = {}) {
  if (!rows.length) return el("div", { class: "cockpit-banner empty" }, opts.empty || "Nothing to show.");
  const t = el("table", { class: "cockpit-table" });
  t.append(el("thead", {}, el("tr", {}, ...cols.map((c) =>
    el("th", { class: (c.num ? "num " : "") + (c.tight ? "col-tight" : "") }, c.label)))));
  const tb = el("tbody");
  for (const r of rows) {
    tb.append(el("tr", opts.onRow ? { class: "clickable", onclick: () => opts.onRow(r) } : {},
      ...cols.map((c) => {
        const v = r[c.key];
        return el("td", { class: (c.num ? "num " : "") + (c.tight ? "col-tight" : "") },
          c.fmt ? c.fmt(v, r) : fmt.naDash(v));
      })));
  }
  t.append(tb);
  return el("div", { class: "cockpit-tablewrap" }, t);
}

// player line for roster / list views (docs/app_design.md §15)
export function playerRow(p, { badge: rightBadge, optimal = false } = {}) {
  return el("div", { class: "player-row" + (optimal ? " player-row--optimal" : "") },
    posBadge(p.position),
    el("div", { class: "player-row__name" }, p.player_name,
      statusBadge(p.injury_status) ? el("span", {}, " ", statusBadge(p.injury_status)) : null,
      rightBadge ? el("span", {}, " ", rightBadge) : null),
    el("div", { class: "player-row__meta hide-sm" }, p.nfl_team || ""),
    el("div", { class: "player-row__meta player-row__num hide-sm" },
      p.p10 != null ? `${fmt.points(p.p10)}–${fmt.points(p.p90)}` : ""),
    el("div", { class: "player-row__num player-row__num--strong" }, fmt.points(p.sim_mean)),
    el("div", { class: "player-row__num" }, coverageDot(p.coverage_class)));
}

export function fairnessMeter(value, { min = -10, max = 10 } = {}) {
  const pct = Math.max(0, Math.min(1, (value - min) / (max - min)));
  return el("div", { style: "margin:4px 0" },
    el("div", { style: "display:flex;justify-content:space-between;font-size:11px;color:var(--muted)" },
      el("span", {}, "you win"), el("span", {}, "fair"), el("span", {}, "they win")),
    el("div", { style: "position:relative;height:6px;background:linear-gradient(90deg,#ff5b6e,#131b38,#28e757);border-radius:3px;margin-top:4px" },
      el("div", { style: `position:absolute;left:${(pct * 100).toFixed(1)}%;top:-3px;width:2px;height:12px;background:#fff` })));
}
