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

# Consume one starting-slot instance per pinned (locked) player, matched to a
# slot the player is eligible for. Returns a roster_slots-shaped frame
# (lineup_slot_id, lineup_slot, count) with the remaining open slots, for
# optimize_lineup() to fill around the pins.
#
# Bipartite max matching (Kuhn's augmenting-path algorithm), not a one-pass
# greedy: a player with a "rarer" slot type available is not necessarily the
# only one who needs it (e.g. RB is the only one eligible for the plain RB
# slot but also competes for RB/WR with 3 WRs) - a pick that looks locally
# safest can starve a later player even though a full assignment exists.
# Small scale (<= roster size candidates x starting slots), so this is cheap.
.drop_pinned_slots <- function(roster_slots, pinned) {
  ss   <- .starting_slots(roster_slots)          # one row per open slot instance
  elig <- lapply(pinned$eligible_slot_ids, .parse_slot_ids)
  adj  <- lapply(elig, function(e) which(ss$lineup_slot_id %in% e))

  match_slot <- rep(NA_integer_, nrow(ss))   # slot index -> matched player index
  visited    <- logical(nrow(ss))

  augment <- function(i) {
    for (j in adj[[i]]) {
      if (visited[j]) next
      visited[j] <<- TRUE
      if (is.na(match_slot[j]) || augment(match_slot[j])) {
        match_slot[j] <<- i
        return(TRUE)
      }
    }
    FALSE
  }

  for (i in order(lengths(adj))) {   # most-constrained first: fewer augmenting paths
    visited <- logical(nrow(ss))
    if (!augment(i)) {
      stop("evaluate_roster: pinned (locked) player cannot fill any open starting slot",
           call. = FALSE)
    }
  }
  take <- !is.na(match_slot)
  ss[!take, , drop = FALSE] |> count(lineup_slot_id, lineup_slot, name = "count")
}

# candidates       : same shape as optimize_lineup() input (roster's startable
#                    players, already filtered of NA / injured by the caller).
# roster_slots     : espn_snap$roster_slots.
# draws_by_ffa     : named list character(ffa_id) -> numeric(n_sim).
# opponent_ffa_ids : integer vector, the opponent's current starters.
# pinned_ffa       : ffa_ids that MUST start in their eligible slot (locked
#                    players whose game has begun - cannot be moved).
# Returns a 1-row tibble: expected_points, p10/p50/p90, win_probability,
# bench_value, optimal_lineup (list-col with the optimize_lineup() tibble).
evaluate_roster <- function(candidates, roster_slots, draws_by_ffa,
                            opponent_ffa_ids, pinned_ffa = integer()) {

  pinned_ffa <- intersect(pinned_ffa, candidates$ffa_id[!is.na(candidates$ffa_id)])
  if (length(pinned_ffa) == 0L) {
    opt <- optimize_lineup(candidates, roster_slots)
  } else {
    pinned <- candidates |> filter(ffa_id %in% pinned_ffa)
    free   <- candidates |> filter(!ffa_id %in% pinned_ffa)
    remaining_slots <- .drop_pinned_slots(roster_slots, pinned)
    # pins alone can fill every starting slot (e.g. late in the week, most
    # games locked) - nothing left for optimize_lineup() to do, and it errors
    # on zero slots rather than treating that as "no-op".
    filled <- if (nrow(remaining_slots) == 0L) {
      tibble(lineup_slot_id = integer(), lineup_slot = character(),
             ffa_id = integer(), pos = character(), sim_mean = double(),
             player_name = character(), espn_id = integer())
    } else {
      optimize_lineup(free, remaining_slots)
    }
    opt <- bind_rows(
      pinned |> transmute(lineup_slot_id = NA_integer_, lineup_slot = NA_character_,
                          ffa_id, pos, sim_mean, player_name,
                          espn_id = as.integer(espn_id)),
      filled
    ) |>
      arrange(lineup_slot_id, desc(sim_mean))
  }
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
