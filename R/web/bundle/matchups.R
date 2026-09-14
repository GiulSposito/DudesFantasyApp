# Web bundle - current/matchups.parquet (contract section 17).
# 1 row = 1 league matchup for the current run. PK run_id + matchup_id.

library(tidyverse)

build_matchups <- function(src, run) {
  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name, logo_url)

  # starters locked so far this week (games kicked off), for the scoreboard's
  # game-progress bar - same is_locked the decision engine folds into sim_mean.
  progress <- src$decision_db$current_players |>
    filter(run_id == run$run_id, is_starter) |>
    group_by(team_id) |>
    summarise(locked_starters = sum(is_locked, na.rm = TRUE),
              total_starters = n(), .groups = "drop")

  src$decision_db$matchup_simulations |>
    filter(run_id == run$run_id) |>
    left_join(rename(teams, home_team_id = team_id, home_team_name = team_name,
                     home_logo_url = logo_url),
              by = "home_team_id") |>
    left_join(rename(teams, away_team_id = team_id, away_team_name = team_name,
                     away_logo_url = logo_url),
              by = "away_team_id") |>
    left_join(rename(progress, home_team_id = team_id,
                     home_locked_starters = locked_starters, home_total_starters = total_starters),
              by = "home_team_id") |>
    left_join(rename(progress, away_team_id = team_id,
                     away_locked_starters = locked_starters, away_total_starters = total_starters),
              by = "away_team_id") |>
    mutate(is_my_matchup = home_team_id == src$my_team_id |
             away_team_id == src$my_team_id) |>
    transmute(
      run_id, season, week, tag,
      matchup_id,
      home_team_id, home_team_name, home_logo_url,
      away_team_id, away_team_name, away_logo_url,
      home_expected, away_expected,
      home_p10, home_p50, home_p90,
      away_p10, away_p50, away_p90,
      home_win_probability, away_win_probability, tie_probability,
      home_locked_starters, home_total_starters,
      away_locked_starters, away_total_starters,
      n_sim, is_my_matchup
    )
}
