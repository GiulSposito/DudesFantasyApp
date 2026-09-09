# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

R analysis codebase for a personal NFL Fantasy Football league ("Dudes"). It scrapes
projections, pulls league data from a Fantasy API, stores everything as relational
`dm` objects in `data/*.rds`, then runs Monte-Carlo player simulations and lineup
optimization on top. No package, no app server — scripts are run interactively with
`source()` from the project root.

`README.md` is the deep reference (pipeline stages, all 15+ simulation strategies,
data-model ERDs). Read it when you need detail on a specific stage. It lags the code
on parameters and config keys — **trust the source for `.season` / `.week` / `.tag`
and for which API is wired in.**

## Running things

No build, no lint, no test suite. Everything is `source()`d, and every path in the
code is relative (`./data/...`, `./config/...`), so **the working directory must be
the project root**. Open `DudesApp.Rproj` in RStudio or `setwd()` there first.

- Full weekly data refresh: edit the `# MASTER PARAMETERS ####` block near the bottom
  of `R/pipeline/data_pipeline.R` (`.season`, `.week`, `.tag`), then
  `source("R/pipeline/data_pipeline.R")`. It scrapes, calls the API, and upserts each
  `data/*_db.rds`. This is the legacy NFL-Fantasy path (`nfl_*` + `ffanalytics`).
- ESPN data refresh: `R/pipeline/data_pipeline_espn.R` — reads `.season`/`.week` from
  `config/config.yml`, pulls one ESPN snapshot + player pool via
  `R/api/espn_fantasy_client.R`, and upserts a single `dm` to `data/espn_db.rds`
  (12 `espn_*` tables). Independent of the NFL path; touches no `nfl_*`/`ffa_*` data.
- Generate simulations: `R/snippets/simulation_machine.R` — has its own
  `WEEK` / `SEASON` constants at the top. Writes `data/dudes_simulation_db.rds`.
- Lineup optimization: `R/analysis/team_optimizer.R`. ML scoring model:
  `R/analysis/projection_ml.R` (tidymodels).
- Ad-hoc analyses live in `R/snippets/` and are standalone — each reads the `.rds`
  databases and prints/plots. Not part of the pipeline.

Dependencies are installed ad hoc with `install.packages()` (see README list). Core:
`tidyverse`, `dm`, `glue`, `lubridate`, `ffanalytics`, `httr`/`httr2`, `jsonlite`,
`tidymodels`, `yaml`.

## Architecture

Data flows one direction, layer to layer:

```
R/api/  ->  R/pipeline/  ->  data/*_db.rds  ->  R/snippets/ + R/analysis/
scrape+API   orchestrate      dm databases      simulate / optimize / report
             + upsert
```

- **`R/api/`** — thin wrappers over external sources. `ffa_projection.R` wraps the
  `ffanalytics` package (multi-site projection scrape, incl. ESPN). `nfl_*.R`
  (`nfl_api.R` core + `nfl_league.R` / `nfl_players.R` / `nfl_game.R`) hit the NFL
  Fantasy API over `httr`. `espn_fantasy_client.R` is an `httr2` client for the ESPN
  Fantasy API (self-contained; `espn_snapshot()` fetches most of the league in one
  request), driven by `R/pipeline/data_pipeline_espn.R`; `example_espn_342842788.R`
  shows lower-level usage.
- **`R/pipeline/data_pipeline.R`** — the master script. Each section sources an API
  file, builds a `dm` (with PKs/FKs), then `updateDB()` merges it into the on-disk
  `.rds` via `dm_rows_upsert`. Raw API responses are cached under `data/temp/` so a
  run can be reprocessed without re-hitting the network. `*_playground.R` and
  `*_old.R` siblings are scratch/legacy — ignore unless asked.
- **`data/*_db.rds`** — each file is a single `dm` object (a set of related tables
  with keys), not a plain data frame. Load with `readRDS()`, access tables as
  `db$table_name`. `ffa_db`, `nfl_teams_db`, `nfl_players_db`, `nfl_stats_db`,
  `nfl_round_db`, `nfl_recap_db`, `dudes_simulation_db`, and `espn_db` (the ESPN
  pipeline's single 12-table dm). Gitignored. Older/wider copies live in
  `data/2023/` (2019–2023 snapshot) and `historic/` (2019–2025 merge, no keys) —
  archive only, no code reads them. **See [`DATA_CATALOG.md`](DATA_CATALOG.md)** for
  the per-table dictionary (columns, keys, meaning) and the season/week coverage
  matrix of every copy.
- **`R/transformation/`** — `simulation.R` computes historical projection errors
  (`real - projected` per source/week/player) and applies that error distribution to
  current projections. `missing_player_ids.R` bridges `ffa` ids and NFL/ESPN player
  ids (a recurring pain point — id mapping breaks every season).
- **`R/snippets/simulation_machine.R`** — for each player builds "seeds" (candidate
  point values) under ~15 strategies (raw source projections, projections+historical
  error, full history, current-season-only, kernel-density resamples of each), then
  resamples 1000 simulations per player and stores quantiles.

### `tag` semantics

`.tag` marks when in the week data was captured: `"preview"` (early-week projections),
`"final"` (after all games — also the only tag that pulls matchup recaps), `"season"`
(season-level snapshot, week 0). It is part of the primary key on time-sensitive
tables, so multiple tagged versions coexist in the same database.

### NFL -> ESPN migration

The league moved to ESPN. Two pipelines now coexist and share nothing:
`R/pipeline/data_pipeline.R` (legacy NFL Fantasy API + `ffanalytics`, still the only
source of `ffa_db` and the `nfl_*` databases the simulation/optimizer code reads) and
`R/pipeline/data_pipeline_espn.R` (ESPN, builds `espn_db`). Bridging ESPN player ids
to the `ffanalytics` ids the downstream code keys on is still undone — start from
`ffa_db$ffa_player_ids$espn_id` and the D/ST offset math in
`R_old/import/espn_scraper.R`.

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

- **`R_old/`** — the previous generation of this project (Yahoo + NFL era), kept for
  reference. Do not edit or wire into current work. `R_old/pipeline/pipeline_description.txt`
  has a prose walkthrough of the old flow.
- **`_bmad/`, `_bmad-output/`, `.claude/skills/`** — an installed BMAD "R Data
  Science" method plus a large set of R skills (tidymodels, shiny, torch, ggplot2,
  bioacoustics, …). Tooling, not project code.
