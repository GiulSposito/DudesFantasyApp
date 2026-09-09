# Web bundle - current/standings.parquet (contract section 15).
# 1 row = 1 fantasy team at the ESPN snapshot tied to the current run.
# PK run_id + team_id.

library(tidyverse)

build_standings <- function(src, run) {
  st <- src$espn_db$espn_team_standings |> filter(season == run$season)

  sel <- st |> filter(week == run$week, tag == run$tag)
  if (nrow(sel) == 0L) {
    # preseason-only standings and a later run week: fall back to latest snapshot
    sel <- st |> filter(timestamp == max(timestamp))
    message("build_standings: no week/tag standings for the run; ",
            "using latest season snapshot (", format(max(st$timestamp)), ")")
  } else {
    ts_hit <- sel |> filter(timestamp == run$espn_timestamp)
    sel <- if (nrow(ts_hit) > 0L) ts_hit else sel |> filter(timestamp == max(timestamp))
  }

  teams <- src$espn_db$espn_teams |>
    filter(season == run$season) |> select(team_id, team_name)

  sel |>
    left_join(teams, by = "team_id") |>
    mutate(
      run_id = run$run_id,
      streak = paste0(substr(streak_type, 1, 1), streak_length)
    ) |>
    arrange(desc(wins), desc(points_for)) |>
    mutate(rank = row_number()) |>
    transmute(
      run_id, season, week, tag,
      team_id, team_name,
      rank, current_projected_rank,
      wins, losses, ties, win_pct,
      points_for, points_against,
      streak, streak_type, streak_length,
      acquisitions, drops, trades
    )
}
