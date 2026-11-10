# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

R analysis codebase for a personal NFL Fantasy Football league ("Dudes"). It scrapes
projections, pulls league data from ESPN's Fantasy API, stores everything as
relational `dm` objects in `data/*.rds`, then runs a Monte-Carlo decision engine
(player/matchup simulation, lineup/free-agent/trade recommendations) and publishes
the results as a static Quarto site. No package, no app server — scripts are run
interactively with `source()` from the project root.

`README.md` is the deep reference for the legacy scripts and data-model ERDs, but it
lags the code — **trust the source for `.season` / `.week` / `.tag` and for which API
is wired in.** For the current, live pipeline, prefer these over `README.md`:
`docs/PIPELINE_OVERVIEW.md` (conceptual walkthrough, extraction → projections →
recommendations), `docs/PIPELINE_RUNBOOK.md` (operational how-to-run), and
`docs/decision_engine_spec.md` (implementation spec for the decision engine).

## Running things

No build, no lint. Everything is `source()`d, and every path in the
code is relative (`./data/...`, `./config/...`), so **the working directory must be
the project root**. Open `DudesApp.Rproj` in RStudio or `setwd()` there first.

- **Weekly cycle (the live path), one entry point:** edit the
  `# MASTER PARAMETERS ####` block near the top of `R/pipeline/data_pipeline.R`
  (`.season`, `.week`, `.tag`), then `source("R/pipeline/data_pipeline.R")`. It runs
  the whole journey in sequence: `importFfa()` (scrapes `ffanalytics`, upserts
  `data/ffa_db.rds`) → `importEspn()` (pulls one ESPN snapshot + player pool via
  `R/api/espn_fantasy_client.R`, upserts `data/espn_db.rds`, 15 `espn_*` tables) →
  `run_decision_pipeline()` (the Monte-Carlo decision engine, `R/decision/`, writes
  `data/decision_db.rds`) → `build_web_bundle()` (Parquet + `manifest.json` under
  `web/data/`) → `quarto publish gh-pages web` (skip with `.publish <- FALSE`). Full
  detail and expected output: `docs/PIPELINE_RUNBOOK.md`.
- To re-run just the decision engine over snapshots already ingested (no re-scrape):
  `source("R/decision/decision_pipeline.R"); run_decision_pipeline(season, week, tag)`.
- Ad-hoc analyses live in `R/snippets/` and are standalone — each reads the `.rds`
  databases and prints/plots. Not part of the pipeline.
- Tests: `source("tests/run_all.R")` runs the plain-`stopifnot` files under
  `tests/decision/` and `tests/web/`, stopping at the first failure;
  `node tests/web/compare.check.mjs` and `node tests/web/trade-sim.check.mjs` check
  the site's JS logic. Known failure and current status:
  `docs/PIPELINE_RUNBOOK.md`, step 6.

**Legacy / dead — moved to `archive/`, do not build on these:**
`archive/R/pipeline/data_pipeline_nfl.R` + `archive/R/api/nfl_*.R` (old NFL Fantasy
API path; `config/config.yml` no longer has `authToken`);
`archive/R/snippets/simulation_machine.R`, `archive/R/analysis/team_optimizer.R`,
`archive/R/analysis/projection_ml.R`, `archive/R/transformation/*` ("gen-1"
simulation/optimization, superseded by `R/decision/` and broken as-is — e.g.
`team_optimizer.R` has an incomplete `readRDS()` call with no path); also 8 more
`R/snippets/*.R` files that read now-nonexistent NFL-era `.rds` tables, moved
alongside. Full list: `docs/PIPELINE_RUNBOOK.md`'s "O que NÃO faz parte do ciclo"
section.

Dependencies are installed ad hoc with `install.packages()` (see README list). Core:
`tidyverse`, `dm`, `glue`, `lubridate`, `ffanalytics`, `httr`/`httr2`, `jsonlite`,
`yaml`. `tidymodels` is only used by the dead `projection_ml.R`. The web-bundle step
also needs `nanoparquet` and the `quarto` CLI.

## Architecture

Data flows one direction, layer to layer:

```
R/api/       ->  R/pipeline/      ->  data/*_db.rds  ->  R/decision/          ->  data/decision_db.rds  ->  R/web/           ->  site Quarto
scrape+API       orchestrate           dm databases       Monte-Carlo              forecasts +                Parquet bundle      static, read-only
                 + upsert                                 decision engine          recommendations             + manifest.json
```

- **`R/api/`** — thin wrappers over external sources. `ffa_projection.R` wraps the
  `ffanalytics` package (multi-site projection scrape, incl. ESPN). `espn_fantasy_client.R`
  is an `httr2` client for the ESPN Fantasy API (self-contained; `espn_snapshot()`
  fetches most of the league in one request), driven by
  `R/pipeline/data_pipeline_espn.R`; `example_espn_342842788.R` shows lower-level
  usage. The legacy NFL Fantasy API wrappers (`nfl_*.R`) now live in
  `archive/R/api/` — dead, see below.
- **`R/pipeline/data_pipeline.R`** — the current one-entry weekly orchestrator:
  `importFfa()` + `importEspn()` build/upsert `ffa_db` and `espn_db`, then it calls
  into `R/decision/` and `R/web/` (see "Running things" above). Each import section
  builds a `dm` (with PKs/FKs), then `updateDB()` merges it into the on-disk `.rds`
  via `dm_rows_upsert` (the ESPN path reconciles schema drift across columns first).
  Raw API responses are cached under `data/temp/` so a run can be reprocessed without
  re-hitting the network. The dead legacy-NFL orchestrator and its `*_playground.R` /
  `*_old.R` scratch siblings live in `archive/R/pipeline/` — do not run them.
- **`data/*_db.rds`** — each file is a single `dm` object (a set of related tables
  with keys), not a plain data frame. Load with `readRDS()`, access tables as
  `db$table_name`. Live tables: `ffa_db`, `espn_db` (15 `espn_*` tables),
  `analytical_db` (historical projection-vs-actual residuals, feeds the decision
  engine's Monte Carlo — rebuilt rarely, not part of the weekly cycle), and
  `decision_db` (9 tables: forecasts, recommendations, and the `current_players` /
  `free_agents` inputs the web bundle reads; one `run_id` per pipeline run,
  accumulates). Dead: `nfl_teams_db`, `nfl_players_db`, `nfl_stats_db`,
  `nfl_round_db`, `nfl_recap_db` (legacy NFL path), `dudes_simulation_db` ("gen-1"
  simulation, superseded). Gitignored. Older/wider copies live in `data/2023/`
  (2019–2023 snapshot) and `historic/` (2019–2025 merge, no keys) — archive only;
  the live pipeline never reads them, only `R/analysis/build_historic_datasets.R`
  reads `historic/` to rebuild `analytical_db`. **See [`DATA_CATALOG.md`](DATA_CATALOG.md)** for the per-table
  dictionary (columns, keys, meaning) and the season/week coverage matrix of every
  copy.
- **`R/decision/`** — the live Monte-Carlo decision engine, orchestrated by
  `decision_pipeline.R::run_decision_pipeline()`. `snapshot.R` + `current_consensus.R`
  pick the FFA/ESPN snapshot and build the per-player consensus projection;
  `player_simulation.R` turns each projection into a distribution by bootstrap-
  resampling centred historical residuals from `analytical_db` (nearest-neighbor pool
  by position + projection value, with a 4-level fallback for thin pools; draws are
  floored at the position's lowest historical score), and folds in realized points
  for players whose game has already locked; `league_state.R`
  (incl. `bridge_espn_to_ffa()`) joins ESPN roster state onto `ffa_id`;
  `matchup_simulation.R` simulates each week's matchups for win probability;
  `lineup_optimizer.R` + `roster_evaluator.R` do exact branch-and-bound lineup
  optimization against the league's real roster slots (no LP solver, pinning locked
  starters via bipartite matching); `free_agents.R` and `trades.R` rank ADD/DROP and
  1×1 trade candidates by delta expected points in three scopes (this week, W1..W3
  from ESPN weekly projections, W0..W3 — see `docs/horizon_projections.md`), with
  delta win probability reported but not ranked on; `decision_db.R` persists
  everything. Full mechanics: `docs/decision_engine_spec.md`.
- **`R/web/`** — `build_web_bundle.R` (+ `bundle/*.R`) reads `data/decision_db.rds`
  (and `espn_db`/`ffa_db`/`analytical_db`) and writes Parquet + `manifest.json` to
  `web/data/`. It never re-simulates or re-bridges ids: its marts reshape and
  aggregate persisted data, and the lineup optimizer runs only for the rosters,
  best-lineup and draft marts. The static Quarto site is a JavaScript app: each
  `web/*.qmd` is a shell calling `boot()`, and `web/js/pages/*.js` query the Parquet
  files in the browser with DuckDB-Wasm (`web/js/data.js`).
- **`archive/R/transformation/`, `archive/R/snippets/simulation_machine.R`,
  `archive/R/analysis/team_optimizer.R`, `archive/R/analysis/projection_ml.R`** — the
  "gen-1" simulation/optimization approach (historical-error resampling +
  ~15 kernel-density seed strategies + greedy slot-filling), fully superseded by
  `R/decision/` and broken as-is today. Kept for reference only, moved out of `R/`
  since nothing in the live pipeline sources them.

### `tag` semantics

`.tag` marks when in the week data was captured, and is part of the primary key on
time-sensitive tables, so multiple tagged versions coexist in the same database
(consumers always take `max(timestamp)`). Main values: `"preWaivers"`/`"posWaivers"`
(around waiver processing; `"preview"` is the older early-week tag), `"preKickoff"`
(ad hoc, right before the first game), `"preTNF"`/`"posTNF"` (around Thursday Night
Football — some players already carry real points after `posTNF`), `"preMNF"` (before
Monday Night), `"final"` (after all games — the only tag `importEspn()` accepts for a
past week, and its ESPN snapshot marks a week closed for the web history marts),
`"season"` (season-level snapshot, week 0). Tags are never validated — a typo creates
a silent orphan partition. Full vocabulary: `docs/PIPELINE_RUNBOOK.md`.

### NFL -> ESPN migration

The league moved to ESPN; the legacy NFL Fantasy pipeline
(`archive/R/pipeline/data_pipeline_nfl.R` + `archive/R/api/nfl_*.R`) is dead
(`config/config.yml` has no `authToken` anymore). ESPN (`R/pipeline/data_pipeline_espn.R`, folded into
`data_pipeline.R`) is now the only live league-data source. Bridging ESPN player ids
to the `ffanalytics` ids the decision engine keys on is done —
`bridge_espn_to_ffa()` in `R/decision/league_state.R:42`.

## Config & secrets

- `config/` and `data/` are gitignored. `config/config.yml` holds identifiers + auth
  cookies for both providers: ESPN (`ESPN_LEAGUEID`, `myTeamEspnId`, `season`, `week`,
  `ESPN_S2`, `ESPN_SWID`) and legacy NFL (`authToken` — absent now, so the NFL
  pipeline's `config$authToken`/`config$leagueId` read as `NULL`).
  `config/score_settings.yml` is the ffanalytics scoring ruleset;
  `config/leagues.json` is an unrelated NFL.com OpenAPI dump.
- `R/api/example_espn_342842788.R` contains real ESPN session cookies in plaintext
  (untracked — do not commit). The ESPN pipeline reads cookies from `config.yml`, not
  this file.

## Legacy / non-code directories

- **`archive/`** — dead/legacy code, kept for reference only, not wired into current
  work. `archive/R_old/` is the previous generation of this project (Yahoo + NFL era);
  `archive/R_old/pipeline/pipeline_description.txt` has a prose walkthrough of the old
  flow. `archive/R/` mirrors the paths of files that used to live directly under `R/`
  before being confirmed dead (see "Legacy / dead" above and `docs/PIPELINE_RUNBOOK.md`).
- **`_bmad/`, `_bmad-output/`, `.claude/skills/`** — an installed BMAD "R Data
  Science" method plus a large set of R skills (tidymodels, shiny, torch, ggplot2,
  bioacoustics, …). Tooling, not project code.
