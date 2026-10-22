# Web bundle - history/player_points.parquet (contract section 25) +
# history/consensus_history.parquet (contract section 26) +
# history/player_weeks.parquet (contract section 26.4) +
# history/matchup_backtest.parquet (contract section 26.5).
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

# history/matchup_backtest.parquet (contract section 26.5) - one row per
# matchup of each closed week (one with an ESPN "final" snapshot, see
# .final_rosters() in best_lineups.R): did the model call the winner? The
# week's newest run made before its first kickoff (preTNF in practice - tags
# are free text, the clock is not) projects the starters that actually played
# (the final lineup); the higher projected total is the predicted winner.
# Weeks with no pre-kickoff run are left out; a TIE has correct = NA.
build_matchup_backtest <- function(src, run) {
  finals <- .final_rosters(src, run)
  if (nrow(finals) == 0L) return(.empty_matchup_backtest())

  kickoff <- src$espn_db$espn_pro_games |>
    filter(season == run$season) |>
    summarise(kickoff = min(game_date), .by = week)

  season_runs <- src$decision_db$simulation_runs |>
    filter(season == run$season, created_at <= run$created_at)

  pre <- season_runs |>
    filter(week %in% finals$week) |>
    inner_join(kickoff, by = "week") |>
    filter(pmax(espn_timestamp, ffa_timestamp) < kickoff) |>
    slice_max(created_at, n = 1, with_ties = FALSE, by = week) |>
    select(week, run_id, tag)

  # ESPN id -> ffa_id as any run of the season bridged it: the mapping is
  # stable, and the pre-kickoff run alone misses players picked up later
  bridge <- bind_rows(
    src$decision_db$current_players |>
      transmute(run_id, espn_id = as.integer(espn_id), ffa_id = as.integer(ffa_id)),
    src$decision_db$free_agents |>
      transmute(run_id, espn_id = as.integer(player_id), ffa_id = as.integer(ffa_id))
  ) |>
    filter(run_id %in% season_runs$run_id, !is.na(espn_id), !is.na(ffa_id)) |>
    distinct(espn_id, .keep_all = TRUE) |>
    select(espn_id, ffa_id)

  proj <- src$decision_db$player_forecasts |>
    inner_join(select(pre, run_id), by = "run_id") |>
    transmute(week = as.integer(week), ffa_id = as.integer(ffa_id), sim_mean) |>
    distinct(week, ffa_id, .keep_all = TRUE)

  teams <- finals |>
    filter(is_starter) |>
    transmute(week = as.integer(week), team_id, espn_id = as.integer(player_id)) |>
    left_join(bridge, by = "espn_id") |>
    left_join(proj, by = c("week", "ffa_id")) |>
    summarise(projected = sum(sim_mean, na.rm = TRUE),
              n_missing = sum(is.na(sim_mean)), .by = c(week, team_id))
  side <- function(prefix) {
    rename_with(teams, \(x) paste0(prefix, x), c(team_id, projected, n_missing))
  }

  src$espn_db$espn_matchups |>
    filter(season == run$season) |>
    inner_join(distinct(finals, week, timestamp), by = c("week", "timestamp")) |>
    filter(matchup_period_id == week) |>
    select(season, week, matchup_id, home_team_id, away_team_id,
           home_points, away_points, winner) |>
    inner_join(pre, by = "week") |>
    left_join(side("home_"), by = c("week", "home_team_id")) |>
    left_join(side("away_"), by = c("week", "away_team_id")) |>
    transmute(
      season = as.integer(season), week = as.integer(week),
      matchup_id = as.integer(matchup_id), run_id, tag,
      home_team_id = as.integer(home_team_id), away_team_id = as.integer(away_team_id),
      home_projected, away_projected, home_points, away_points,
      predicted_winner = case_when(home_projected > away_projected ~ "HOME",
                                   home_projected < away_projected ~ "AWAY"),
      winner,
      correct = if_else(winner %in% c("HOME", "AWAY"), predicted_winner == winner, NA),
      home_n_missing, away_n_missing
    ) |>
    arrange(week, matchup_id)
}

.empty_matchup_backtest <- function() {
  tibble(season = integer(), week = integer(), matchup_id = integer(),
         run_id = character(), tag = character(),
         home_team_id = integer(), away_team_id = integer(),
         home_projected = double(), away_projected = double(),
         home_points = double(), away_points = double(),
         predicted_winner = character(), winner = character(), correct = logical(),
         home_n_missing = integer(), away_n_missing = integer())
}
