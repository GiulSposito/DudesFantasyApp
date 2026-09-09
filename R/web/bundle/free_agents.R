# Web bundle - current/free_agents.parquet (contract section 20).
# 1 row = 1 available player for the current run. PK run_id + player_id.
# Reproduces the decision engine's free-agent universe verbatim (persisted
# decision_db$free_agents) - no re-derivation.

library(tidyverse)

build_free_agents <- function(src, run) {
  fa <- src$decision_db$free_agents |> filter(run_id == run$run_id)
  if (is.list(fa$eligible_slot_ids)) {
    fa <- fa |> mutate(eligible_slot_ids = map_chr(eligible_slot_ids,
                                                   ~ paste(.x, collapse = ",")))
  }

  fc <- src$decision_db$player_forecasts |>
    filter(run_id == run$run_id) |>
    select(ffa_id, pos, sim_sd, p25, p75,
           prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25, n_sources)

  nfl <- src$espn_db$espn_players |>
    filter(season == run$season) |>
    transmute(player_id, nfl_team = pro_team)

  fa |>
    left_join(fc, by = c("ffa_id", "pos")) |>
    left_join(nfl, by = "player_id") |>
    transmute(
      run_id,
      player_id, ffa_id,
      player_name, position, nfl_team,
      injury_status,
      projection, sim_mean, sim_sd,
      p10, p25, p50, p75, p90,
      prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25,
      n_sources, coverage_class,
      percent_owned = NA_real_,
      percent_started = NA_real_
    )
}
