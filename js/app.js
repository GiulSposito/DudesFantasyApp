// Application shell: header (run context + team/run selectors), status
// banners, and page boot. Each .qmd calls boot("<page>") once.

import * as data from "./data.js";
import * as state from "./state.js";
import * as fmt from "./format.js";
import { skeleton, setPlayerTeams, teamLogo } from "./components.js";

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

export function banner(kind, msg) {
  return el("div", { class: `cockpit-banner ${kind}` }, msg);
}

// Replace #app content, dropping null/false entries (native replaceChildren
// would stringify them). Pages call this instead of root.replaceChildren.
export function mount(root, ...kids) {
  root.replaceChildren(...kids.flat(Infinity).filter((k) => k != null && k !== false));
}

// ---- shell -------------------------------------------------------------

let _teams = [];
let _run = null;

// fantasy team row (team_id, team_name, abbrev, logo_url, is_my_team) by id
export function team(id) {
  return _teams.find((t) => String(t.team_id) === String(id)) || { team_id: id, team_name: String(id ?? "–") };
}

async function renderHeader() {
  let bar = document.getElementById("cockpit-header");
  if (!bar) {
    bar = el("div", { id: "cockpit-header" });
    const title = document.querySelector("#title-block-header");
    if (title) title.after(bar); else document.querySelector("main")?.prepend(bar);
  }
  const s = state.get();
  const teamSel = el("select", { "aria-label": "Time", onchange: (e) => state.set({ teamId: e.target.value }) },
    ..._teams.map((t) => el("option", { value: t.team_id, selected: String(t.team_id) === String(s.teamId) ? "" : null }, t.team_name)));
  const runs = await data.getRuns().catch(() => []);
  const runSel = el("select", { "aria-label": "Captura", onchange: (e) => state.set({ runId: e.target.value }) },
    ...runs.map((r) => el("option", { value: r.run_id, selected: r.run_id === s.runId ? "" : null },
      `${r.season} · Semana ${r.week} · ${r.tag}`)));

  bar.replaceChildren(
    teamLogo(team(s.teamId), { size: 26 }),
    el("div", { class: "ctx" },
      el("span", { class: "ctx__week" }, `Semana ${_run.week} · ${_run.season}`),
      el("span", { class: "ctx__tag", title: "Momento da semana em que os dados foram capturados" }, _run.tag),
      el("span", {}, `atualizado ${fmt.since(_run.generated_at)}`)),
    el("span", { class: "spring" }),
    teamSel, runSel,
  );
}

export async function boot(pageName) {
  const app = document.getElementById("app");
  if (!app) return;
  app.replaceChildren(skeleton());

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
  setPlayerTeams(await data.getPlayerTeams().catch(() => new Map()));

  await renderHeader();

  const mod = await import(`./pages/${pageName}.js`);
  const rerender = async () => {
    try {
      await mod.render(app);
    } catch (e) {
      console.error(e);
      app.replaceChildren(banner("error", `Erro ao montar a página: ${e.message}`));
    }
    await renderHeader();
  };
  state.subscribe(rerender);
  await rerender();
}
