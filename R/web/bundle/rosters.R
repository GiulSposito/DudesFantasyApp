# Web bundle - current/rosters.parquet (contract section 16).
# 1 row = 1 rostered player for 1 team for the current run.
# PK run_id + team_id + player_id.
#
# is_optimal_starter / optimal_slot come from optimize_lineup() (pure, no draws)
# run per team. IDs are NOT re-bridged - current_players already carries ffa_id
# and bridge_method from the decision engine.

library(tidyverse)

if (!exists("optimize_lineup")) source("./R/decision/lineup_optimizer.R")

build_rosters <- function(src, run) {
  cp <- src$decision_db$current_players |> filter(run_id == run$run_id)
  if (is.list(cp$eligible_slot_ids)) {
    cp <- cp |> mutate(eligible_slot_ids = map_chr(eligible_slot_ids,
                                                   ~ paste(.x, collapse = ",")))
  }

  fc <- src$decision_db$player_forecasts |>
    filter(run_id == run$run_id) |>
    select(ffa_id, pos, p25, p75,
           prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25)

  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name)

  base <- cp |>
    left_join(fc, by = c("ffa_id", "pos")) |>
    left_join(teams, by = "team_id")

  slots <- src$espn_db$espn_roster_slots |> filter(season == run$season)

  opt <- base |>
    filter(!is.na(ffa_id), !is.na(sim_mean), !is_ir, !(injury_status %in% c("OUT"))) |>
    select(team_id, ffa_id, pos, sim_mean, eligible_slot_ids, player_name, espn_id) |>
    group_by(team_id) |>
    group_modify(~ {
      res <- optimize_lineup(.x, slots)
      tibble(espn_id = res$espn_id, optimal_slot = res$lineup_slot)
    }) |>
    ungroup()

  base |>
    left_join(opt, by = c("team_id", "espn_id")) |>
    mutate(
      is_optimal_starter = !is.na(optimal_slot),
      player_id = espn_id
    ) |>
    transmute(
      run_id, season, week, tag,
      team_id, team_name,
      player_id, ffa_id, player_name, position, nfl_team,
      lineup_slot_id, lineup_slot,
      is_starter, is_bench, is_ir,
      injury_status, injured, active,
      projection, sim_mean, sim_sd,
      p10, p25, p50, p75, p90,
      prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25,
      n_sources, coverage_class,
      is_optimal_starter, optimal_slot,
      bridge_method
    )
}
