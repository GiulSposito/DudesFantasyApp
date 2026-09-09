# Web presentation layer - bundle orchestrator (contract sections 8, 37, 40).
#
#   build_web_bundle()  reads the persisted dm databases and writes a Parquet +
#   manifest.json bundle for the static Quarto cockpit.
#
# It NEVER re-simulates, re-optimizes ids, or re-bridges ESPN<->FFA. The only
# computation is optimize_lineup() (pure, no Monte Carlo draws) to flag the
# optimal starters in the rosters mart. Everything else is a read of one
# consistent decision run.
#
# Usage (working directory = project root):
#   source("R/web/build_web_bundle.R")
#   build_web_bundle()                                  # latest run -> web/data/
#   build_web_bundle(run_id = "2026-W01-preview-...")
#   build_web_bundle(privacy = "public", output_dir = "tests/fixtures/web_bundle")

library(tidyverse)
library(dm)

.web_root <- "R/web"
for (f in list.files(file.path(.web_root, "utils"), "\\.R$", full.names = TRUE)) source(f)
for (f in list.files(file.path(.web_root, "bundle"), "\\.R$", full.names = TRUE)) source(f)
source(file.path(.web_root, "validate_web_bundle.R"))

# --- inputs ------------------------------------------------------------------

load_sources <- function(result = NULL) {
  cfg <- yaml::read_yaml("./config/config.yml")
  list(
    decision_db   = if (!is.null(result)) result$decision_db else readRDS("./data/decision_db.rds"),
    espn_db       = readRDS("./data/espn_db.rds"),
    ffa_db        = readRDS("./data/ffa_db.rds"),
    analytical_db = readRDS("./data/analytical_db.rds"),
    my_team_id    = as.integer(cfg$myTeamEspnId)
  )
}

# 1-row list describing the resolved run.
resolve_run <- function(decision_db, run_id = NULL) {
  runs <- decision_db$simulation_runs
  row <- if (is.null(run_id)) {
    runs |> slice_max(created_at, n = 1, with_ties = FALSE)
  } else {
    hit <- runs |> filter(run_id == !!run_id)
    if (nrow(hit) == 0L) stop("resolve_run: run_id not found: ", run_id, call. = FALSE)
    hit
  }
  as.list(row)
}

reset_output <- function(output_dir) {
  unlink(output_dir, recursive = TRUE)
  for (d in c("", "dimensions", "current", "projections", "history")) {
    dir.create(file.path(output_dir, d), recursive = TRUE, showWarnings = FALSE)
  }
}

# --- orchestrator ----------------------------------------------------------

build_web_bundle <- function(run_id = NULL, result = NULL,
                             output_dir = "web/data",
                             privacy = c("private", "public"),
                             validate = TRUE) {
  privacy <- match.arg(privacy)

  src <- load_sources(result)
  run <- resolve_run(src$decision_db, run_id)
  message("build_web_bundle: run ", run$run_id, " -> ", output_dir,
          " (privacy=", privacy, ")")

  reset_output(output_dir)
  old_opt <- options(cockpit.output_dir = output_dir)
  on.exit(options(old_opt), add = TRUE)

  paths <- list()
  put <- function(name, df, rel) paths[[name]] <<- write_mart(df, rel)

  put("runs",         build_runs(src, run),               "runs.parquet")

  put("teams",        apply_privacy(build_dim_teams(src, run), "teams", privacy),
                      "dimensions/teams.parquet")
  put("players",      build_dim_players(src, run),         "dimensions/players.parquet")
  put("roster_slots", build_dim_roster_slots(src, run),    "dimensions/roster_slots.parquet")

  put("standings",              build_standings(src, run),              "current/standings.parquet")
  put("rosters",                build_rosters(src, run),                "current/rosters.parquet")
  put("forecasts",              build_forecasts(src, run),              "current/forecasts.parquet")
  put("matchups",               build_matchups(src, run),               "current/matchups.parquet")
  put("lineup_evaluations",     build_lineup_evaluations(src, run),     "current/lineup_evaluations.parquet")
  put("lineup_recommendations", build_lineup_recommendations(src, run), "current/lineup_recommendations.parquet")
  put("free_agents",            build_free_agents(src, run),            "current/free_agents.parquet")
  put("waiver_recommendations", build_waiver_recommendations(src, run), "current/waiver_recommendations.parquet")
  put("trade_recommendations",
      apply_privacy(build_trade_recommendations(src, run), "trade_recommendations", privacy),
      "current/trade_recommendations.parquet")
  put("data_health",            build_data_health(src, run),            "current/data_health.parquet")

  put("source_projections", build_source_projections(src, run), "projections/source_projections.parquet")
  put("source_accuracy",    build_source_accuracy(src, run),    "projections/source_accuracy.parquet")

  put("player_points",      build_player_points(src, run),      "history/player_points.parquet")
  put("consensus_history",  build_consensus_history(src, run),  "history/consensus_history.parquet")

  write_manifest(run, paths, privacy, output_dir)

  if (validate) validate_web_bundle(output_dir)
  invisible(output_dir)
}
