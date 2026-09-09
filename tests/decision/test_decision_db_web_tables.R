# tests/decision/test_decision_db_web_tables.R - M0.5: current_players +
# free_agents persisted into the decision dm for the web bundle layer.
# Skips (does not fail) when the databases are absent.

suppressMessages({library(tidyverse); library(dm)})

need <- c("./data/ffa_db.rds", "./data/espn_db.rds", "./data/analytical_db.rds")
if (!all(file.exists(need))) {
  cat("SKIP test_decision_db_web_tables.R (missing data/*.rds)\n")
} else {
  source("./R/decision/decision_pipeline.R")

  res <- suppressWarnings(
    run_decision_pipeline(2026, 1, "preview", n_sim = 2000, persist = FALSE)
  )
  ddb <- res$decision_db

  stopifnot(
    inherits(ddb, "dm"),
    all(c("current_players", "free_agents") %in% names(ddb)),
    length(ddb) == 9,
    "run_id" %in% names(ddb$current_players),
    "run_id" %in% names(ddb$free_agents),
    all(ddb$current_players$run_id == res$run_id),
    all(ddb$free_agents$run_id == res$run_id),
    !anyDuplicated(ddb$current_players[c("run_id", "team_id", "espn_id")]),
    !anyDuplicated(ddb$free_agents[c("run_id", "player_id")]),
    nrow(ddb$current_players) == 210
  )

  cat("PASS test_decision_db_web_tables.R\n")
}
