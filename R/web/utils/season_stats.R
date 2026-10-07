# Season-level numbers per ESPN player_id for one run, from the run's ESPN
# snapshot (league scoring):
#
#   season_points  actual fantasy points so far this season (scoring period 0,
#                  actual, season-total split)
#   ros_points     ESPN rest-of-season projection (scoring period 0, projected,
#                  split 0) - checked against weekly projection x remaining team
#                  games through week 18: median ratio 0.99
#   games_played   the player's NFL team games before the run week
#   ros_games      the player's NFL team games from the run week through week 18
#
# ponytail: games are team games, so a game missed through injury counts as 0
# in points-per-game; ESPN's per-player games-played stat is not persisted.
run_season_stats <- function(src, run) {
  pts <- src$espn_db$espn_players_points |>
    filter(season == run$season, timestamp == run$espn_timestamp, week == 0L,
           stat_split_type_id == 0L, stat_season == run$season,
           stat_source_id %in% c(0L, 1L)) |>
    group_by(player_id) |>
    summarise(season_points = fantasy_points[stat_source_id == 0L][1],
              ros_points    = fantasy_points[stat_source_id == 1L][1],
              pro_team = first(pro_team), .groups = "drop")

  g <- src$espn_db$espn_pro_games |> filter(season == run$season)
  team_games <- bind_rows(transmute(g, week, pro_team = home_pro_team),
                          transmute(g, week, pro_team = away_pro_team)) |>
    group_by(pro_team) |>
    summarise(games_played = sum(week < run$week),
              ros_games    = sum(week >= run$week & week <= 18L), .groups = "drop")

  pts |>
    left_join(team_games, by = "pro_team") |>
    transmute(player_id, season_points, ros_points,
              games_played = as.integer(games_played), ros_games = as.integer(ros_games))
}
