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

  fc |>
    left_join(espn_nm, by = "espn_id") |>
    left_join(ffa_nm, by = "ffa_id") |>
    mutate(
      player_name = coalesce(espn_name, ffa_name),
      nfl_team    = coalesce(espn_team, ffa_team),
      historical_bias = sim_mean - projection
    ) |>
    transmute(
      run_id, season, week, tag,
      ffa_id, espn_id, player_name,
      position = pos, nfl_team,
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
