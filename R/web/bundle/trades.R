# Web bundle - current/waiver_recommendations.parquet (contract section 21) +
# current/trade_recommendations.parquet (contract section 22).
#
# Native recommendation_rank is preserved verbatim (delta_expected DESC for
# waivers, trade_score for trades) - do NOT rerank.

library(tidyverse)

# espn_id -> player_name, covering rostered players, free agents and the full
# ESPN player table (D/ST carry negative ids that only the first two sources have)
.espn_name_lookup <- function(src, run) {
  bind_rows(
    src$decision_db$current_players |> filter(run_id == run$run_id) |>
      transmute(pid = espn_id, player_name),
    src$decision_db$free_agents |> filter(run_id == run$run_id) |>
      transmute(pid = player_id, player_name),
    src$espn_db$espn_players |> filter(season == run$season) |>
      transmute(pid = player_id, player_name)
  ) |>
    filter(!is.na(pid), !is.na(player_name)) |>
    distinct(pid, .keep_all = TRUE)
}

build_waiver_recommendations <- function(src, run) {
  nm <- .espn_name_lookup(src, run)

  src$decision_db$free_agent_recommendations |>
    filter(run_id == run$run_id) |>
    left_join(rename(nm, drop_player_id = pid, drop_player_name = player_name),
              by = "drop_player_id") |>
    left_join(rename(nm, add_player_id = pid, add_player_name = player_name),
              by = "add_player_id") |>
    transmute(
      run_id, season, week, tag,
      team_id,
      drop_player_id, drop_ffa_id, drop_player_name, drop_position,
      add_player_id, add_ffa_id, add_player_name, add_position,
      before_expected, after_expected, delta_expected,
      before_win_probability, after_win_probability, delta_win_probability,
      recommendation_rank
    )
}

build_trade_recommendations <- function(src, run) {
  nm <- .espn_name_lookup(src, run)
  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name)

  src$decision_db$trade_recommendations |>
    filter(run_id == run$run_id) |>
    left_join(rename(teams, my_team_id = team_id, my_team_name = team_name),
              by = "my_team_id") |>
    left_join(rename(teams, other_team_id = team_id, other_team_name = team_name),
              by = "other_team_id") |>
    left_join(rename(nm, give_player_id = pid, give_player_name = player_name),
              by = "give_player_id") |>
    left_join(rename(nm, receive_player_id = pid, receive_player_name = player_name),
              by = "receive_player_id") |>
    transmute(
      run_id, season, week, tag,
      my_team_id, my_team_name,
      other_team_id, other_team_name,
      give_player_id, give_ffa_id, give_player_name, give_position,
      receive_player_id, receive_ffa_id, receive_player_name, receive_position,
      my_before_expected, my_after_expected, my_delta_expected,
      their_before_expected, their_after_expected, their_delta_expected,
      my_before_win_probability, my_after_win_probability, my_delta_win_probability,
      fairness, trade_score, partner_is_my_opponent,
      recommendation_rank
    )
}
