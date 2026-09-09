// The only module that talks to DuckDB-Wasm. Pages call the typed accessors
// below and never touch SQL for the common cases. Allowed SQL surface:
// WHERE / ORDER BY / LIMIT / GROUP BY / simple aggregates / ILIKE.

import * as duckdb from "@duckdb/duckdb-wasm";

let _manifest = null;
let _dbPromise = null;
let _conn = null;
const _registered = new Set();

export async function loadManifest() {
  if (_manifest) return _manifest;
  const res = await fetch("./data/manifest.json", { cache: "no-cache" });
  if (!res.ok) throw new Error(`manifest.json not found (${res.status}). Run build_web_bundle().`);
  _manifest = await res.json();
  const major = String(_manifest.schema_version || "").split(".")[0];
  if (major !== "1") {
    throw new Error(`Unsupported bundle schema ${_manifest.schema_version} — this app expects 1.x`);
  }
  return _manifest;
}

async function db() {
  if (_dbPromise) return _dbPromise;
  _dbPromise = (async () => {
    const bundle = await duckdb.selectBundle(duckdb.getJsDelivrBundles());
    const workerUrl = URL.createObjectURL(
      new Blob([`importScripts("${bundle.mainWorker}");`], { type: "text/javascript" })
    );
    const worker = new Worker(workerUrl);
    const logger = new duckdb.ConsoleLogger(duckdb.LogLevel.WARNING);
    const instance = new duckdb.AsyncDuckDB(logger, worker);
    await instance.instantiate(bundle.mainModule, bundle.pthreadWorker);
    URL.revokeObjectURL(workerUrl);
    _conn = await instance.connect();
    return instance;
  })();
  return _dbPromise;
}

// Register a mart as a DuckDB view, lazily, from the manifest path.
export async function register(name) {
  if (_registered.has(name)) return;
  const m = await loadManifest();
  const rel = m.datasets[name];
  if (!rel) throw new Error(`Unknown dataset "${name}"`);
  await db();
  const url = new URL(`./data/${rel}`, window.location.href).href;
  const file = `${name}.parquet`;
  await (await db()).registerFileURL(file, url, duckdb.DuckDBDataProtocol.HTTP, false);
  await _conn.query(`CREATE OR REPLACE VIEW ${name} AS SELECT * FROM read_parquet('${file}')`);
  _registered.add(name);
}

// Run SQL over already-registered views. Returns plain row objects.
export async function q(sql, ...deps) {
  await Promise.all(deps.map(register));
  await db();
  const result = await _conn.query(sql);
  return result.toArray().map((r) => {
    const o = r.toJSON();
    // arrow returns BigInt for int64 — normalise to Number for the UI
    for (const k of Object.keys(o)) if (typeof o[k] === "bigint") o[k] = Number(o[k]);
    return o;
  });
}

// ---- typed accessors -----------------------------------------------------

export async function getRun() {
  const m = await loadManifest();
  return { ...m.current, privacy: m.privacy, generated_at: m.generated_at };
}

export async function getRuns() {
  return q("SELECT * FROM runs ORDER BY created_at DESC", "runs");
}

export async function getTeams() {
  return q("SELECT * FROM teams ORDER BY team_name", "teams");
}

export async function getStandings() {
  return q("SELECT * FROM standings ORDER BY rank", "standings");
}

export async function getForecasts({ position = "ALL", search = "" } = {}) {
  let sql = "SELECT * FROM forecasts WHERE 1=1";
  if (position && position !== "ALL") sql += ` AND upper(position) = '${position}'`;
  if (search) sql += ` AND player_name ILIKE '%${search.replace(/'/g, "")}%'`;
  sql += " ORDER BY sim_mean DESC";
  return q(sql, "forecasts");
}

export async function getRoster(teamId) {
  return q(`SELECT * FROM rosters WHERE team_id = '${teamId}' ORDER BY lineup_slot_id, sim_mean DESC`, "rosters");
}

export async function getMatchups() {
  return q("SELECT * FROM matchups ORDER BY matchup_id", "matchups");
}

export async function getMyMatchup() {
  const rows = await q("SELECT * FROM matchups WHERE is_my_matchup = true LIMIT 1", "matchups");
  return rows[0] || null;
}

export async function getMatchupForTeam(teamId) {
  const rows = await q(
    `SELECT * FROM matchups WHERE home_team_id = '${teamId}' OR away_team_id = '${teamId}' LIMIT 1`,
    "matchups",
  );
  return rows[0] || null;
}

export async function getLineupEvaluation(teamId) {
  const rows = await q(`SELECT * FROM lineup_evaluations WHERE team_id = '${teamId}' LIMIT 1`, "lineup_evaluations");
  return rows[0] || null;
}

export async function getLineupRecommendations(teamId) {
  return q(`SELECT * FROM lineup_recommendations WHERE team_id = '${teamId}' ORDER BY recommendation_rank`, "lineup_recommendations");
}

export async function getWaiverRecommendations(teamId) {
  return q(`SELECT * FROM waiver_recommendations WHERE team_id = '${teamId}' ORDER BY recommendation_rank`, "waiver_recommendations");
}

export async function getTradeRecommendations() {
  return q("SELECT * FROM trade_recommendations ORDER BY recommendation_rank", "trade_recommendations");
}

export async function getFreeAgents({ position = "ALL" } = {}) {
  let sql = "SELECT * FROM free_agents WHERE 1=1";
  if (position && position !== "ALL") sql += ` AND upper(position) = '${position}'`;
  sql += " ORDER BY sim_mean DESC";
  return q(sql, "free_agents");
}

export async function getForecast(ffaId) {
  const rows = await q(`SELECT * FROM forecasts WHERE ffa_id = '${ffaId}' LIMIT 1`, "forecasts");
  return rows[0] || null;
}

export async function getSourceProjections(ffaId) {
  return q(`SELECT * FROM source_projections WHERE ffa_id = '${ffaId}' ORDER BY data_src`, "source_projections");
}

export async function getSourceAccuracy() {
  return q("SELECT * FROM source_accuracy ORDER BY season DESC, data_src, position", "source_accuracy");
}

export async function getConsensusHistory({ season = null, limit = 4000 } = {}) {
  let sql = "SELECT season, week, position, coverage_class, source_sd, abs_residual, residual FROM consensus_history WHERE week > 0";
  if (season) sql += ` AND season = ${Number(season)}`;
  sql += ` ORDER BY season DESC, week DESC LIMIT ${Number(limit)}`;
  return q(sql, "consensus_history");
}

export async function getDataHealth() {
  const rows = await q("SELECT * FROM data_health LIMIT 1", "data_health");
  return rows[0] || null;
}
