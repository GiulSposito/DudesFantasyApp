# tests/decision/test_snapshot.R - snapshot selection + FFA quality guard.
# Standalone: source() from the project root. Uses stopifnot(), no framework.

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/snapshot.R")

# --- fixture: two timestamps for the same season/week/tag --------------------
mk <- function(ts, src, pts) tibble(
  season = 2025L, week = 3L, tag = "preview", timestamp = as.POSIXct(ts, tz = "UTC"),
  data_src = src, id = "100", pos = "WR", points = pts
)
fix <- bind_rows(
  mk("2025-09-01 10:00", "CBS", 10), mk("2025-09-01 10:00", "ESPN", 12),
  mk("2025-09-02 09:00", "CBS", 20), mk("2025-09-02 09:00", "ESPN", 22)   # newer
)
ffa_db <- dm(ffa_proj_source_points = fix)

snap <- select_ffa_snapshot(ffa_db, 2025, 3, "preview")
stopifnot(
  snap$timestamp == as.POSIXct("2025-09-02 09:00", tz = "UTC"),
  nrow(snap$proj_source) == 2,                       # only newest timestamp's rows
  all(snap$proj_source$proj_points %in% c(20, 22)),
  is.integer(snap$proj_source$ffa_id), snap$proj_source$ffa_id[1] == 100L
)

# --- missing snapshot errors -----------------------------------------------
err <- tryCatch(select_ffa_snapshot(ffa_db, 2025, 9, "preview"), error = conditionMessage)
stopifnot(grepl("not found in ffa_db", err))

# --- quality guard: duplicate data_src/ffa_id/pos ---------------------------
dup <- bind_rows(mk("2025-09-02 09:00", "CBS", 20), mk("2025-09-02 09:00", "CBS", 21)) |>
  mutate(ffa_id = as.integer(id), proj_points = points)
derr <- tryCatch(check_ffa_snapshot_quality(dup), error = conditionMessage)
stopifnot(grepl("duplicated", derr))

# clean snapshot passes
stopifnot(isTRUE(check_ffa_snapshot_quality(
  mutate(snap$proj_source)
)))

# --- ESPN horizon: pinned to the selected snapshot's timestamp ---------------
# W5 snapshot (ts1) wrote target weeks 6..8; W6 snapshots ts2 then ts3 wrote 7..9.
# Selecting week 6 must take only the newest W6 snapshot's rows, and only weeks > 6.
t1 <- as.POSIXct("2025-10-01 10:00", tz = "UTC")
t2 <- as.POSIXct("2025-10-08 10:00", tz = "UTC")
t3 <- as.POSIXct("2025-10-09 10:00", tz = "UTC")
pts <- function(ts, wk, weeks, val, src = 1L, split = 1L) tibble(
  season = 2025L, week = weeks, tag = "preview", timestamp = ts, player_id = 7L,
  stat_source_id = src, stat_split_type_id = split, fantasy_points = val
)
espn_db <- list(
  espn_rosters = tibble(season = 2025L, week = c(5L, 6L, 6L), timestamp = c(t1, t2, t3),
                        player_id = 7L),
  espn_players_points = bind_rows(
    pts(t1, 5L, 6:8, 1),
    pts(t2, 6L, 7:9, 2),
    pts(t3, 6L, c(6L, 7:9), c(99, 3, 0, NA)),          # week 6 = this week, not horizon
    pts(t3, 6L, 7L, 50, split = 0L),                     # not the weekly projection
    pts(t3, 6L, 8L, 60, src = 0L)                        # not a projection
  ),
  espn_matchups = tibble(season = 2025L, week = 6L, timestamp = t3, matchup_period_id = 6L),
  espn_player_injury_status = tibble(season = integer(), week = integer()),
  espn_pro_teams = tibble(season = 2025L, pro_team = "KC", bye_week = 8L),
  espn_roster_slots = tibble(season = 2025L), espn_teams = tibble(season = 2025L),
  espn_players = tibble(season = 2025L)
)
es <- select_espn_snapshot(espn_db, 2025, 6, "preview")
stopifnot(
  identical(names(es$horizon), c("player_id", "target_week", "projection")),
  identical(es$horizon$target_week, 7:9),
  identical(es$horizon$projection, c(3, 0, 0)),          # ts3 only; NA -> 0
  identical(es$bye_teams, character())
)
# realized points: this snapshot's (ts3) actuals only; a locked player whose game
# kicked off < 4h before the snapshot keeps NA points (partial, not final)
act <- function(ts, pid, team, val) tibble(season = 2025L, week = 6L, tag = "preview",
  timestamp = ts, player_id = pid, pro_team_id = team, stat_source_id = 0L,
  stat_split_type_id = 1L, fantasy_points = val, lineup_locked = TRUE)
db_r <- espn_db
db_r$espn_players_points <- bind_rows(
  act(t2, 1L, 1L, 77),                                    # older snapshot: ignored
  act(t3, 2L, 1L, 12), act(t3, 3L, 2L, 4)                 # team 1 game over, team 2 live
)
db_r$espn_pro_games <- tibble(season = 2025L, week = 6L,
  game_date = c(t3 - 5 * 3600, t3 - 3600), home_pro_team_id = c(1L, 2L), away_pro_team_id = c(3L, 4L))
rz <- select_espn_snapshot(db_r, 2025, 6, "preview")$realized |> arrange(player_id)
stopifnot(
  identical(rz$player_id, 2:3),
  identical(rz$actual_points, c(12, NA)),
  all(rz$is_locked)
)

# a snapshot taken before the horizon existed -> 0 rows, not an error
espn_db$espn_players_points <- pts(t3, 6L, 6L, 99)
stopifnot(nrow(select_espn_snapshot(espn_db, 2025, 6, "preview")$horizon) == 0L)

cat("PASS test_snapshot.R\n")
