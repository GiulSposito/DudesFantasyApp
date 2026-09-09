// Application shell: header (run context + team/run selectors), status
// banners, and page boot. Each .qmd calls boot("<page>") once.

import * as data from "./data.js";
import * as state from "./state.js";
import * as fmt from "./format.js";

// ---- small DOM helpers (shared by pages) --------------------------------

export function el(tag, attrs = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v;
    else if (k === "html") n.innerHTML = v;
    else if (k.startsWith("on") && typeof v === "function") n.addEventListener(k.slice(2), v);
    else if (v != null) n.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid == null) continue;
    n.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return n;
}

// table(container, rows, [{key, label, fmt, cls}])
export function table(rows, cols) {
  const wrap = el("div", { class: "cockpit-tablewrap" });
  const t = el("table", { class: "table table-sm table-dark align-middle" });
  t.append(el("thead", {}, el("tr", {}, ...cols.map((c) => el("th", { class: c.cls }, c.label)))));
  const tb = el("tbody");
  for (const r of rows) {
    tb.append(el("tr", {}, ...cols.map((c) => {
      const raw = r[c.key];
      return el("td", { class: c.cls }, c.fmt ? c.fmt(raw, r) : fmt.naDash(raw));
    })));
  }
  t.append(tb);
  wrap.append(t);
  return wrap;
}

export function banner(kind, msg) {
  return el("div", { class: `cockpit-banner ${kind}` }, msg);
}

// ---- shell -------------------------------------------------------------

let _teams = [];
let _run = null;

async function renderHeader() {
  let bar = document.getElementById("cockpit-header");
  if (!bar) {
    bar = el("div", { id: "cockpit-header" });
    bar.style.cssText =
      "display:flex;gap:16px;align-items:center;flex-wrap:wrap;padding:10px 0 14px;" +
      "border-bottom:1px solid #343855;margin-bottom:18px;font-size:0.85rem;color:#9298ae";
    document.querySelector("main")?.prepend(bar);
  }
  const s = state.get();
  const teamSel = el("select", { class: "form-select form-select-sm", style: "width:auto;display:inline-block",
    onchange: (e) => state.set({ teamId: e.target.value }) },
    ...(_run?.privacy === "public" ? [] : []),
    ..._teams.map((t) => el("option", { value: t.team_id, selected: String(t.team_id) === String(s.teamId) ? "" : null }, t.team_name)));
  const runs = await data.getRuns().catch(() => []);
  const runSel = el("select", { class: "form-select form-select-sm", style: "width:auto;display:inline-block",
    onchange: (e) => state.set({ runId: e.target.value }) },
    ...runs.map((r) => el("option", { value: r.run_id, selected: r.run_id === s.runId ? "" : null },
      `${r.season} W${r.week} ${r.tag}`)));

  bar.replaceChildren(
    el("strong", { style: "color:#fff;font-family:Poppins,sans-serif;letter-spacing:0.02em" }, "DUDES"),
    el("span", {}, `${_run.season} · Week ${_run.week} · ${_run.tag}`),
    el("span", {}, _run.model_version),
    el("span", {}, `Updated ${fmt.ts(_run.generated_at)} (${fmt.since(_run.generated_at)})`),
    el("span", { style: "flex:1" }),
    el("span", {}, "Team "), teamSel,
    el("span", {}, "Run "), runSel,
  );
}

export async function boot(pageName) {
  const app = document.getElementById("app");
  if (!app) return;
  app.replaceChildren(banner("loading", "Loading…"));

  let manifest;
  try {
    manifest = await data.loadManifest();
  } catch (e) {
    app.replaceChildren(banner("error", e.message));
    return;
  }

  try {
    _teams = await data.getTeams();
  } catch { _teams = []; }
  const mine = _teams.find((t) => t.is_my_team);
  state.init(manifest, mine ? mine.team_id : (_teams[0]?.team_id ?? null));
  _run = await data.getRun();

  await renderHeader();

  const mod = await import(`./pages/${pageName}.js`);
  const rerender = async () => {
    try {
      await mod.render(app);
    } catch (e) {
      console.error(e);
      app.replaceChildren(banner("error", `Failed to render: ${e.message}`));
    }
    await renderHeader();
  };
  state.subscribe(rerender);
  await rerender();
}
