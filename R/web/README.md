# R/web — Web Presentation Layer

Builds the static data bundle the Quarto cockpit (`web/`) consumes. R stays the
only analytics layer: these scripts **read** the `dm` databases and **write**
Parquet + `manifest.json`. They never re-simulate, re-optimize, or re-resolve
ESPN↔FFA ids — that all lives in `R/decision/`.

## Dependency

One new package beyond the decision engine's stack:

```r
install.packages("nanoparquet")   # Posit, CRAN, zero-dependency Parquet writer
```

`arrow` is deliberately **not** used (large compiled install, no feature we need
at this data volume).

## Usage

```r
source("R/web/build_web_bundle.R")
build_web_bundle()                       # latest decision run -> web/data/
build_web_bundle(run_id = "2026-W01-preview-20260908T161947")
build_web_bundle(privacy = "public")     # strips owner names / ids
```

Reads `data/decision_db.rds`, `data/espn_db.rds`, `data/ffa_db.rds`,
`data/analytical_db.rds`. `current_players` and `free_agents` come from the
persisted `decision_db` tables (added by the decision pipeline), so the bundle is
a pure read of one consistent `run_id`.

## Layout

```
R/web/
  build_web_bundle.R      orchestrator: resolve_run(), load_sources(), write loop
  validate_web_bundle.R   build gate — stop() on any contract violation
  bundle/*.R              one build_*() per mart, returns a tibble, no file I/O
  utils/
    schema.R              id -> string, NA -> NULL, no list-columns, type coercion
    parquet.R             write_mart() -> nanoparquet::write_parquet
    privacy.R             apply_privacy(df, mart, mode)
```

Contract: `docs/app_web_data_contract.md`. Data dictionary: `DATA_CATALOG.md`.
