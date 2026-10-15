# Web bundle - history/player_points.parquet (contract section 25) +
# history/consensus_history.parquet (contract section 26) +
# history/player_weeks.parquet (contract section 26.4).
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

# history/player_weeks.parquet (contract section 26.4) - one row per player x
# closed week of the run's season (week < run week): the player's last forecast
# of that week made before his game locked (newest run where he was not yet
# realized - the bundle's per-week runs are post-game, P10 == P90 == actual),
# plus the actual points of the week's newest ESPN snapshot. Feeds the player
# drawer's realized x projected chart and the comparison map's Realizado lens.
build_player_weeks <- function(src, run) {
  runs <- src$decision_db$simulation_runs |>
    filter(season == run$season, week < run$week, created_at <= run$created_at) |>
    select(run_id, created_at)

  fc <- src$decision_db$player_forecasts |> inner_join(runs, by = "run_id")
  if (!"is_realized" %in% names(fc)) fc$is_realized <- FALSE
  fc <- fc |>
    filter(!coalesce(is_realized, FALSE)) |>
    mutate(ffa_id = as.integer(ffa_id)) |>
    slice_max(created_at, n = 1, with_ties = FALSE, by = c(week, ffa_id, pos))

  # ffa_id -> ESPN id as the forecast's own run bridged it (the forecast's
  # espn_id is the stale historical xref, see utils/bridge.R)
  bridge <- bind_rows(
    src$decision_db$current_players |>
      transmute(run_id, ffa_id = as.integer(ffa_id), run_espn_id = as.integer(espn_id)),
    src$decision_db$free_agents |>
      transmute(run_id, ffa_id = as.integer(ffa_id), run_espn_id = as.integer(player_id))
  ) |>
    filter(!is.na(ffa_id), !is.na(run_espn_id)) |>
    distinct(run_id, ffa_id, .keep_all = TRUE)

  # each snapshot carries the actual points of its own week only
  actual <- src$espn_db$espn_players_points |>
    filter(season == run$season, week < run$week, timestamp <= run$espn_timestamp,
           stat_source_id == 0L, stat_split_type_id == 1L) |>
    filter(timestamp == max(timestamp), .by = week) |>
    transmute(week = as.integer(week), espn_id = as.integer(player_id),
              actual_points = fantasy_points)

  fc |>
    left_join(bridge, by = c("run_id", "ffa_id")) |>
    mutate(espn_id = coalesce(run_espn_id, as.integer(espn_id)), week = as.integer(week)) |>
    left_join(actual, by = c("week", "espn_id")) |>
    transmute(
      season = as.integer(season), week, ffa_id, espn_id, position = pos,
      run_id, tag, projection, sim_mean, p10, p50, p90, actual_points
    ) |>
    arrange(week, ffa_id)
}

# history/matchup_history.parquet (contract section 26.1) - one row per run x
# matchup for the current run's season, up to and including the current run,
# so the frontend can chart how each matchup's win probability moved across the
# week's snapshots (preview -> preTNF -> posTNF -> ... -> final).
build_matchup_history <- function(src, run) {
  runs <- src$decision_db$simulation_runs |>
    filter(season == run$season, created_at <= run$created_at) |>
    select(run_id, created_at)

  src$decision_db$matchup_simulations |>
    inner_join(runs, by = "run_id") |>
    transmute(
      run_id, created_at,
      season = as.integer(season), week = as.integer(week), tag,
      matchup_id = as.integer(matchup_id),
      home_team_id = as.integer(home_team_id), away_team_id = as.integer(away_team_id),
      home_expected, away_expected,
      home_win_probability, away_win_probability
    ) |>
    arrange(created_at, matchup_id)
}
