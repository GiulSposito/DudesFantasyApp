// The only module that talks to DuckDB-Wasm. Pages call the typed accessors
// below and never touch SQL for the common cases. Allowed SQL surface:
// WHERE / ORDER BY / LIMIT / GROUP BY / simple aggregates / ILIKE.

import * as duckdb from "@duckdb/duckdb-wasm";
import * as state from "./state.js";

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

// The current/* and source_projections marts stack one run per season + week;
// every accessor over them reads only the run selected in the header.
export const runFilter = () => `run_id = '${String(state.get().runId).replace(/'/g, "")}'`;

// One row per season + week (the bundle keeps only that week's newest run),
// newest first.
export async function getRuns() {
  // created_ms: epoch ms, so the UI never has to decode an arrow timestamp
  return q("SELECT *, epoch_ms(created_at) AS created_ms FROM runs ORDER BY season DESC, week DESC", "runs");
}

export async function getTeams() {
  return q("SELECT * FROM teams ORDER BY team_name", "teams");
}

export async function getStandings() {
  return q(`SELECT * FROM standings WHERE ${runFilter()} ORDER BY rank`, "standings");
}

export async function getForecasts({ position = "ALL", search = "" } = {}) {
  let sql = `SELECT * FROM forecasts WHERE ${runFilter()}`;
  if (position && position !== "ALL") sql += ` AND upper(position) = '${position}'`;
  if (search) sql += ` AND player_name ILIKE '%${search.replace(/'/g, "")}%'`;
  sql += " ORDER BY sim_mean DESC";
  return q(sql, "forecasts");
}

export async function getRoster(teamId) {
  return q(`SELECT * FROM rosters WHERE ${runFilter()} AND team_id = '${teamId}' ORDER BY lineup_slot_id, sim_mean DESC`, "rosters");
}

export async function getMatchups() {
  return q(`SELECT * FROM matchups WHERE ${runFilter()} ORDER BY matchup_id`, "matchups");
}

export async function getMyMatchup() {
  const rows = await q(`SELECT * FROM matchups WHERE ${runFilter()} AND is_my_matchup = true LIMIT 1`, "matchups");
  return rows[0] || null;
}

export async function getMatchupForTeam(teamId) {
  const rows = await q(
    `SELECT * FROM matchups WHERE ${runFilter()} AND (home_team_id = '${teamId}' OR away_team_id = '${teamId}') LIMIT 1`,
    "matchups",
  );
  return rows[0] || null;
}

export async function getLineupEvaluation(teamId) {
  const rows = await q(`SELECT * FROM lineup_evaluations WHERE ${runFilter()} AND team_id = '${teamId}' LIMIT 1`, "lineup_evaluations");
  return rows[0] || null;
}

export async function getLineupRecommendations(teamId) {
  return q(`SELECT * FROM lineup_recommendations WHERE ${runFilter()} AND team_id = '${teamId}' ORDER BY recommendation_rank`, "lineup_recommendations");
}

export async function getWaiverRecommendations(teamId) {
  return q(`SELECT * FROM waiver_recommendations WHERE ${runFilter()} AND team_id = '${teamId}' ORDER BY recommendation_rank`, "waiver_recommendations");
}

export async function getTradeRecommendations() {
  return q(`SELECT * FROM trade_recommendations WHERE ${runFilter()} ORDER BY recommendation_rank`, "trade_recommendations");
}

export async function getFreeAgents({ position = "ALL" } = {}) {
  let sql = `SELECT * FROM free_agents WHERE ${runFilter()}`;
  if (position && position !== "ALL") sql += ` AND upper(position) = '${position}'`;
  sql += " ORDER BY sim_mean DESC";
  return q(sql, "free_agents");
}

export async function getForecast(ffaId) {
  const rows = await q(`SELECT * FROM forecasts WHERE ${runFilter()} AND ffa_id = '${ffaId}' LIMIT 1`, "forecasts");
  return rows[0] || null;
}

export async function getForecastByEspnId(espnId) {
  const rows = await q(`SELECT * FROM forecasts WHERE ${runFilter()} AND espn_id = '${espnId}' LIMIT 1`, "forecasts");
  return rows[0] || null;
}

export async function getSourceProjections(ffaId) {
  return q(`SELECT * FROM source_projections WHERE ${runFilter()} AND ffa_id = '${ffaId}' ORDER BY data_src`, "source_projections");
}

export async function getSourceAccuracy() {
  return q("SELECT * FROM source_accuracy ORDER BY season DESC, data_src, position", "source_accuracy");
}

export async function getPlayerHistory(ffaId) {
  return q(`SELECT season, week, actual_points FROM player_points WHERE ffa_id = '${ffaId}' AND week > 0 ORDER BY season, week`,
    "player_points");
}

export async function getConsensusHistory({ season = null, limit = 4000 } = {}) {
  let sql = "SELECT season, week, position, coverage_class, source_sd, abs_residual, residual FROM consensus_history WHERE week > 0";
  if (season) sql += ` AND season = ${Number(season)}`;
  sql += ` ORDER BY season DESC, week DESC LIMIT ${Number(limit)}`;
  return q(sql, "consensus_history");
}

export async function getDataHealth() {
  const rows = await q(`SELECT * FROM data_health WHERE ${runFilter()} LIMIT 1`, "data_health");
  return rows[0] || null;
}

// Forecast rows for a set of ffa_ids (cards that show several players at once).
export async function getForecastsByIds(ffaIds) {
  const ids = [...new Set(ffaIds.filter((x) => x != null).map((x) => `'${x}'`))];
  if (!ids.length) return [];
  return q(`SELECT * FROM forecasts WHERE ${runFilter()} AND ffa_id IN (${ids.join(",")})`, "forecasts");
}

// player_id -> nfl_team, for D/ST logos where a mart carries no team column.
export async function getPlayerTeams() {
  const rows = await q("SELECT player_id, nfl_team FROM players", "players");
  return new Map(rows.map((r) => [String(r.player_id), r.nfl_team]));
}

// Every rostered player (all teams), for owner filters.
export async function getAllRosters() {
  return q(`SELECT team_id, team_name, player_id, ffa_id FROM rosters WHERE ${runFilter()}`, "rosters");
}


// Team ranks per completed week (standings / cumulative points / survival),
// up to the week selected in the header.
export async function getLeagueRanks() {
  const { season, week } = state.get();
  return q(`SELECT * FROM league_ranks WHERE season = ${Number(season)} AND week <= ${Number(week)}
            ORDER BY week, team_id`, "league_ranks");
}

// Best possible starting lineups (rostered / free agents) from real points,
// only for weeks with a "final" snapshot; empty while the week is open.
export async function getBestLineups() {
  const { season, week } = state.get();
  return q(`SELECT * FROM best_lineups WHERE season = ${Number(season)} AND week = ${Number(week)}
            ORDER BY kind, slot_order`, "best_lineups");
}

// Win-probability path of one matchup across the week's snapshots.
export async function getMatchupHistory(week, matchupId) {
  return q(`SELECT * FROM matchup_history WHERE week = ${Number(week)} AND matchup_id = '${matchupId}'
            ORDER BY created_at`, "matchup_history");
}

// Warm DuckDB-Wasm up as soon as the module loads: the first query then does
// not pay the ~5-10 s engine start on top of its own work.
loadManifest().then(() => db()).catch(() => { /* boot() reports the error */ });
