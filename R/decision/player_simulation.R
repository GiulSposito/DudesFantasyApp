# Decision engine - Phase 3: player Monte Carlo (V2).
#
# Turn a point projection into a predictive distribution by resampling the errors
# the consensus has actually made historically (spec 8-11, 46):
#
#     points_sim = projection + sample(historical_consensus_residual, n_sim, replace = TRUE)
#
# NOT Normal(projection, source_sd). source_sd is source disagreement; the residual
# pool is real projection error.
#
# set.seed() is called ONCE by run_decision_pipeline(), never inside these functions.

library(tidyverse)

# --- residual pool selection (spec 9) ------------------------------------------

# Pick historical consensus residuals relevant to one current player, descending a
# 4-level fallback until the candidate set reaches min_pool_size (spec 9.1). Never
# fails: level 4 is the entire history.
#
#   history : analytical_db$consensus_error_history, already filtered to !is.na(residual)
#   returns : numeric vector of residuals, with attr "fallback_level" (1-4) and "pool_n"
get_residual_pool <- function(pos, projection, coverage_class, history,
                              k = 300, min_pool_size = 100) {

  # k nearest rows of `cand` by |projection - cand$projection|, then their residuals
  nearest_residuals <- function(cand) {
    ord <- order(abs(cand$projection - projection))
    cand$residual[ord[seq_len(min(k, nrow(cand)))]]
  }

  by_pos <- history[history$pos == pos, , drop = FALSE]

  # L1: position + coverage + projection neighbourhood
  l1 <- by_pos[by_pos$coverage_class == coverage_class, , drop = FALSE]
  if (nrow(l1) >= min_pool_size) return(.pool(nearest_residuals(l1), 1L))

  # L2: position + projection neighbourhood
  if (nrow(by_pos) >= min_pool_size) return(.pool(nearest_residuals(by_pos), 2L))

  # L3: position, all residuals (position pool too small to trim safely)
  if (nrow(by_pos) > 0L) return(.pool(by_pos$residual, 3L))

  # L4: all historical residuals
  .pool(history$residual, 4L)
}

.pool <- function(v, level) {
  v <- v[!is.na(v)]
  attr(v, "fallback_level") <- level
  attr(v, "pool_n") <- length(v)
  v
}

# --- player simulation -------------------------------------------------------

# consensus : output of build_current_consensus() (optionally left-joined with espn_id)
# history   : analytical_db$consensus_error_history
# Returns consensus + list-column `draws` (each length n_sim) + residual_pool_level
# + residual_pool_n.
simulate_players <- function(consensus, history, n_sim = 10000,
                             k = 300, min_pool_size = 100) {

  history <- history |>
    filter(!is.na(residual), !is.na(projection)) |>
    select(pos, projection, coverage_class, residual)

  sims <- consensus |>
    mutate(
      .sim = pmap(
        list(pos, projection, coverage_class),
        function(.pos, .proj, .cov) {
          pool  <- get_residual_pool(.pos, .proj, .cov, history, k, min_pool_size)
          draws <- .proj + sample(pool, n_sim, replace = TRUE)
          list(draws = draws,
               level = attr(pool, "fallback_level"),
               pool_n = attr(pool, "pool_n"))
        }
      )
    )

  sims |>
    mutate(
      draws               = map(.sim, "draws"),
      residual_pool_level = map_int(.sim, "level"),
      residual_pool_n     = map_int(.sim, "pool_n")
    ) |>
    select(-.sim)
}

# --- forecast summary (spec 11.2) --------------------------------------------

.q_probs <- c(p05 = .05, p10 = .10, p25 = .25, p50 = .50,
              p75 = .75, p90 = .90, p95 = .95)

# sims : output of simulate_players(). run_id : from new_run_id().
# Returns player_forecasts (no list-columns).
summarise_forecasts <- function(sims, run_id) {
  sims |>
    mutate(
      run_id   = run_id,
      sim_mean = map_dbl(draws, mean),
      sim_sd   = map_dbl(draws, sd),
      qs       = map(draws, ~ as_tibble_row(quantile(.x, .q_probs, names = FALSE) |>
                                              set_names(names(.q_probs)))),
      prob_gt_10 = map_dbl(draws, ~ mean(.x > 10)),
      prob_gt_15 = map_dbl(draws, ~ mean(.x > 15)),
      prob_gt_20 = map_dbl(draws, ~ mean(.x > 20)),
      prob_gt_25 = map_dbl(draws, ~ mean(.x > 25)),
      prob_gt_30 = map_dbl(draws, ~ mean(.x > 30))
    ) |>
    unnest(qs) |>
    select(run_id, season, week, tag, ffa_id, any_of("espn_id"), pos,
           projection, n_sources, coverage_class, source_sd, source_mad,
           sim_mean, sim_sd, p05, p10, p25, p50, p75, p90, p95,
           prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25, prob_gt_30,
           residual_pool_level, residual_pool_n)
}
