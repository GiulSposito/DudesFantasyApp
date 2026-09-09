# Decision engine - Phase 7: roster evaluator (spec 18).
#
# The shared value function for a roster in one week: its best legal lineup, that
# lineup's point distribution, and its win probability against one opponent.
# Reused by the lineup recommender (M3) and, later, free agents (M4) and trades
# (M5).
#
# Deterministic given inputs + the pipeline seed + n_sim (spec 18): the draws are
# already frozen by the single set.seed() before simulate_players(); nothing here
# draws random numbers, and optimize_lineup() breaks ties on a total order.
#
# Requires optimize_lineup() from lineup_optimizer.R and simulate_matchup() from
# matchup_simulation.R (both sourced by decision_pipeline.R).

library(tidyverse)

if (!exists("optimize_lineup"))  source("./R/decision/lineup_optimizer.R")
if (!exists("simulate_matchup")) source("./R/decision/matchup_simulation.R")

# candidates       : same shape as optimize_lineup() input (roster's startable
#                    players, already filtered of NA / injured by the caller).
# roster_slots     : espn_snap$roster_slots.
# draws_by_ffa     : named list character(ffa_id) -> numeric(n_sim).
# opponent_ffa_ids : integer vector, the opponent's current starters.
# Returns a 1-row tibble: expected_points, p10/p50/p90, win_probability,
# bench_value, optimal_lineup (list-col with the optimize_lineup() tibble).
evaluate_roster <- function(candidates, roster_slots, draws_by_ffa,
                            opponent_ffa_ids) {

  opt <- optimize_lineup(candidates, roster_slots)
  mm  <- simulate_matchup(opt$ffa_id, opponent_ffa_ids, draws_by_ffa)

  in_opt <- candidates$ffa_id %in% opt$ffa_id
  tibble(
    expected_points = mm$home_expected,        # == sum(opt$sim_mean) exactly
    p10 = mm$home_p10, p50 = mm$home_p50, p90 = mm$home_p90,
    win_probability = mm$home_win_probability,
    # ponytail: bench value = forecast points sitting on the bench; revisit if
    # FA/trade logic needs position-weighted depth
    bench_value = sum(candidates$sim_mean[!in_opt], na.rm = TRUE),
    optimal_lineup = list(opt)
  )
}
