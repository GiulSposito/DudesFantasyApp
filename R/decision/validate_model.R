# Decision engine - calibration gate (spec 37-38).
#
# Backtest the player Monte Carlo against analytical_db$consensus_error_history.
# The goal of V2 is a CALIBRATED distribution, not just a low MAE (spec 37):
#
#   P10-P90 interval should cover the actual ~80% of the time
#   P25-P75 interval should cover the actual ~50% of the time
#
# Leakage control: leave-one-(season, week)-out. For every target we build the
# residual pool from history with that whole season/week slice removed, so the
# target's own residual and its same-week correlated rows never enter the pool.
#
# This is a MANUAL gate. It is not called by run_decision_pipeline() and is not a
# unit test. Full run is tens of seconds; use sample_frac < 1 while iterating.

library(tidyverse)

# Depends on get_residual_pool() from player_simulation.R.
if (!exists("get_residual_pool")) source("./R/decision/player_simulation.R")

validate_player_model <- function(history,
                                  n_sim = 2000,
                                  seed = 20260908,
                                  k = 300,
                                  min_pool_size = 100,
                                  sample_frac = 1) {

  history <- history |>
    filter(!is.na(residual), !is.na(projection), !is.na(actual_points)) |>
    select(season, week, pos, projection, coverage_class, residual, actual_points)

  set.seed(seed)

  groups <- history |> distinct(season, week)

  rows <- pmap_dfr(groups, function(season, week) {
    pool_history <- history |>
      filter(!(season == !!season & week == !!week)) |>
      select(pos, projection, coverage_class, residual)

    targets <- history |> filter(season == !!season, week == !!week)
    if (sample_frac < 1) targets <- slice_sample(targets, prop = sample_frac)

    pmap_dfr(
      list(targets$pos, targets$projection, targets$coverage_class, targets$actual_points),
      function(.pos, .proj, .cov, .actual) {
        pool  <- get_residual_pool(.pos, .proj, .cov, pool_history, k, min_pool_size)
        draws <- .proj + sample(pool, n_sim, replace = TRUE)
        q     <- quantile(draws, c(.10, .25, .50, .75, .90), names = FALSE)
        tibble(
          pos = .pos, coverage_class = .cov,
          in_10_90 = .actual >= q[1] & .actual <= q[5],
          in_25_75 = .actual >= q[2] & .actual <= q[4],
          err = mean(draws) - .actual,
          fallback_level = attr(pool, "fallback_level")
        )
      }
    )
  })

  by_cell <- rows |>
    summarise(
      n = n(),
      cov_p10_p90  = mean(in_10_90),
      cov_p25_p75  = mean(in_25_75),
      bias = mean(err),
      mae  = mean(abs(err)),
      rmse = sqrt(mean(err^2)),
      pct_fallback = mean(fallback_level > 1),
      .by = c(pos, coverage_class)
    ) |>
    arrange(pos, coverage_class)

  overall <- rows |>
    summarise(
      pos = "ALL", coverage_class = "ALL",
      n = n(),
      cov_p10_p90  = mean(in_10_90),
      cov_p25_p75  = mean(in_25_75),
      bias = mean(err),
      mae  = mean(abs(err)),
      rmse = sqrt(mean(err^2)),
      pct_fallback = mean(fallback_level > 1)
    )

  out <- bind_rows(by_cell, overall)
  print(out, n = nrow(out))
  invisible(out)
}
