# tests/decision/test_league_state.R - build_current_league_state (spec 12).

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/league_state.R")

analytical_db <- dm(player_ids = tibble(
  ffa_id  = c(1L, 2L, 3L, 4L, 5L),
  espn_id = c(100L, 101L, 102L, 103L, 104L),
  nfl_id = NA_integer_, numfire_id = NA_character_
))
ffa_db <- dm(
  ffa_player_ids = tibble(id = character(), espn_id = character()),
  ffa_players    = tibble(id = character(), first_name = character(),
                          last_name = character(), pos = character())
)

rosters <- tibble(
  season = 2026L, week = 1L, tag = "preview", timestamp = Sys.time(),
  team_id     = c(10L, 10L, 10L, 20L, 20L, 20L),
  player_id   = c(100L, 101L, 102L, 103L, 104L, 999L),  # 999 = bench, unmapped
  player_name = c("P1", "P2", "P3", "P4", "P5", "Bench Nobody"),
  position    = c("QB", "RB", "WR", "QB", "D/ST", "WR"),
  pro_team    = "NE",
  lineup_slot = c("QB", "RB", "BE", "QB", "D/ST", "BE"),
  lineup_slot_id = c(0L, 2L, 20L, 0L, 16L, 20L),
  eligible_slot_ids = c("0,7,20,21", "2,3,23,7,20,21", "3,4,5,23,7,20,21",
                        "0,7,20,21", "16,20,21", "3,4,5,23,7,20,21"),
  is_starter  = c(TRUE, TRUE, FALSE, TRUE, TRUE, FALSE),
  is_bench    = c(FALSE, FALSE, TRUE, FALSE, FALSE, TRUE),
  is_ir       = FALSE,
  injury_status = "ACTIVE"
)
espn_snap <- list(
  rosters = rosters, season = 2026, week = 1, tag = "preview",
  injury = tibble(player_id = c(100L, 104L),
                  injury_status = c("QUESTIONABLE", "ACTIVE"),
                  injured = c(TRUE, FALSE), active = c(TRUE, TRUE))
)
player_forecasts <- tibble(
  ffa_id = 1:5L, pos = c("QB", "RB", "WR", "QB", "DST"),
  projection = 10:14, sim_mean = c(11, 13, 15, 12, 7), sim_sd = 4,
  p10 = 3, p50 = 11, p90 = 22, coverage_class = "ensemble", n_sources = 5L
)

cp <- suppressWarnings(
  build_current_league_state(espn_snap, player_forecasts, analytical_db, ffa_db)
)

stopifnot(
  nrow(cp) == nrow(rosters),                 # 1 row per roster player
  sum(cp$is_starter) == 4,
  all(!is.na(cp$sim_mean[cp$is_starter])),    # every starter carries a forecast
  is.na(cp$sim_mean[cp$player_name == "Bench Nobody"]),   # unmapped bench -> NA
  cp$pos[cp$position == "D/ST"] == "DST",     # position normalised
  cp$injury_status[cp$espn_id == 100] == "QUESTIONABLE",  # injury table wins
  all(c("team_id", "espn_id", "ffa_id", "bridge_method", "lineup_slot",
        "lineup_slot_id", "eligible_slot_ids",
        "is_starter", "sim_mean", "p10", "p50", "p90") %in% names(cp)),
  cp$lineup_slot_id[cp$espn_id == 104] == 16L,            # slot cols pass through
  grepl("16", cp$eligible_slot_ids[cp$espn_id == 104])
)

cat("PASS test_league_state.R\n")
