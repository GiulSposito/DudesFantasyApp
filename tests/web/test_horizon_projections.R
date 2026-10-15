# tests/web/test_horizon_projections.R - build_horizon_projections(): ESPN weekly
# projections for the run's future weeks, pinned to the run's ESPN snapshot.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/bundle/forecasts.R")

t5 <- as.POSIXct("2026-10-08 10:00", tz = "UTC")   # W5 snapshot: wrote weeks 6..8
t6 <- as.POSIXct("2026-10-15 10:00", tz = "UTC")   # W6 snapshot: wrote weeks 7..9
pts <- function(ts, weeks, val, team = "KC", src = 1L, split = 1L) tibble(
  season = 2026L, week = weeks, timestamp = ts, player_id = 7L, pro_team = team,
  stat_source_id = src, stat_split_type_id = split, fantasy_points = val
)
src <- list(espn_db = list(
  espn_pro_teams = tibble(season = 2026L, pro_team = "KC", bye_week = 8L),
  espn_players_points = bind_rows(
    pts(t5, 6:8, 1),
    pts(t6, 6:9, c(99, 12, 0, NA)),        # week 6 = the run's own week, not horizon
    pts(t6, 7L, 50, split = 0L),            # not the weekly projection
    pts(t6, 8L, 60, src = 0L)               # not a projection
  )
))
run <- list(run_id = "R6", season = 2026L, week = 6L, espn_timestamp = t6)
h <- build_horizon_projections(src, run)
stopifnot(
  identical(names(h), c("run_id", "player_id", "target_week", "horizon",
                        "projection", "is_bye")),
  identical(h$target_week, 7:9),
  identical(h$horizon, 1:3),
  identical(h$projection, c(12, 0, 0)),                # t6 only; NA -> 0
  identical(h$is_bye, c(FALSE, TRUE, FALSE)),          # KC bye in week 8
  all(h$run_id == "R6")
)
# a run whose snapshot predates the horizon -> 0 rows
stopifnot(nrow(build_horizon_projections(src, modifyList(run, list(espn_timestamp = t5 + 1)))) == 0L)

cat("PASS test_horizon_projections.R\n")
