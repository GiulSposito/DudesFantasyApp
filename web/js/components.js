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
  return el("span", { class: `coverage-dot ${c.cls}`, title: "Confiança pela cobertura de fontes: " + (coverageClass || "") }, "● " + c.label);
}

export function deltaSpan(x, kind = "pts") {
  if (x == null || Number.isNaN(x)) return el("span", { class: "delta delta--zero" }, "–");
  // below display precision reads as zero, not as a green "+0,0"
  const eps = kind === "pp" ? 0.0005 : 0.05;
  const cls = x >= eps ? "delta--pos" : x <= -eps ? "delta--neg" : "delta--zero";
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
      el("button", { class: "chip", onclick: () => panel.remove() }, "✕ fechar")),
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
  if (!rows.length) return el("div", { class: "cockpit-banner empty" }, opts.empty || "Nada para mostrar.");
  const t = el("table", { class: "cockpit-table" });
  // opts.sort = {key, dir, onSort(key)} makes headers with c.sortable clickable
  const s = opts.sort;
  t.append(el("thead", {}, el("tr", {}, ...cols.map((c) => {
    const sortable = s && c.sortable;
    const arrow = sortable && s.key === c.key ? (s.dir === "asc" ? " ▲" : " ▼") : "";
    return el("th", { class: (c.num ? "num " : "") + (c.tight ? "col-tight " : "") + (sortable ? "sortable" : ""),
      title: c.title || null, onclick: sortable ? () => s.onSort(c.key) : null }, c.label + arrow);
  }))));
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
    avatar(p, { size: 32 }),
    el("div", { class: "player-row__name" }, posBadge(p.position), " ", p.player_name,
      statusBadge(p.injury_status) ? el("span", {}, " ", statusBadge(p.injury_status)) : null,
      p.is_locked ? el("span", {}, " ", lockBadge()) : null,
      rightBadge ? el("span", {}, " ", rightBadge) : null),
    el("div", { class: "player-row__meta hide-sm" }, p.nfl_team || ""),
    el("div", { class: "player-row__meta hide-sm" },
      p.p10 != null ? rangeBar(p.p10, p.p50, p.p90) : ""),
    el("div", { class: "player-row__num player-row__num--strong" }, fmt.points(p.sim_mean)),
    el("div", { class: "player-row__num hide-sm" }, p.is_realized ? fmt.points(p.sim_mean) : "–"),
    el("div", { class: "player-row__num" }, coverageDot(p.coverage_class)));
}

// column header for playerRow's grid - same tracks, labels only.
export function playerRowHeader() {
  return el("div", { class: "player-row player-row--head" },
    el("div", {}, ""),
    el("div", {}, "Jogador"),
    el("div", { class: "hide-sm" }, "Time"),
    el("div", { class: "hide-sm", title: "Faixa simulada: piso (P10) a teto (P90), traço na mediana" }, "Faixa P10–P90"),
    el("div", { class: "player-row__num", title: "Média simulada" }, "Proj"),
    el("div", { class: "player-row__num hide-sm", title: "Pontos reais, depois que o jogo trava" }, "Real"),
    el("div", { class: "player-row__num", title: "Confiança pela cobertura de fontes" }, "Conf"));
}

export function fairnessMeter(value, { min = -10, max = 10 } = {}) {
  const pct = Math.max(0, Math.min(1, (value - min) / (max - min)));
  return el("div", { style: "margin:4px 0" },
    el("div", { style: "display:flex;justify-content:space-between;font-size:11px;color:var(--muted)" },
      el("span", {}, "você ganha mais"), el("span", {}, "equilibrada"), el("span", {}, "ele ganha mais")),
    el("div", { style: "position:relative;height:6px;background:linear-gradient(90deg,#ff5b6e,#131b38,#28e757);border-radius:3px;margin-top:4px" },
      el("div", { style: `position:absolute;left:${(pct * 100).toFixed(1)}%;top:-3px;width:2px;height:12px;background:#fff` })));
}

// ---- media: headshots, team logos --------------------------------------

// player_id -> nfl_team from dimensions/players, filled once by app.boot() so
// a D/ST row can find its NFL logo even when its mart has no team column.
let _playerTeams = new Map();
export function setPlayerTeams(map) { _playerTeams = map || new Map(); }

// ESPN CDN image for a player: headshot for people, the NFL team logo for D/ST
// (ESPN D/ST ids are negative). Returns null when nothing can be derived.
export function headshotUrl(playerId, position, nflTeam) {
  const id = playerId == null ? null : String(playerId);
  const isDst = fmt.pos(position) === "DST" || (id && id.startsWith("-"));
  if (isDst) {
    const abbr = fmt.nflAbbr(nflTeam || _playerTeams.get(id));
    return abbr ? `https://a.espncdn.com/i/teamlogos/nfl/500/${abbr.toLowerCase()}.png` : null;
  }
  if (!id) return null;
  return `https://a.espncdn.com/combiner/i?img=/i/headshots/nfl/players/full/${id}.png&w=96&h=70&cb=1`;
}

function initials(name) {
  const parts = (name || "").replace(/ (Jr\.|Sr\.|II|III|IV)$/, "").split(" ").filter(Boolean);
  return ((parts[0]?.[0] || "") + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase() || "?";
}

// Round player picture. p needs player_name + position and one of
// player_id / espn_id; nfl_team helps D/ST. Falls back to initials tinted by
// position when the CDN has no image.
export function avatar(p, { size = 36, id = null } = {}) {
  const pid = id ?? p.player_id ?? p.espn_id;
  const pc = fmt.pos(p.position).toLowerCase();
  const box = el("span", { class: `avatar avatar--${pc}`, style: `width:${size}px;height:${size}px`,
    title: p.player_name || "" });
  const fallback = () => box.replaceChildren(el("span", { class: "avatar__initials",
    style: `font-size:${Math.round(size * 0.36)}px` }, initials(p.player_name)));
  const url = headshotUrl(pid, p.position, p.nfl_team);
  if (!url) { fallback(); return box; }
  const img = el("img", { src: url, alt: "", loading: "lazy", decoding: "async" });
  img.addEventListener("error", fallback, { once: true });
  box.append(img);
  return box;
}

// Fantasy team logo; custom uploads sometimes fail to load, so fall back to a
// monogram from the team abbreviation (or name).
export function teamLogo(team, { size = 28 } = {}) {
  const name = team?.team_name || "";
  const box = el("span", { class: "team-logo", style: `width:${size}px;height:${size}px`, title: name });
  const label = (team?.abbrev || initials(name)).slice(0, 4);
  const mono = () => box.replaceChildren(el("span", { class: "team-logo__mono",
    style: `font-size:${Math.round(size * (label.length > 3 ? 0.26 : 0.34))}px` }, label));
  if (!team?.logo_url) { mono(); return box; }
  const img = el("img", { src: team.logo_url, alt: "", loading: "lazy" });
  img.addEventListener("error", mono, { once: true });
  box.append(img);
  return box;
}

// logo + name inline
export function teamBadge(team, { size = 24, strong = false } = {}) {
  return el("span", { class: "team-badge" + (strong ? " team-badge--strong" : "") },
    teamLogo(team, { size }), el("span", { class: "team-badge__name" }, team?.team_name || "–"));
}

export function lockBadge() {
  return el("span", { class: "badge-pill badge-pill--locked", title: "Jogo em andamento ou encerrado" }, "🔒");
}

// P10–P90 band with a P50 tick, on a shared 0..max scale so rows compare.
export function rangeBar(p10, p50, p90, max = 40) {
  const pct = (v) => Math.max(0, Math.min(100, ((v ?? 0) / max) * 100));
  const lo = pct(p10), hi = pct(p90), mid = pct(p50);
  return el("span", { class: "range-bar",
    title: `P10 ${fmt.points(p10)} · P50 ${fmt.points(p50)} · P90 ${fmt.points(p90)}` },
    el("span", { class: "range-bar__band", style: `left:${lo}%;width:${Math.max(1, hi - lo)}%` }),
    el("span", { class: "range-bar__mid", style: `left:${mid}%` }));
}

// placeholder layout shown while DuckDB-Wasm warms up
export function skeleton(note = "Carregando dados… a primeira visita leva alguns segundos.") {
  return el("div", { class: "skeleton", "aria-busy": "true" },
    el("div", { class: "skeleton__note" }, note),
    el("div", { class: "skeleton__block skeleton__block--hero" }),
    el("div", { class: "skeleton__row" },
      ...[1, 2, 3, 4].map(() => el("div", { class: "skeleton__block" }))),
    el("div", { class: "skeleton__block skeleton__block--tall" }));
}

// Win-probability split bar, % printed inside each side. A = "my" side.
export function winBar(probA, probB, { labelA = "", labelB = "" } = {}) {
  const a = Math.max(0, Math.min(1, probA ?? 0)), b = Math.max(0, Math.min(1, probB ?? 1 - a));
  return el("div", { class: "winbar", role: "img",
    "aria-label": `${labelA} ${fmt.prob(a, 0)} contra ${labelB} ${fmt.prob(b, 0)}` },
    el("div", { class: "winbar__side winbar__side--a", style: `flex:${a || 0.001}`, title: labelA }, fmt.prob(a, 0)),
    el("div", { class: "winbar__side winbar__side--b", style: `flex:${b || 0.001}`, title: labelB }, fmt.prob(b, 0)));
}

// One side of a move card: avatar + label (Entra / Sai / Você recebe…) + name + meta line.
// f is the player's forecast row when available (sim_mean, p10, p90).
export function moveSide(p, label, kind, f = null) {
  const meta = f ? `${fmt.pos(p.position)} · proj ${fmt.points(f.sim_mean)} · ${fmt.points(f.p10)}–${fmt.points(f.p90)}`
    : fmt.pos(p.position);
  return el("div", { class: "move-side" },
    avatar(p, { size: 44 }),
    el("div", { class: "move-side__text" },
      el("div", { class: `move-side__label move-side__label--${kind}` }, label),
      el("div", { class: "move-side__name", title: p.player_name }, p.player_name),
      el("div", { class: "move-side__meta" }, meta)));
}

// label | bar | value, bar scaled to max
export function gainBar(label, value, max, kind = "pts") {
  const frac = max > 0 ? Math.max(0, value || 0) / max : 0;
  return el("div", { class: "gain-bar" },
    el("span", {}, label), bar(frac, value > 0 ? "var(--good)" : "var(--muted)"),
    el("span", { class: "gain-bar__v" }, deltaSpan(value, kind)));
}
