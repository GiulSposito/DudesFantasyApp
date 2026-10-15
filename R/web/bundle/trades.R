# Web bundle - current/waiver_recommendations.parquet (contract section 21) +
# current/trade_recommendations.parquet (contract section 22).
#
# Native ranks are preserved verbatim - do NOT rerank. recommendation_rank is the
# week scope (delta_expected DESC for waivers, trade_score for trades);
# rank_future / rank_horizon the W1..W3 / W0..W3 scopes (docs/horizon_projections.md).
# A row can carry any subset of the three (NA = not ranked in that scope).

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

# horizon columns, absent from decision_dbs persisted before they existed
.HZ_FA_COLS    <- c("delta_future", "delta_horizon", "rank_future", "rank_horizon")
.HZ_TRADE_COLS <- c("my_delta_future", "my_delta_horizon", "their_delta_future",
                    "their_delta_horizon", "rank_future", "rank_horizon")
.with_cols <- function(df, cols) { df[setdiff(cols, names(df))] <- NA; df }

build_waiver_recommendations <- function(src, run) {
  nm <- .espn_name_lookup(src, run)

  src$decision_db$free_agent_recommendations |>
    filter(run_id == run$run_id) |>
    .with_cols(.HZ_FA_COLS) |>
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
      delta_future, delta_horizon,
      before_win_probability, after_win_probability, delta_win_probability,
      recommendation_rank, rank_future, rank_horizon
    )
}

build_trade_recommendations <- function(src, run) {
  nm <- .espn_name_lookup(src, run)
  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name)

  src$decision_db$trade_recommendations |>
    filter(run_id == run$run_id) |>
    .with_cols(.HZ_TRADE_COLS) |>
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
      my_delta_future, my_delta_horizon, their_delta_future, their_delta_horizon,
      my_before_win_probability, my_after_win_probability, my_delta_win_probability,
      fairness, trade_score, partner_is_my_opponent,
      recommendation_rank, rank_future, rank_horizon
    )
}
