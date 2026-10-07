# tests/web/test_league_ranks.R - build_league_ranks(): standings / cumulative
# points / survival ranks over a synthetic 4-team league.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/bundle/ranks.R")

ts <- as.POSIXct("2026-10-01 12:00", tz = "UTC")
# wk = matchup period; the snapshot's own `week` column is irrelevant here
mk <- function(wk, h, hp, a, ap, winner = if (hp > ap) "HOME" else "AWAY") tibble(
  season = 2026L, week = 4L, tag = "x", timestamp = ts,
  matchup_id = wk * 10L + h, matchup_period_id = wk,
  home_team_id = h, home_points = hp, away_team_id = a, away_points = ap,
  winner = winner, playoff_tier_type = "NONE"
)
mu <- bind_rows(
  mk(1L, 1L, 100, 2L, 90),  mk(1L, 3L, 80,  4L, 70),    # w1: 1 100, 2 90, 3 80, 4 70
  mk(2L, 1L, 60,  3L, 110), mk(2L, 2L, 95,  4L, 120),   # w2: 4 120, 3 110, 2 95, 1 60
  mk(3L, 1L, 85,  4L, 85, "TIE"), mk(3L, 2L, 70, 3L, 75), # w3: tie 85/85, 3 75, 2 70
  mk(4L, 1L, 0, 2L, 0, "UNDECIDED"), mk(4L, 3L, 0, 4L, 0, "UNDECIDED")  # not played
)
r <- build_league_ranks(list(espn_db = list(espn_matchups = mu)),
                        list(season = 2026L, espn_timestamp = ts))
at <- function(w, t) r |> filter(week == w, team_id == t)

stopifnot(
  nrow(r) == 12L, !any(r$week == 4L),                         # undecided week dropped
  # cumulative points + record after w3
  at(3, 1)$cum_points == 245, at(3, 1)$wins == 1L, at(3, 1)$ties == 1L,
  at(3, 4)$cum_points == 275, at(3, 4)$losses == 1L,
  # standings w2: 3 is 2-0; 4 (190) and 1 (160) are 1-1 -> cumulative points; 2 is 0-2
  at(2, 3)$standing_rank == 1L, at(2, 4)$standing_rank == 2L,
  at(2, 1)$standing_rank == 3L, at(2, 2)$standing_rank == 4L,
  # w3: 3 is 2-1 (265), 1 is 1-1-1, 4 is 1-1-1 (275 > 245), 2 is 1-2
  at(3, 3)$standing_rank == 1L, at(3, 4)$standing_rank == 2L,
  at(3, 1)$standing_rank == 3L, at(3, 2)$standing_rank == 4L,
  # points rank = cumulative points
  at(3, 4)$points_rank == 1L, at(3, 3)$points_rank == 2L,
  # survival: w1 4 out (70); w2 among 1,2,3: 1 out (60); w3 among 2,3: 2 out (70)
  at(1, 4)$eliminated, at(1, 4)$survival_rank == 4L,
  is.na(at(2, 4)$survival_rank), !at(2, 4)$eliminated,
  at(2, 1)$eliminated, at(2, 3)$survival_rank == 1L,
  is.na(at(3, 1)$survival_rank), at(3, 2)$eliminated,
  sum(r$eliminated) == 3L
)

# tie on the week's lowest score: lower cumulative points goes out
mu_tie <- bind_rows(mk(1L, 1L, 100, 2L, 90), mk(1L, 3L, 90, 4L, 95))
mu_tie <- bind_rows(mu_tie, mk(2L, 1L, 50, 2L, 80), mk(2L, 3L, 80, 4L, 60))
rt <- build_league_ranks(list(espn_db = list(espn_matchups = mu_tie)),
                         list(season = 2026L, espn_timestamp = ts))
# w1: 2 and 3 tie at 90 (both cum 90) -> lower team_id (2) out
stopifnot(rt |> filter(week == 1, eliminated) |> pull(team_id) == 2L)

cat("PASS test_league_ranks.R\n")
