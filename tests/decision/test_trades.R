# tests/decision/test_trades.R - recommend_trades (spec 24-28, 43).

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/lineup_optimizer.R")
source("./R/decision/roster_evaluator.R")
source("./R/decision/trades.R")
source("./R/decision/decision_db.R")

# ===========================================================================
# Fixture - self-contained 4-team mini league (mirrors test_free_agents.R B)
# ===========================================================================

# slots: QB1, RB1, WR1, FLEX1 (id 23, RB/WR), BE2  -> 4 starters
slots <- tibble(
  season = 2026L,
  lineup_slot_id = c(0L, 2L, 4L, 23L, 20L),
  lineup_slot    = c("QB", "RB", "WR", "FLEX", "BE"),
  count          = c(1L, 1L, 1L, 1L, 2L)
)
E <- c(QB = "0,20", RB = "2,23,20", WR = "4,23,20")

pl <- function(team, id, pos, sm, starter, ffa = id) tibble(
  season = 2026L, week = 1L, tag = "preview",
  team_id = as.integer(team), espn_id = as.integer(id * 10),
  ffa_id = as.integer(ffa),
  player_name = paste0(pos, id), position = pos, pos = pos,
  eligible_slot_ids = E[[pos]],
  lineup_slot = if (starter) pos else "BE", lineup_slot_id = if (starter) 1L else 20L,
  is_starter = starter, is_bench = !starter, is_ir = FALSE,
  injury_status = "ACTIVE", sim_mean = sm
)

# team 10 (mine): RB-deep, WR-thin. current lineup QB1/RB2/FLEX RB3/WR5 = 42.
# team 30 (partner, NOT my opponent): WR-deep, RB-thin, current lineup = 42.
# team 20 (my week opponent, also a partner): 4 flat starters = 40.
# team 40 (team 30's opponent, backdrop only): 4 flat starters = 40.
cp <- bind_rows(
  pl(10, 1, "QB", 10, TRUE),  pl(10, 2, "RB", 15, TRUE),
  pl(10, 3, "RB", 12, TRUE),  pl(10, 5, "WR", 5,  TRUE),
  pl(10, 4, "RB", 9,  FALSE),
  pl(30, 11, "QB", 10, TRUE), pl(30, 12, "WR", 15, TRUE),
  pl(30, 13, "WR", 12, TRUE), pl(30, 15, "RB", 5,  TRUE),
  pl(30, 14, "WR", 9,  FALSE),
  pl(20, 21, "QB", 10, TRUE), pl(20, 22, "RB", 10, TRUE),
  pl(20, 23, "WR", 10, TRUE), pl(20, 24, "RB", 10, TRUE),
  pl(40, 41, "QB", 10, TRUE), pl(40, 42, "RB", 10, TRUE),
  pl(40, 43, "WR", 10, TRUE), pl(40, 44, "RB", 10, TRUE)
)

# fixed draws: mean(draws) == sim_mean for every player, so deltas are exact.
draws <- set_names(map(cp$sim_mean, ~ rep(.x, 200)), as.character(cp$ffa_id))

espn_snap <- list(
  roster_slots = slots,
  matchups = tibble(home_team_id = c(10L, 30L), away_team_id = c(20L, 40L))
)

out <- recommend_trades(cp, espn_snap, draws, "TESTRUN", 2026, 1, "preview",
                        team_id = 10L, max_give = 5L, max_receive_per_pos = 3L,
                        top_n = 10L)

# expected survivors (all with partner 30, my_delta > 0 AND their_delta >= 0):
#   rank1  give RB3 (12)  x receive WR12 (15)  -> my +7, their +1, score 8
#   rank2  give RB4 (9)   x receive WR13 (12)  -> my +7, their +1, score 8
#   rank3  give WR5 (5)   x receive WR14 (9)   -> my +4, their  0, score 4
stopifnot(
  identical(names(out), names(.empty_trade_recs())),        # exact spec-28 schema
  nrow(out) == 3,
  all(out$my_team_id == 10L), all(out$other_team_id == 30L),
  out$give_ffa_id[1] == 3L, out$receive_ffa_id[1] == 12L,
  out$give_position[1] == "RB", out$receive_position[1] == "WR",
  out$give_player_id[1] == 30L, out$receive_player_id[1] == 120L,
  abs(out$my_before_expected[1]    - 42) < 1e-9,
  abs(out$their_before_expected[1] - 42) < 1e-9,
  abs(out$my_after_expected[1]     - 49) < 1e-9,
  abs(out$their_after_expected[1]  - 43) < 1e-9,
  abs(out$my_delta_expected[1]     -  7) < 1e-9,
  abs(out$their_delta_expected[1]  -  1) < 1e-9,
  abs(out$trade_score[1] - 8) < 1e-9,
  abs(out$fairness[1] - (-6)) < 1e-9,
  # arithmetic holds on every row
  all(abs(out$trade_score -
          (out$my_delta_expected + pmin(out$my_delta_expected, out$their_delta_expected))) < 1e-9),
  all(abs(out$fairness + abs(out$my_delta_expected - out$their_delta_expected)) < 1e-9),
  all(abs((out$my_after_expected - out$my_before_expected) - out$my_delta_expected) < 1e-9),
  all(abs((out$their_after_expected - out$their_before_expected) - out$their_delta_expected) < 1e-9),
  all(out$my_delta_expected > 0),                           # spec 26 hard rule
  all(out$their_delta_expected >= 0),                       # min_their_delta default
  length(unique(round(out$my_before_expected, 9))) == 1L,   # before constant
  nrow(out) <= 1 || all(diff(out$trade_score) <= 1e-9),     # ranked desc
  identical(out$recommendation_rank, seq_len(nrow(out))),
  !anyDuplicated(out$receive_player_id),                    # one row per received player
  !(10L %in% out$give_player_id),                           # my only QB never given
  !any(c(110L, 210L, 410L) %in% out$receive_player_id),     # no team's only QB received
  all(out$partner_is_my_opponent == FALSE),                 # my_opp is team 20, not 30
  identical(out, recommend_trades(cp, espn_snap, draws, "TESTRUN", 2026, 1, "preview",
                                  team_id = 10L, max_give = 5L,
                                  max_receive_per_pos = 3L, top_n = 10L))
)

# no unique opponent for my team -> empty, no error
snap_bad <- modifyList(espn_snap,
  list(matchups = tibble(home_team_id = 99L, away_team_id = 98L)))
stopifnot(nrow(suppressWarnings(
  recommend_trades(cp, snap_bad, draws, "R", 2026, 1, "preview", team_id = 10L))) == 0)

# nothing beneficial -> 0 rows (every roster flat, no 1x1 swap nets a gain)
cp_flat    <- cp |> mutate(sim_mean = 10)
draws_flat <- map(draws, ~ rep(10, 200))
stopifnot(nrow(recommend_trades(cp_flat, espn_snap, draws_flat, "R",
                                2026, 1, "preview", team_id = 10L)) == 0)

# ===========================================================================
# DB key check - PK holds on the 0-row template
# ===========================================================================

sr <- build_simulation_run("R", 2026, 1, "preview", Sys.time(), Sys.time(), 10L, 1L)
tiny_fc <- tibble(run_id = "R", season = 2026L, week = 1L, tag = "preview",
                  ffa_id = 1L, pos = "QB")
db <- build_decision_db(sr, tiny_fc, trade_recommendations = .empty_trade_recs())
stopifnot("trade_recommendations" %in% names(db), inherits(db, "dm"))

cat("PASS test_trades.R\n")
