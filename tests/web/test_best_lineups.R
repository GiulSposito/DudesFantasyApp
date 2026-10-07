# tests/web/test_best_lineups.R - build_best_lineups(): dream team + best free
# agents over a synthetic league; only weeks with a "final" snapshot count.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/bundle/best_lineups.R")

ts_fin <- as.POSIXct("2026-09-22 08:00", tz = "UTC")
ts_mnf <- as.POSIXct("2026-09-28 08:00", tz = "UTC")
elig <- c(QB = "0,20,21", RB = "2,3,20,21", WR = "3,4,20,21", TE = "6,20,21",
          `D/ST` = "16,20,21", K = "17,20,21")

# 6 per position; ids encode position + rank (101 = QB 1 ... 606 = K 6),
# points 35, 30, 25, 20, 15, 10
pos <- names(elig)
players <- tibble(position = rep(pos, each = 6), k = rep(1:6, length(pos))) |>
  mutate(player_id = match(position, pos) * 100L + k,
         player_name = paste(position, k), pro_team = "XXX",
         fantasy_points = 40 - k * 5)
# WR 5 (22) beats RB 5 (15) -> takes the league flex
players$fantasy_points[players$player_id == 305L] <- 22

# odd k rostered by team 1, even k free agents
rostered <- players |> filter(k %% 2L == 1L)

mk_snap <- function(wk, tag, ts) list(
  ros = rostered |> transmute(season = 2026L, week = wk, tag, timestamp = ts,
                              team_id = 1L, player_id, position,
                              eligible_slot_ids = elig[position]),
  pts = players |> mutate(season = 2026L, week = wk, tag = tag, timestamp = ts,
                          stat_source_id = 0L, stat_split_type_id = 1L)
)
s2 <- mk_snap(2L, "final", ts_fin)
s3 <- mk_snap(3L, "preMNF", ts_mnf)

src <- list(espn_db = list(
  espn_rosters        = bind_rows(s2$ros, s3$ros),
  espn_players_points = bind_rows(s2$pts, s3$pts),
  espn_roster_slots   = tibble(season = 2026L,
                               lineup_slot_id = c(0L, 2L, 3L, 4L, 6L, 16L, 17L, 20L),
                               lineup_slot = c("QB", "RB", "RB/WR", "WR", "TE", "D/ST", "K", "BE"),
                               count = c(1L, 2L, 1L, 2L, 1L, 1L, 1L, 6L))
))
b <- build_best_lineups(src, list(season = 2026L, espn_timestamp = ts_mnf))
lg <- b |> filter(kind == "league")
fa <- b |> filter(kind == "free_agents")

stopifnot(
  all(b$week == 2L),                                       # w3 has no final snapshot
  nrow(lg) == 9L, nrow(fa) == 9L,
  !anyDuplicated(lg$player_id), !anyDuplicated(fa$player_id),
  !any(lg$player_id %in% fa$player_id),
  all(lg$team_id == 1L), all(is.na(fa$team_id)),
  all(lg$player_id %% 2L == 1L), all(fa$player_id %% 2L == 0L),
  # league: RB 1, RB 3 / WR 1, WR 3 in their slots, WR 5 in the flex
  lg$player_id[lg$lineup_slot == "RB/WR"] == 305L,
  setequal(lg$player_id[lg$lineup_slot %in% c("RB", "WR")], c(201L, 203L, 301L, 303L)),
  sum(lg$points) == 35 * 6 + 25 * 2 + 22,
  identical(lg$slot_order, 1:9)
)

# no final snapshot at all -> empty, typed
e <- build_best_lineups(src, list(season = 2026L, espn_timestamp = ts_fin - 1))
stopifnot(nrow(e) == 0L, is.integer(e$week))

cat("PASS test_best_lineups.R\n")
