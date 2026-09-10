# tests/decision/test_realized_points.R - realized-points folding.
#
# Players whose NFL game has locked enter the Monte Carlo at their realized
# points (degenerate distribution) and are barred from lineup/FA/trade moves.

suppressMessages({library(tidyverse)})
source("./R/decision/player_simulation.R")
source("./R/decision/matchup_simulation.R")
source("./R/decision/lineup_optimizer.R")
source("./R/decision/roster_evaluator.R")

n_sim <- 50L

# minimal simulate_players() output: ffa_id + draws list-col + pool cols
sims <- tibble(
  ffa_id              = c(1L, 2L, 3L),
  pos                 = c("QB", "RB", "WR"),
  season = 2026L, week = 1L, tag = "preview",
  projection          = c(20, 10, 12),
  n_sources = 3L, coverage_class = "sparse", source_sd = 1, source_mad = 1,
  draws               = list(rnorm(n_sim, 20), rnorm(n_sim, 10), rnorm(n_sim, 12)),
  residual_pool_level = c(1L, 1L, 1L),
  residual_pool_n     = c(200L, 200L, 200L)
)

# --- 1. no realized rows -> byte-identical -----------------------------------
none <- apply_realized_points(sims, tibble(ffa_id = integer(), actual_points = double()), n_sim)
stopifnot(identical(none$draws, sims$draws),
          all(none$is_realized == FALSE))

# --- 2. locked player -> constant draws at actual, others untouched ---------
realized <- tibble(ffa_id = 2L, actual_points = 17.5)
out <- apply_realized_points(sims, realized, n_sim)
stopifnot(
  out$is_realized == c(FALSE, TRUE, FALSE),
  identical(out$draws[[1]], sims$draws[[1]]),
  identical(out$draws[[3]], sims$draws[[3]]),
  length(out$draws[[2]]) == n_sim,
  all(out$draws[[2]] == 17.5),
  is.na(out$residual_pool_level[[2]]), is.na(out$residual_pool_n[[2]])
)

# --- 3. summarise_forecasts carries is_realized, sd 0 ----------------------
fc <- summarise_forecasts(out, run_id = "r1")
r2 <- fc |> filter(ffa_id == 2L)
stopifnot(r2$is_realized == TRUE, r2$sim_sd == 0,
          abs(r2$sim_mean - 17.5) < 1e-9, r2$p50 == 17.5,
          fc$is_realized[fc$ffa_id == 1L] == FALSE)

# --- 4. matchup: locked 30 vs all-0 projected -> home always wins ----------
dbf <- list("1" = rep(30, n_sim), "2" = rep(0, n_sim))
mm  <- simulate_matchup(1L, 2L, dbf)
stopifnot(mm$home_win_probability == 1, mm$away_win_probability == 0)

# --- 5. evaluate_roster(pinned_ffa) always starts the pinned player --------
slots <- tibble(season = 2026L,
                lineup_slot_id = c(0L, 2L, 4L, 20L),
                lineup_slot    = c("QB", "RB", "WR", "BE"),
                count          = c(1L, 1L, 1L, 2L))
E <- c(QB = "0,20", RB = "2,3,20", WR = "3,4,20")
mk <- function(id, pos, sm) tibble(
  ffa_id = as.integer(id), pos = pos, sim_mean = sm,
  eligible_slot_ids = E[[pos]], player_name = paste0(pos, id),
  espn_id = as.integer(id * 10))
cand  <- bind_rows(mk(1,"QB",10), mk(2,"RB",2), mk(3,"RB",9), mk(4,"WR",6))
draws <- list("1" = rep(10, 4), "2" = rep(2, 4), "3" = rep(9, 4), "4" = rep(6, 4),
              "9" = rep(15, 4))
# without pin the weak RB (ffa 2) sits; with pin it must start (bumping ffa 3)
free <- evaluate_roster(cand, slots, draws, 9L)
pin  <- evaluate_roster(cand, slots, draws, 9L, pinned_ffa = 2L)
stopifnot(!2L %in% free$optimal_lineup[[1]]$ffa_id,
          2L %in% pin$optimal_lineup[[1]]$ffa_id,
          nrow(pin$optimal_lineup[[1]]) == 3)

cat("PASS test_realized_points.R\n")
