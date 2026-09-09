# tests/decision/test_roster_evaluator.R - evaluate_roster (spec 18).

suppressMessages({library(tidyverse)})
source("./R/decision/lineup_optimizer.R")
source("./R/decision/roster_evaluator.R")

# mini slots: QB1, RB1, WR1, BE2
slots <- tibble(
  season = 2026L,
  lineup_slot_id = c(0L, 2L, 4L, 20L),
  lineup_slot    = c("QB", "RB", "WR", "BE"),
  count          = c(1L, 1L, 1L, 2L)
)
E <- c(QB = "0,20", RB = "2,3,20", WR = "3,4,20")
mk <- function(id, pos, sm) tibble(
  ffa_id = as.integer(id), pos = pos, sim_mean = sm,
  eligible_slot_ids = E[[pos]], player_name = paste0(pos, id),
  espn_id = as.integer(id * 10)
)

cand <- bind_rows(mk(1,"QB",10), mk(2,"RB",8), mk(3,"RB",5), mk(4,"WR",6))

# fixed draws: mean(draws) == sim_mean for each player, so expected_points
# must equal sum(optimal_lineup$sim_mean) exactly.
draws <- list(
  "1" = rep(10, 4), "2" = rep(8, 4), "3" = rep(5, 4), "4" = rep(6, 4),
  "9" = c(30, 30, 10, 10)                    # opponent total
)
opp <- 9L

ev <- evaluate_roster(cand, slots, draws, opp)
opt <- ev$optimal_lineup[[1]]

stopifnot(
  setequal(opt$ffa_id, c(1L, 2L, 4L)),                 # QB1, best RB, WR
  abs(ev$expected_points - sum(opt$sim_mean)) < 1e-9,   # 10 + 8 + 6
  abs(ev$expected_points - 24) < 1e-9,
  ev$win_probability == mean(rep(24, 4) > draws[["9"]]),# 0.5
  abs(ev$bench_value - 5) < 1e-9,                       # only ffa 3 sits
  identical(ev, evaluate_roster(cand, slots, draws, opp))   # deterministic
)

cat("PASS test_roster_evaluator.R\n")
