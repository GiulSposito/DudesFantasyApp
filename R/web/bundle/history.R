# Web bundle - history/player_points.parquet (contract section 25) +
# history/consensus_history.parquet (contract section 26).
#
# Multi-season reference marts (no run_id). week == 0 rows are season
# aggregates, not a real NFL week - the frontend defaults to week > 0.
# Trimmed to the most recent `seasons` seasons to keep the browser bundle small.

library(tidyverse)

build_player_points <- function(src, run, seasons = 3L) {
  keep <- sort(unique(src$analytical_db$nfl_player_points$season), decreasing = TRUE)[seq_len(seasons)]
  xref <- src$analytical_db$player_ids |> distinct(nfl_id, ffa_id, espn_id)

  src$analytical_db$nfl_player_points |>
    filter(season %in% keep) |>
    left_join(xref, by = "nfl_id") |>
    transmute(
      nfl_id, ffa_id, espn_id,
      season = as.integer(season),
      week = as.integer(week),
      actual_points = points
    )
}

build_consensus_history <- function(src, run, seasons = 3L) {
  keep <- sort(unique(src$analytical_db$consensus_error_history$season), decreasing = TRUE)[seq_len(seasons)]

  src$analytical_db$consensus_error_history |>
    filter(season %in% keep) |>
    transmute(
      season = as.integer(season),
      week = as.integer(week),
      ffa_id, nfl_id, espn_id,
      position = pos,
      projection,
      n_sources = as.integer(n_sources),
      coverage_class,
      source_median, source_sd, source_mad, source_min, source_max, source_range,
      actual_points,
      residual, abs_residual, squared_residual,
      consensus_type
    )
}
