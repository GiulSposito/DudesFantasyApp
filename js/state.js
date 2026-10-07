// Canonical UI selection: { season, week, runId, teamId, position }.
// Resolution order: URL query -> localStorage -> manifest defaults.
// set() writes URL (replaceState) + localStorage and notifies subscribers.
// No full page reload on change.

const KEY = "cockpit.state";
const listeners = new Set();
let _state = null;

function readStored() {
  try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch { return {}; }
}
function writeStored() {
  try { localStorage.setItem(KEY, JSON.stringify(_state)); } catch { /* private mode */ }
}
function writeUrl() {
  const u = new URL(window.location.href);
  const p = u.searchParams;
  p.set("season", _state.season);
  p.set("week", _state.week);
  p.set("run", _state.runId);
  if (_state.teamId != null) p.set("team", _state.teamId); else p.delete("team");
  if (_state.position && _state.position !== "ALL") p.set("position", _state.position);
  else p.delete("position");
  history.replaceState(null, "", u);
}

// runs: rows of runs.parquet (one per season + week). A stored run is only
// reused while the published bundle is the same one it was picked under, so a
// newly published week opens on that week instead of the last one browsed.
export function init(manifest, defaultTeamId = null, runs = []) {
  const qp = Object.fromEntries(new URL(window.location.href).searchParams);
  const stored = readStored();
  const c = manifest.current;
  const sameBundle = stored.bundle === c.run_id;
  const run = [qp.run, sameBundle ? stored.runId : null, c.run_id]
    .map((id) => runs.find((r) => r.run_id === id))
    .find(Boolean) || { run_id: c.run_id, season: c.season, week: c.week };
  _state = {
    bundle: c.run_id,
    season: Number(run.season),
    week: Number(run.week),
    runId: run.run_id,
    teamId: qp.team ?? stored.teamId ?? defaultTeamId,
    position: qp.position ?? stored.position ?? "ALL",
  };
  writeStored();
}

export function get() {
  return { ..._state };
}

export function set(patch) {
  const next = { ..._state, ...patch };
  if (JSON.stringify(next) === JSON.stringify(_state)) return;
  _state = next;
  writeStored();
  writeUrl();
  emit();
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function emit() {
  for (const fn of listeners) {
    try { fn(get()); } catch (e) { console.error(e); }
  }
}
