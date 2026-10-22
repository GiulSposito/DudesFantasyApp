# tests/web/test_draft.R - build_draft(): VOR over the league-wide replacement
# level, value over the picks around each pick, decision + luck split, ranks.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/bundle/draft.R")

ts <- function(x) as.POSIXct(x, tz = "UTC")
KICK  <- ts("2026-09-10 00:20")
T2    <- ts("2026-09-20 10:00")   # newest week (2) snapshot
T1F   <- ts("2026-09-20 10:30")   # week-1 "final" fetched later: no acquisition_type

players <- tribble(
  ~player_id, ~player_name, ~position, ~points,
   1L, "q1", "QB", 100,   2L, "q2", "QB", 80,   3L, "q3", "QB", 60,   4L, "q4", "QB", 0,
  11L, "r1", "RB",  90,  12L, "r2", "RB", 70,  13L, "r3", "RB", 50,  14L, "r4", "RB", 20,
  21L, "w1", "WR",  85,  22L, "w2", "WR", 65,  23L, "w3", "WR", 55,  24L, "w4", "WR", 30
) |> mutate(season = 2026L, pro_team_id = if_else(player_id %% 2L == 0L, 1L, 2L),
            pro_team = if_else(pro_team_id == 1L, "AAA", "BBB"))
elig <- c(QB = "0,20,21", RB = "2,3,20,21", WR = "3,4,20,21")

season_pts <- function(timestamp, stat_source_id, value) players |>
  transmute(season, week = 0L, tag = "x", timestamp, player_id, stat_source_id,
            stat_split_type_id = 0L, stat_season = 2026L, fantasy_points = value)
weekly <- function(week, timestamp, player_id, fantasy_points) tibble(
  season = 2026L, week, tag = "x", timestamp, player_id, stat_source_id = 0L,
  stat_split_type_id = 1L, stat_season = 2026L, fantasy_points)

roster <- function(week, timestamp, team_id, player_id, acquisition_type) tibble(
  season = 2026L, week, timestamp, team_id, player_id, acquisition_type) |>
  left_join(select(players, player_id, position), by = "player_id") |>
  mutate(eligible_slot_ids = elig[position])
r2 <- bind_rows(roster(2L, T2, 1L, c(11L, 14L, 2L, 24L), "DRAFT"), roster(2L, T2, 1L, 13L, "ADD"),
                roster(2L, T2, 2L, c(1L, 21L, 22L, 12L), "DRAFT"))

src <- list(espn_db = list(
  espn_draft = tibble(season = 2026L, overall_pick = 1:8,
                      team_id = c(1L, 2L, 2L, 1L, 1L, 2L, 2L, 1L),
                      player_id = c(11L, 1L, 21L, 14L, 2L, 22L, 12L, 24L)) |>
    mutate(round = (overall_pick + 1L) %/% 2L, round_pick = 2L - overall_pick %% 2L),
  espn_players = select(players, -points),
  espn_players_points = bind_rows(
    season_pts(ts("2026-09-13 10:00"), 0L, 5),                       # older totals
    season_pts(T2, 0L, players$points),
    weekly(1L, ts("2026-09-13 10:00"), c(11L, 14L), c(50, 0)),
    weekly(2L, T2, c(11L, 14L), c(40, 20)),
    season_pts(ts("2026-09-05 10:00"), 1L, 999) |> filter(player_id == 11L),  # thin early snapshot
    season_pts(ts("2026-09-08 10:00"), 1L,                           # pre-kickoff projection
               17 * if_else(players$player_id == 1L, 120, players$points)),
    season_pts(ts("2026-09-12 10:00"), 1L, 0)                         # in-season: ignored
  ),
  espn_pro_games = tibble(season = 2026L, week = c(1L, 2L), game_date = c(KICK, ts("2026-09-30 00:20")),
                          home_pro_team_id = 1L, away_pro_team_id = 2L,
                          stats_official = c(TRUE, FALSE)),
  espn_rosters = bind_rows(r2, mutate(r2, week = 1L, timestamp = T1F, team_id = 2L,
                                      acquisition_type = NA_character_)),
  espn_roster_slots = tibble(season = 2026L, lineup_slot_id = c(0L, 2L, 3L, 4L, 20L, 21L),
                             lineup_slot = c("QB", "RB", "RB/WR", "WR", "BE", "IR"),
                             count = c(1L, 1L, 1L, 1L, 3L, 1L))
))
run <- list(season = 2026L, espn_timestamp = ts("2026-09-20 12:00"))

d <- build_draft(src, run)
row <- function(id) d[d$player_id == id, ]
drafted <- filter(d, !is.na(overall_pick))
stopifnot(
  nrow(d) == 11L, !4L %in% d$player_id,                   # undrafted 0-pointer dropped
  # league starters: 2 QB, 2 RB, 2 WR + 2 flex (w3, r3) -> replacement q3 / r4 / w4
  row(1L)$vor == 40, row(11L)$vor == 70, row(21L)$vor == 55, row(14L)$vor == 0,
  row(11L)$vor_expected == 55,                            # mean of picks 1-2
  row(14L)$value_over_expected == -25,                    # 0 - mean(55, 0, 20)
  row(14L)$draft_pos_rank == 2L, row(14L)$pos_rank == 4L, row(14L)$pos_rank_delta == -2L,
  row(12L)$pos_rank_delta == 1L,
  is.na(row(3L)$overall_pick), is.na(row(3L)$vor_expected), row(3L)$vor == 0,
  row(13L)$owner_team_id == 1L, row(13L)$acquisition_type == "ADD",  # newest week wins
  row(11L)$points == 90, row(11L)$weeks_scored == 2L, row(14L)$weeks_scored == 1L,
  row(11L)$proj_points == 17 * 90,                        # first full pre-kickoff snapshot
  row(11L)$proj_points_to_date == 90,                     # 1 of 17 games played
  row(1L)$proj_vor == 60,                                 # projected 120 vs q3 60
  isTRUE(all.equal(drafted$decision_value + drafted$luck_value, drafted$value_over_expected))
)

src$espn_db$espn_draft <- src$espn_db$espn_draft[0, ]
stopifnot(nrow(build_draft(src, run)) == 0L)

cat("PASS test_draft.R\n")
