# tests/decision/test_residual_pool.R - get_residual_pool 4-level fallback (spec 9.1).

suppressMessages({library(tidyverse)})
source("./R/decision/player_simulation.R")

set.seed(1)
# WR ensemble: 500 rows -> L1 holds
wr_ens <- tibble(pos = "WR", coverage_class = "ensemble",
                 projection = runif(500, 0, 30), residual = rnorm(500))
# WR sparse: only 40 rows -> below min_pool_size, must descend
wr_sps <- tibble(pos = "WR", coverage_class = "sparse",
                 projection = runif(40, 0, 30), residual = rnorm(40, 5))
# RB single: 20 rows only, no ensemble/sparse -> position pool < min -> L3
rb <- tibble(pos = "RB", coverage_class = "single",
             projection = runif(20, 0, 20), residual = rnorm(20, -3))
hist <- bind_rows(wr_ens, wr_sps, rb)

# L1: exactly k nearest, ordered by |projection - target|
p1 <- get_residual_pool("WR", 15, "ensemble", hist, k = 50, min_pool_size = 100)
stopifnot(
  attr(p1, "fallback_level") == 1L,
  length(p1) == 50,
  is.numeric(p1), is.null(dim(p1))
)
expect_near <- wr_ens |> slice_min(abs(projection - 15), n = 50) |> pull(residual)
stopifnot(setequal(round(p1, 8), round(expect_near, 8)))

# L2: WR sparse pool (40) < 100 -> falls to position neighbourhood (WR = 540 rows)
p2 <- get_residual_pool("WR", 15, "sparse", hist, k = 60, min_pool_size = 100)
stopifnot(attr(p2, "fallback_level") == 2L, length(p2) == 60)

# L3: RB position pool (20) < 100 and no larger neighbourhood -> all RB residuals
p3 <- get_residual_pool("RB", 10, "single", hist, k = 300, min_pool_size = 100)
stopifnot(attr(p3, "fallback_level") == 3L, length(p3) == 20)

# L4: unknown position -> entire history
p4 <- get_residual_pool("QB", 20, "ensemble", hist, k = 300, min_pool_size = 100)
stopifnot(attr(p4, "fallback_level") == 4L, length(p4) == nrow(hist))

cat("PASS test_residual_pool.R\n")
