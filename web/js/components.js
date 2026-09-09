// Shared UI primitives aligned with docs/app_design.md: dark navy cards,
// cyan only for emphasis, tabular numerals, position colours, thin borders.
// Frozen after M3 — pages depend on this surface.

import { el } from "./app.js";
import * as fmt from "./format.js";

export function sectionLabel(text) {
  return el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin:16px 0 6px" }, text.toUpperCase());
}

export function card(...kids) {
  return el("div", { class: "cockpit-card" }, ...kids);
}

// Big number tile. accent=true colours the value cyan.
export function statTile(label, value, sub, accent = false) {
  return el("div", { class: "cockpit-card", style: "flex:1;min-width:120px" },
    el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae" }, label.toUpperCase()),
    el("div", { style: `font-size:24px;font-weight:600;font-variant-numeric:tabular-nums;color:${accent ? "#00fff9" : "#fff"}` }, value),
    sub != null ? el("div", { style: "font-size:12px;color:#9298ae" }, sub) : null);
}

export function statRow(tiles) {
  return el("div", { style: "display:flex;gap:10px;flex-wrap:wrap" }, ...tiles);
}

export function posBadge(position) {
  const p = fmt.pos(position);
  return el("span", { class: fmt.posClass(p) }, p);
}

export function coverageDot(coverageClass) {
  const c = fmt.coverage(coverageClass);
  return el("span", { class: `coverage-dot ${c.cls}`, title: coverageClass || "" }, "● " + c.label);
}

// delta value with red/green tint
export function deltaSpan(x, kind = "pts") {
  if (x == null || Number.isNaN(x)) return el("span", { style: "color:#9298ae" }, "–");
  const col = x > 0 ? "#28e757" : x < 0 ? "#ff5b6e" : "#9298ae";
  const txt = kind === "pp" ? fmt.deltaPp(x) : kind === "raw" ? (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(1) : fmt.deltaPts(x);
  return el("span", { style: `color:${col};font-variant-numeric:tabular-nums` }, txt);
}

// Right-hand slide-over drawer. Returns the drawer element; call .remove() to close.
export function drawer(titleText, ...body) {
  document.getElementById("cockpit-drawer")?.remove();
  const panel = el("div", { id: "cockpit-drawer", style:
    "position:fixed;top:0;right:0;bottom:0;width:min(420px,92vw);z-index:1050;" +
    "background:#131b38;border-left:1px solid #343855;padding:20px;overflow:auto;box-shadow:-8px 0 24px rgba(0,0,0,.4)" },
    el("div", { style: "display:flex;justify-content:space-between;align-items:center;margin-bottom:12px" },
      el("div", { style: "font-family:Poppins,sans-serif;font-weight:600;color:#fff" }, titleText),
      el("button", { class: "btn btn-sm btn-outline-secondary", onclick: () => panel.remove() }, "✕")),
    ...body);
  document.body.append(panel);
  return panel;
}

// Ranking / data table. cols: [{key,label,fmt,cls,align}]. opts.onRow(row) -> click handler.
export function rankTable(rows, cols, opts = {}) {
  const wrap = el("div", { class: "cockpit-tablewrap" });
  const t = el("table", { class: "table table-sm table-dark align-middle", style: "font-variant-numeric:tabular-nums" });
  t.append(el("thead", {}, el("tr", {}, ...cols.map((c) =>
    el("th", { class: c.cls, style: c.align ? `text-align:${c.align}` : null }, c.label)))));
  const tb = el("tbody");
  for (const r of rows) {
    const tr = el("tr", opts.onRow ? { style: "cursor:pointer", onclick: () => opts.onRow(r) } : {},
      ...cols.map((c) => {
        const v = r[c.key];
        const content = c.fmt ? c.fmt(v, r) : fmt.naDash(v);
        return el("td", { class: c.cls, style: c.align ? `text-align:${c.align}` : null }, content);
      }));
    tb.append(tr);
  }
  t.append(tb);
  wrap.append(t);
  return rows.length ? wrap : el("div", { class: "cockpit-banner empty" }, opts.empty || "Nothing to show.");
}

// Simple diverging meter: -1..0..1 position, one marker.
export function fairnessMeter(value, { min = -10, max = 10, leftLabel = "you win", rightLabel = "they win" } = {}) {
  const pct = Math.max(0, Math.min(1, (value - min) / (max - min)));
  return el("div", { style: "margin:4px 0" },
    el("div", { style: "display:flex;justify-content:space-between;font-size:11px;color:#9298ae" },
      el("span", {}, leftLabel), el("span", {}, "fair"), el("span", {}, rightLabel)),
    el("div", { style: "position:relative;height:6px;background:linear-gradient(90deg,#ff5b6e,#131b38,#28e757);border-radius:3px;margin-top:4px" },
      el("div", { style: `position:absolute;left:${(pct * 100).toFixed(1)}%;top:-3px;width:2px;height:12px;background:#fff` })));
}
