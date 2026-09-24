// Display formatting — one place so every screen renders numbers the same way.
// Interface in pt-BR: decimal comma, Portuguese labels.

const LOCALE = "pt-BR";

function num(x, dp) {
  return Number(x).toLocaleString(LOCALE, { minimumFractionDigits: dp, maximumFractionDigits: dp });
}

export function points(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  return num(x, dp);
}

export function prob(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  return num(Number(x) * 100, dp) + "%";
}

export function deltaPts(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  const s = Number(x) >= 0 ? "+" : "−";
  return s + num(Math.abs(Number(x)), dp) + " pts";
}

export function deltaPp(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  const v = Number(x) * 100;
  const s = v >= 0 ? "+" : "−";
  return s + num(Math.abs(v), dp) + " p.p.";
}

const POS = ["QB", "RB", "WR", "TE", "K", "DST"];
export function pos(p) {
  const norm = (p || "").toUpperCase().replace("D/ST", "DST").replace("DEF", "DST");
  return POS.includes(norm) ? norm : (p || "–");
}
export function posClass(p) {
  return "pos-badge " + pos(p).toLowerCase();
}

// coverage_class -> {label, cls} for the confidence dot
export function coverage(c) {
  switch (c) {
    case "ensemble": return { label: "ALTA", cls: "high" };
    case "sparse":   return { label: "MÉDIA", cls: "medium" };
    case "single":   return { label: "BAIXA", cls: "low" };
    default:         return { label: "–", cls: "" };
  }
}

export function naDash(x) {
  return x == null || x === "" || Number.isNaN(x) ? "–" : x;
}

// ISO timestamp -> "24 set 17:12"
export function ts(iso) {
  if (!iso) return "–";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "–";
  const mon = d.toLocaleString(LOCALE, { month: "short" }).replace(".", "");
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${d.getDate()} ${mon} ${hh}:${mm}`;
}

// "há 37 min" style age from an ISO timestamp
export function since(iso) {
  if (!iso) return "";
  const secs = (Date.now() - new Date(iso).getTime()) / 1000;
  if (Number.isNaN(secs)) return "";
  if (secs < 90) return "agora";
  if (secs < 5400) return `há ${Math.round(secs / 60)} min`;
  if (secs < 172800) return `há ${Math.round(secs / 3600)} h`;
  return `há ${Math.round(secs / 86400)} dias`;
}

// FFA-style NFL abbreviations -> ESPN's (the logo CDN keys on ESPN's).
const NFL_ABBR = { SFO: "SF", KCC: "KC", GBP: "GB", NEP: "NE", NOS: "NO", TBB: "TB",
  LVR: "LV", JAC: "JAX", WAS: "WSH", LA: "LAR", SD: "LAC", OAK: "LV" };
export function nflAbbr(t) {
  const u = (t || "").toUpperCase();
  return NFL_ABBR[u] || u;
}
