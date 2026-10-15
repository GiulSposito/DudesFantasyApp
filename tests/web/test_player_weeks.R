# tests/web/test_player_weeks.R - build_player_weeks(): each closed week's last
# pre-lock forecast + the week's actual points from its newest ESPN snapshot.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/bundle/history.R")

ts <- function(x) as.POSIXct(x, tz = "UTC")
runs <- tibble(
  run_id     = c("W5pre", "W5post", "W6pre"),
  season     = 2026L,
  week       = c(5L, 5L, 6L),
  created_at = ts(c("2026-10-07 10:00", "2026-10-13 10:00", "2026-10-14 10:00"))
)
fc <- function(run_id, week, ffa_id, sim_mean, realized, espn_id = 1L) tibble(
  run_id, season = 2026L, week, tag = run_id, ffa_id, espn_id, pos = "WR",
  projection = sim_mean, sim_mean, p10 = sim_mean - 5, p50 = sim_mean, p90 = sim_mean + 5,
  is_realized = realized
)
src <- list(
  decision_db = list(
    simulation_runs = runs,
    player_forecasts = bind_rows(
      fc("W5pre",  5L, 10L, 12, FALSE, espn_id = 999L),   # stale xref id
      fc("W5post", 5L, 10L, 20, TRUE,  espn_id = 999L),   # realized: never the projection
      fc("W5pre",  5L, 11L, 8,  FALSE, espn_id = 2L),
      fc("W5post", 5L, 11L, 9,  FALSE, espn_id = 2L),     # Monday game: newest pre-lock
      fc("W6pre",  6L, 10L, 14, FALSE)                    # the run's own week: excluded
    ),
    current_players = tibble(run_id = "W5pre", ffa_id = 10L, espn_id = 7L),
    free_agents = tibble(run_id = character(), ffa_id = integer(), player_id = integer())
  ),
  espn_db = list(espn_players_points = tibble(
    season = 2026L, week = 5L,
    timestamp = ts(c("2026-10-10 10:00", "2026-10-13 09:00", "2026-10-13 09:00")),
    player_id = c(7L, 7L, 5L), stat_source_id = 0L, stat_split_type_id = 1L,
    fantasy_points = c(3, 21.5, 4)
  ))
)
run <- list(run_id = "W6pre", season = 2026L, week = 6L,
            created_at = ts("2026-10-14 10:00"), espn_timestamp = ts("2026-10-14 09:00"))

pw <- build_player_weeks(src, run)
stopifnot(
  nrow(pw) == 2L, all(pw$week == 5L),                   # week 6 excluded
  identical(pw$ffa_id, c(10L, 11L)),
  identical(pw$sim_mean, c(12, 9)),                      # pre-lock wins; newest pre-lock wins
  identical(pw$espn_id, c(7L, 2L)),                      # run bridge beats the stale xref
  identical(pw$actual_points[1], 21.5),                  # newest snapshot of the week
  is.na(pw$actual_points[2])                             # no stat row -> NA
)

cat("PASS test_player_weeks.R\n")
