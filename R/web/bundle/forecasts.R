# Web bundle - current/forecasts.parquet (contract section 14).
# 1 row = 1 player forecast for the current run. PK run_id + ffa_id + position.

library(tidyverse)

build_forecasts <- function(src, run) {
  espn_nm <- src$espn_db$espn_players |>
    filter(season == run$season) |>
    transmute(espn_id = player_id, espn_name = player_name, espn_team = pro_team)

  ffa_nm <- src$ffa_db$ffa_players |>
    transmute(ffa_id = as.integer(id),
              ffa_name = str_squish(paste(first_name, last_name)),
              ffa_team = team) |>
    distinct(ffa_id, .keep_all = TRUE)

  fc <- src$decision_db$player_forecasts |> filter(run_id == run$run_id)
  if (!"is_realized" %in% names(fc)) fc$is_realized <- FALSE

  # actual points so far this season, as of the run's ESPN snapshot
  season_pts <- run_season_stats(src, run) |>
    transmute(espn_id = player_id, season_points)

  fc |>
    # the engine's espn_id is the stale historical xref; prefer this run's bridge
    left_join(run_espn_bridge(src, run), by = "ffa_id") |>
    mutate(espn_id = coalesce(run_espn_id, as.integer(espn_id))) |>
    left_join(espn_nm, by = "espn_id") |>
    left_join(ffa_nm, by = "ffa_id") |>
    left_join(season_pts, by = "espn_id") |>
    # rank within position by our simulated mean (1 = best projected)
    mutate(pos_rank = min_rank(desc(sim_mean)), pos_count = n(), .by = pos) |>
    # opponent keyed on the ESPN abbreviation only (FFA-only teams like SFO miss)
    mutate(pos_key = opp_pos_key(pos)) |>
    left_join(run_opponents(src, run), by = c("espn_team" = "nfl_team", "pos_key")) |>
    mutate(
      player_name = coalesce(espn_name, ffa_name),
      nfl_team    = coalesce(espn_team, ffa_team),
      historical_bias = sim_mean - projection
    ) |>
    transmute(
      run_id, season, week, tag,
      ffa_id, espn_id, player_name,
      position = pos, nfl_team,
      opp_team, opp_is_home, opp_rank, opp_avg,
      pos_rank, pos_count, season_points,
      projection,
      n_sources, coverage_class, source_sd, source_mad,
      sim_mean, sim_sd,
      p05, p10, p25, p50, p75, p90, p95,
      prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25, prob_gt_30,
      residual_pool_level, residual_pool_n,
      is_realized,
      historical_bias
    )
}

# current/horizon_projections.parquet (contract section 22.1). 1 row = 1 player x
# future target week (W1..W3) as seen from the run's ESPN snapshot. PK run_id +
# player_id + target_week. Pinned to run$espn_timestamp: the snapshots of later
# weeks also write these target weeks. W0 is the consensus forecast, not here.
# 0 rows for runs whose snapshot predates the horizon (docs/horizon_projections.md).
build_horizon_projections <- function(src, run) {
  byes <- src$espn_db$espn_pro_teams |>
    filter(season == run$season) |>
    select(pro_team, bye_week)

  src$espn_db$espn_players_points |>
    filter(season == run$season, timestamp == run$espn_timestamp, week > run$week,
           stat_source_id == 1L, stat_split_type_id == 1L) |>
    left_join(byes, by = "pro_team") |>
    transmute(
      run_id      = run$run_id,
      player_id,
      target_week = as.integer(week),
      horizon     = as.integer(week) - as.integer(run$week),
      projection  = coalesce(fantasy_points, 0),
      is_bye      = coalesce(bye_week == week, FALSE)
    )
}
