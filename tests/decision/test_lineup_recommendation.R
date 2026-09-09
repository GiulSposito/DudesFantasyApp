# tests/decision/test_lineup_recommendation.R - recommend_lineups (spec 17, 41).

suppressMessages({library(tidyverse)})
source("./R/decision/lineup_optimizer.R")
source("./R/decision/roster_evaluator.R")

# mini slots: QB1, RB2, WR1, BE2
slots <- tibble(
  season = 2026L,
  lineup_slot_id = c(0L, 2L, 4L, 20L),
  lineup_slot    = c("QB", "RB", "WR", "BE"),
  count          = c(1L, 2L, 1L, 2L)
)
E <- c(QB = "0,20", RB = "2,3,20", WR = "3,4,20")

pl <- function(team, id, pos, sm, starter) tibble(
  season = 2026L, week = 1L, tag = "preview",
  team_id = as.integer(team), espn_id = as.integer(id * 10), ffa_id = as.integer(id),
  player_name = paste0(pos, id), position = pos, pos = pos,
  eligible_slot_ids = E[[pos]],
  lineup_slot = if (starter) pos else "BE", lineup_slot_id = if (starter) 1L else 20L,
  is_starter = starter, is_bench = !starter, is_ir = FALSE,
  injury_status = "ACTIVE", sim_mean = sm
)

# team 10: bench RB f5 (20) beats starter RB f3 (8) -> one recommended swap
# team 20: already optimal (top-2 RB are the two starters)
cp <- bind_rows(
  pl(10, 1, "QB", 10, TRUE),  pl(10, 2, "RB", 15, TRUE),
  pl(10, 3, "RB", 8,  TRUE),  pl(10, 4, "WR", 12, TRUE),
  pl(10, 5, "RB", 20, FALSE), pl(10, 6, "WR", 5,  FALSE),
  pl(20, 11, "QB", 10, TRUE), pl(20, 12, "RB", 15, TRUE),
  pl(20, 13, "RB", 14, TRUE), pl(20, 14, "WR", 12, TRUE),
  pl(20, 15, "RB", 3,  FALSE), pl(20, 16, "WR", 2, FALSE)
)

draws <- set_names(map(cp$ffa_id, ~ rep(cp$sim_mean[cp$ffa_id == .x], 200)),
                   as.character(cp$ffa_id))

espn_snap <- list(
  roster_slots = slots,
  matchups     = tibble(home_team_id = 10L, away_team_id = 20L)
)

out <- recommend_lineups(cp, espn_snap, draws, "TESTRUN", 2026, 1, "preview")
le  <- out$evaluations
lr  <- out$recommendations

# team 20 opponent total = 10+15+8+12 = 45 (team 10 current) -> always loses;
# team 10 optimal = 10+20+15+12 = 57 > team 20's 51 -> always wins.
e10 <- le[le$team_id == 10, ]
e20 <- le[le$team_id == 20, ]
stopifnot(
  nrow(le) == 2,
  e10$opponent_team_id == 20, e20$opponent_team_id == 10,
  abs(e10$current_expected - 45) < 1e-9,
  abs(e10$optimal_expected - 57) < 1e-9,
  e10$n_substitutions == 1,
  e20$n_substitutions == 0,
  abs(e20$optimal_expected - e20$current_expected) < 1e-9,   # already optimal
  e10$current_win_probability == 0, e10$optimal_win_probability == 1
)

# exactly one swap row, for team 10, f3 out / f5 in, into an RB slot
stopifnot(
  nrow(lr) == 1,
  lr$team_id == 10L,
  lr$player_out == 30L, lr$player_in == 50L,           # espn_id = ffa_id * 10
  lr$player_out_name == "RB3", lr$player_in_name == "RB5",
  lr$slot == "RB",
  abs(lr$delta_expected - 12) < 1e-9,                  # 57 - 45
  lr$recommendation_rank == 1,
  lr$player_out %in% cp$espn_id[cp$is_starter],
  !lr$player_in %in% cp$espn_id[cp$is_starter]
)

# opponent map works in the other direction too
snap2 <- modifyList(espn_snap,
  list(matchups = tibble(home_team_id = 20L, away_team_id = 10L)))
le2 <- recommend_lineups(cp, snap2, draws, "T2", 2026, 1, "preview")$evaluations
stopifnot(le2$opponent_team_id[le2$team_id == 10] == 20)

cat("PASS test_lineup_recommendation.R\n")
