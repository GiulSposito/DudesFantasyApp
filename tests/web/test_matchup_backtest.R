# tests/web/test_matchup_backtest.R - build_matchup_backtest(): each closed
# week's newest pre-kickoff run projects the starters of the final lineup; the
# higher projected total is the predicted winner, scored against ESPN's result.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/bundle/best_lineups.R")
source("./R/web/bundle/history.R")

ts <- function(x) as.POSIXct(x, tz = "UTC")
T5 <- ts("2026-10-13 09:00")   # week 5 final snapshot

starter <- function(team_id, player_id, is_starter = TRUE) tibble(team_id, player_id, is_starter)
rosters <- bind_rows(
  starter(1L, 101L), starter(1L, 102L), starter(1L, 103L, FALSE),  # 103 benched
  starter(2L, 201L), starter(2L, 202L),                             # 202: no forecast
  starter(3L, 301L), starter(4L, 401L),
  starter(5L, 501L), starter(6L, 601L)
) |> mutate(season = 2026L, week = 5L, tag = "final", timestamp = T5)
rosters <- bind_rows(rosters,                                        # week 6: open
  rosters |> mutate(week = 6L, tag = "preMNF", timestamp = ts("2026-10-19 09:00")))

mu <- function(matchup_id, period, home, away, winner) tibble(
  season = 2026L, week = 5L, tag = "final", timestamp = T5, matchup_id,
  matchup_period_id = period, home_team_id = home, away_team_id = away,
  home_points = 100, away_points = 90, winner
)
fc <- function(run_id, week, ffa_id, sim_mean) tibble(run_id, week, ffa_id, sim_mean)

src <- list(
  espn_db = list(
    espn_rosters = rosters,
    espn_pro_games = tibble(season = 2026L, week = c(5L, 5L, 6L),
                            game_date = ts(c("2026-10-09 00:15", "2026-10-12 17:00", "2026-10-16 00:15"))),
    espn_matchups = bind_rows(
      mu(1L, 5L, 1L, 2L, "HOME"),
      mu(2L, 5L, 3L, 4L, "AWAY"),
      mu(3L, 5L, 5L, 6L, "TIE"),
      mu(4L, 6L, 1L, 3L, "UNDECIDED")                               # next week's schedule
    )
  ),
  decision_db = list(
    simulation_runs = tibble(
      run_id = c("W5old", "W5pre", "W5post", "W6pre"), season = 2026L, week = c(5L, 5L, 5L, 6L),
      tag = run_id,
      created_at     = ts(c("2026-10-06 10:00", "2026-10-08 10:05", "2026-10-12 10:05", "2026-10-14 10:05")),
      espn_timestamp = ts(c("2026-10-06 09:00", "2026-10-08 10:00", "2026-10-12 10:00", "2026-10-14 10:00")),
      ffa_timestamp  = ts(c("2026-10-06 09:00", "2026-10-08 10:00", "2026-10-08 10:00", "2026-10-14 10:00"))
    ),
    player_forecasts = bind_rows(
      fc("W5pre", 5L, c(11L, 12L, 13L, 21L, 31L, 41L, 51L, 61L), c(10, 10, 100, 15, 20, 10, 10, 12)),
      fc("W5old", 5L, 41L, 50),                  # older pre-kickoff run: superseded
      fc("W5post", 5L, 31L, 5)                   # post-kickoff: would flip matchup 2
    ),
    # the bridge comes from any run of the season, not only the pre-kickoff one
    current_players = tibble(run_id = c(rep("W5post", 5), "W5pre", "W5pre"),
                             espn_id = c(101L, 102L, 103L, 201L, 202L, 301L, 401L),
                             ffa_id  = c(11L, 12L, 13L, 21L, 22L, 31L, 41L)),
    free_agents = tibble(run_id = "W5pre", player_id = c(501L, 601L), ffa_id = c(51L, 61L))
  )
)
run <- list(run_id = "W6pre", season = 2026L, week = 6L,
            created_at = ts("2026-10-14 10:05"), espn_timestamp = ts("2026-10-14 10:00"))

bt <- build_matchup_backtest(src, run)
stopifnot(
  nrow(bt) == 3L, all(bt$week == 5L),                     # open week 6 excluded
  all(bt$run_id == "W5pre"),                               # newest run before kickoff
  identical(bt$matchup_id, 1:3),
  identical(bt$home_projected, c(20, 20, 10)),             # bench player not counted
  identical(bt$away_projected, c(15, 10, 12)),
  identical(bt$away_n_missing, c(1L, 0L, 0L)),             # unprojected starter counts 0
  identical(bt$predicted_winner, c("HOME", "HOME", "AWAY")),
  identical(bt$correct, c(TRUE, FALSE, NA))                # hit, miss, tie
)

# no closed week yet -> typed empty mart
src$espn_db$espn_rosters <- filter(rosters, tag != "final")
stopifnot(nrow(build_matchup_backtest(src, run)) == 0L)

cat("PASS test_matchup_backtest.R\n")
