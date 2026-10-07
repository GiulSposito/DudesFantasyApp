// Application shell: header (run context + team/run selectors), status
// banners, and page boot. Each .qmd calls boot("<page>") once.

import * as data from "./data.js";
import * as state from "./state.js";
import * as fmt from "./format.js";
import { skeleton, setPlayerTeams, setPlayerOpener, teamLogo } from "./components.js";
import { openPlayer } from "./player-drawer.js";

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
let _runs = [];
let _run = null;   // runs.parquet row of the selected snapshot

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
  // one option per season + week; each maps to that week's newest snapshot
  const runSel = el("select", { "aria-label": "Semana", onchange: (e) => {
    const r = _runs.find((x) => x.run_id === e.target.value);
    if (r) state.set({ runId: r.run_id, season: Number(r.season), week: Number(r.week) });
  } },
    ..._runs.map((r) => el("option", { value: r.run_id, selected: r.run_id === s.runId ? "" : null },
      `${r.season} · Semana ${r.week}`)));

  bar.replaceChildren(
    teamLogo(team(s.teamId), { size: 26 }),
    el("div", { class: "ctx" },
      el("span", { class: "ctx__week" }, `Semana ${_run.week} · ${_run.season}`),
      el("span", { class: "ctx__tag", title: "Momento da semana em que os dados foram capturados" }, _run.tag),
      el("span", {}, `atualizado ${fmt.since(_run.created_ms)}`)),
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
  _runs = await data.getRuns().catch(() => []);
  const mine = _teams.find((t) => t.is_my_team);
  state.init(manifest, mine ? mine.team_id : (_teams[0]?.team_id ?? null), _runs);
  const pickRun = () => {
    const c = manifest.current;
    _run = _runs.find((r) => r.run_id === state.get().runId) || { ...c, created_ms: manifest.generated_at };
  };
  pickRun();
  setPlayerTeams(await data.getPlayerTeams().catch(() => new Map()));
  setPlayerOpener(openPlayer);

  await renderHeader();

  const mod = await import(`./pages/${pageName}.js`);
  const rerender = async () => {
    pickRun();
    try {
      await mod.render(app);
    } catch (e) {
      console.error(e);
      app.replaceChildren(banner("error", `Erro ao montar a página: ${e.message}`));
    }
    await renderHeader();
  };
  // serialised: a slow render of an older selection never lands after a newer one
  let chain = Promise.resolve();
  state.subscribe(() => { chain = chain.then(rerender); });
  await rerender();
}
