// Display formatting — one place so every screen renders numbers the same way.

export function points(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  return Number(x).toFixed(dp);
}

export function prob(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  return (Number(x) * 100).toFixed(dp) + "%";
}

export function deltaPts(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  const s = Number(x) >= 0 ? "+" : "−";
  return s + Math.abs(Number(x)).toFixed(dp) + " pts";
}

export function deltaPp(x, dp = 1) {
  if (x == null || Number.isNaN(x)) return "–";
  const v = Number(x) * 100;
  const s = v >= 0 ? "+" : "−";
  return s + Math.abs(v).toFixed(dp) + " pp";
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
    case "ensemble": return { label: "HIGH", cls: "high" };
    case "sparse":   return { label: "MED", cls: "medium" };
    case "single":   return { label: "LOW", cls: "low" };
    default:         return { label: "–", cls: "" };
  }
}

export function naDash(x) {
  return x == null || x === "" || Number.isNaN(x) ? "–" : x;
}

// ISO timestamp -> "Sep 9 07:24"
export function ts(iso) {
  if (!iso) return "–";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "–";
  const mon = d.toLocaleString("en-US", { month: "short" });
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${mon} ${d.getDate()} ${hh}:${mm}`;
}

// "37 min ago" style age from an ISO timestamp
export function since(iso) {
  if (!iso) return "";
  const secs = (Date.now() - new Date(iso).getTime()) / 1000;
  if (Number.isNaN(secs)) return "";
  if (secs < 90) return "just now";
  if (secs < 5400) return `${Math.round(secs / 60)} min ago`;
  if (secs < 172800) return `${Math.round(secs / 3600)} h ago`;
  return `${Math.round(secs / 86400)} d ago`;
}
