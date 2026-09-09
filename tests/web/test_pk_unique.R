# tests/web/test_pk_unique.R - logical PK uniqueness for every mart
# (contract section 32.4).

suppressMessages({library(nanoparquet)})

FIX <- "./tests/fixtures/web_bundle"
rp  <- function(x) as.data.frame(read_parquet(file.path(FIX, x)))

pk <- list(
  "runs.parquet"                           = "run_id",
  "dimensions/teams.parquet"               = c("season", "team_id"),
  "dimensions/players.parquet"             = c("season", "player_id"),
  "dimensions/roster_slots.parquet"        = c("season", "lineup_slot_id"),
  "current/standings.parquet"              = c("run_id", "team_id"),
  "current/rosters.parquet"                = c("run_id", "team_id", "player_id"),
  "current/forecasts.parquet"              = c("run_id", "ffa_id", "position"),
  "current/matchups.parquet"               = c("run_id", "matchup_id"),
  "current/lineup_evaluations.parquet"     = c("run_id", "team_id"),
  "current/lineup_recommendations.parquet" = c("run_id", "team_id", "player_out_id"),
  "current/free_agents.parquet"            = c("run_id", "player_id"),
  "current/waiver_recommendations.parquet" = c("run_id", "team_id", "drop_player_id", "add_player_id"),
  "current/trade_recommendations.parquet"  = c("run_id", "other_team_id", "give_player_id", "receive_player_id"),
  "current/data_health.parquet"            = "run_id",
  "projections/source_projections.parquet" = c("run_id", "ffa_id", "position", "data_src"),
  "projections/source_accuracy.parquet"    = c("season", "data_src", "position")
)

for (rel in names(pk)) {
  d <- rp(rel)
  stopifnot(all(pk[[rel]] %in% names(d)))
  if (anyDuplicated(d[pk[[rel]]])) {
    stop(rel, ": duplicate PK on (", paste(pk[[rel]], collapse = ", "), ")")
  }
}

cat("PASS test_pk_unique.R\n")
