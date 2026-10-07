# Web bundle - history/league_ranks.parquet.
# 1 row = 1 fantasy team x 1 completed regular-season week. PK season + week +
# team_id. Feeds the three bump charts on Liga -> Rank:
#   standing_rank  league table after the week (win % then cumulative points -
#                  same order as current/standings.parquet; ESPN's H2H
#                  tiebreak is not reproduced)
#   points_rank    cumulative points scored
#   survival_rank  week score among teams still alive; the week's lowest score
#                  is eliminated from every later week (NA once eliminated)
#
# ponytail: regular season only - playoff weeks have byes and 2-week matchups.

library(tidyverse)

build_league_ranks <- function(src, run) {
  mu <- src$espn_db$espn_matchups |>
    filter(season == run$season, timestamp <= run$espn_timestamp)
  if (nrow(mu) == 0L) return(.empty_league_ranks())

  # the snapshot carries the whole-season schedule with results so far
  mu <- mu |>
    filter(timestamp == max(timestamp), playoff_tier_type == "NONE") |>
    group_by(matchup_period_id) |>
    filter(all(winner != "UNDECIDED")) |>
    ungroup()
  if (nrow(mu) == 0L) return(.empty_league_ranks())

  side <- function(us, won) {
    mu |> transmute(
      season = as.integer(season), week = as.integer(matchup_period_id),
      team_id = as.integer(.data[[paste0(us, "_team_id")]]),
      points  = .data[[paste0(us, "_points")]],
      result  = case_when(winner == won ~ "W", winner == "TIE" ~ "T", TRUE ~ "L")
    )
  }

  weekly <- bind_rows(side("home", "HOME"), side("away", "AWAY")) |>
    arrange(team_id, week) |>
    group_by(team_id) |>
    mutate(
      cum_points = cumsum(points),
      wins   = cumsum(result == "W"),
      losses = cumsum(result == "L"),
      ties   = cumsum(result == "T")
    ) |>
    group_by(week) |>
    mutate(
      win_pct = (wins + ties / 2) / (wins + losses + ties),
      # order(order(...)) = each row's position in that sort
      standing_rank = order(order(-win_pct, -cum_points, team_id)),
      points_rank   = order(order(-cum_points, team_id))
    ) |>
    ungroup()

  # survival: walk the weeks with the set of teams still alive
  alive <- unique(weekly$team_id)
  surv  <- list()
  for (w in sort(unique(weekly$week))) {
    wk <- weekly |>
      filter(week == w, team_id %in% alive) |>
      arrange(desc(points), desc(cum_points), desc(team_id)) |>
      mutate(survival_rank = row_number(),
             eliminated = length(alive) > 1L & survival_rank == n())
    surv[[length(surv) + 1L]] <- select(wk, week, team_id, survival_rank, eliminated)
    alive <- setdiff(alive, wk$team_id[wk$eliminated])
  }

  weekly |>
    left_join(bind_rows(surv), by = c("week", "team_id")) |>
    mutate(eliminated = coalesce(eliminated, FALSE)) |>
    transmute(
      season, week, team_id, points, result,
      cum_points, wins, losses, ties,
      standing_rank = as.integer(standing_rank),
      points_rank   = as.integer(points_rank),
      survival_rank = as.integer(survival_rank),
      eliminated
    ) |>
    arrange(week, standing_rank)
}

.empty_league_ranks <- function() {
  tibble(season = integer(), week = integer(), team_id = integer(),
         points = double(), result = character(), cum_points = double(),
         wins = integer(), losses = integer(), ties = integer(),
         standing_rank = integer(), points_rank = integer(),
         survival_rank = integer(), eliminated = logical())
}
