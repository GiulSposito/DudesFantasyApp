# Web bundle - current/lineup_evaluations.parquet (contract section 18) +
# current/lineup_recommendations.parquet (contract section 19).

library(tidyverse)

build_lineup_evaluations <- function(src, run) {
  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name)

  src$decision_db$lineup_evaluations |>
    filter(run_id == run$run_id) |>
    left_join(teams, by = "team_id") |>
    left_join(rename(teams, opponent_team_id = team_id,
                     opponent_team_name = team_name), by = "opponent_team_id") |>
    mutate(
      delta_expected = optimal_expected - current_expected,
      delta_win_probability = optimal_win_probability - current_win_probability
    ) |>
    transmute(
      run_id, season, week, tag,
      team_id, team_name, opponent_team_id, opponent_team_name,
      current_expected, current_p10, current_p50, current_p90,
      current_win_probability,
      optimal_expected, optimal_p10, optimal_p50, optimal_p90,
      optimal_win_probability,
      bench_value, n_substitutions,
      delta_expected, delta_win_probability
    )
}

build_lineup_recommendations <- function(src, run) {
  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name)

  # position lookup for out/in players (ESPN ids) from the run's roster pool
  pos <- src$decision_db$current_players |>
    filter(run_id == run$run_id) |>
    distinct(espn_id, position)

  src$decision_db$lineup_recommendations |>
    filter(run_id == run$run_id) |>
    rename(player_out_id = player_out, player_in_id = player_in) |>
    left_join(teams, by = "team_id") |>
    left_join(rename(pos, player_out_id = espn_id, player_out_position = position),
              by = "player_out_id") |>
    left_join(rename(pos, player_in_id = espn_id, player_in_position = position),
              by = "player_in_id") |>
    transmute(
      run_id, season, week, tag,
      team_id, team_name,
      player_out_id, player_out_name, player_out_position,
      player_in_id, player_in_name, player_in_position,
      slot,
      current_expected, optimized_expected, delta_expected,
      current_win_probability, optimized_win_probability, delta_win_probability,
      recommendation_rank
    )
}
