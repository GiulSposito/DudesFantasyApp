# tests/decision/test_simulation_repro.R - Monte Carlo reproducibility (spec 38).

suppressMessages({library(tidyverse)})
source("./R/decision/player_simulation.R")

set.seed(1)
hist <- tibble(
  pos = rep(c("WR", "RB"), each = 400),
  coverage_class = "ensemble",
  projection = runif(800, 0, 30),
  residual = rnorm(800, 0, 6)
)
con <- tibble(
  season = 2025L, week = 4L, tag = "preview",
  ffa_id = 1:20L, pos = rep(c("WR", "RB"), 10),
  projection = runif(20, 5, 25), n_sources = 5L, coverage_class = "ensemble",
  source_sd = 2, source_mad = 2
)

run <- function(seed) {
  set.seed(seed)
  s <- simulate_players(con, hist, n_sim = 3000)
  summarise_forecasts(s, "R")
}

a <- run(1234); b <- run(1234); c <- run(99)

# same seed -> identical forecasts
stopifnot(isTRUE(all.equal(a, b)))
# different seed -> different quantiles
stopifnot(!isTRUE(all.equal(a$p50, c$p50)))

# centred pool: sim_mean ~= projection (the pool's mean bias is not carried),
# spread ~= the pool's own sd
hf <- hist |> filter(!is.na(residual))
one <- con |> slice(1)
pool <- get_residual_pool(one$pos, one$projection, one$coverage_class, hf)
stopifnot(abs(a$sim_mean[1] - one$projection) < 0.6,
          abs(a$sim_sd[1] - sd(pool)) < 0.6)

# a biased pool (+3 mean) still centres on the projection
hb <- hist |> mutate(residual = residual + 3)
set.seed(1); sb <- summarise_forecasts(simulate_players(con, hb, n_sim = 3000), "R")
stopifnot(all(abs(sb$sim_mean - con$projection) < 0.6))

# floor: never below the position's lowest historical actual
lo <- tibble(pos = "WR", coverage_class = "ensemble", projection = rep(c(1, 2), 100),
             residual = rep(c(-1, 20), 100))                       # actuals 0 / 22 -> floor 0
set.seed(1); sl <- simulate_players(con |> slice(1) |> mutate(pos = "WR", projection = 1), lo, n_sim = 500)
stopifnot(min(sl$draws[[1]]) >= 0)

# monotone quantiles
stopifnot(with(a, all(p05 <= p10 & p10 <= p25 & p25 <= p50 & p50 <= p75 & p75 <= p90 & p90 <= p95)))

cat("PASS test_simulation_repro.R\n")
