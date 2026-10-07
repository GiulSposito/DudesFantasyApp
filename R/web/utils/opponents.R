# NFL opponent of the run's week + the ESPN "OPRK" of that defense against the
# player's position, one row per ESPN team abbreviation x position.
#
#   opp_team    ESPN abbreviation of the week's opponent, "BYE", or NA
#   opp_is_home TRUE when the player's team hosts the game
#   opp_rank    1..32 within position; 1 = defense allows the fewest fantasy
#               points (toughest matchup), 32 = the most (easiest)
#   opp_avg     fantasy points that defense allowed per game to the position
#
# Ratings are the newest espn_pos_vs_opponent capture at or before the run's
# ESPN snapshot; runs older than that table get NA rank / avg.
run_opponents <- function(src, run) {
  games <- src$espn_db$espn_pro_games |>
    filter(season == run$season, week == run$week)
  sched <- bind_rows(
    games |> transmute(nfl_team = home_pro_team, opp_team = away_pro_team, opp_is_home = TRUE),
    games |> transmute(nfl_team = away_pro_team, opp_team = home_pro_team, opp_is_home = FALSE)
  )
  bye <- src$espn_db$espn_pro_teams |>
    filter(season == run$season, pro_team_id != 0L, !pro_team %in% sched$nfl_team) |>
    transmute(nfl_team = pro_team, opp_team = "BYE", opp_is_home = NA)

  ratings <- if ("espn_pos_vs_opponent" %in% names(src$espn_db)) {
    src$espn_db$espn_pos_vs_opponent |>
      filter(season == run$season, timestamp <= run$espn_timestamp) |>
      slice_max(timestamp, n = 1, with_ties = TRUE) |>
      transmute(pos_key = position, opp_team = pro_team,
                opp_rank = as.integer(rank), opp_avg = as.double(average))
  } else {
    tibble(pos_key = character(), opp_team = character(),
           opp_rank = integer(), opp_avg = double())
  }

  bind_rows(sched, bye) |>
    cross_join(tibble(pos_key = c("QB", "RB", "WR", "TE", "K", "D/ST"))) |>
    left_join(ratings, by = c("pos_key", "opp_team"))
}

# mart position ("DST" in forecasts, "D/ST" in ESPN marts) -> run_opponents key
opp_pos_key <- function(position) if_else(position == "DST", "D/ST", position)
