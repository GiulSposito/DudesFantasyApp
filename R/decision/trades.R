# Decision engine - Phase 9: 1x1 trade recommendations (spec 24-28, 43).
#
# recommend_trades(): for one team, score a bounded GIVE x RECEIVE grid of single-
# for-single swaps against every other team, and keep the ones that raise my
# roster's expected points (spec 26) - preferring the ones that also help (or at
# least don't hurt) the partner (spec 26-27).
#
# No new simulation - draws_by_ffa already covers every FFA-projected player, so a
# received player has a draw vector without re-simulating. evaluate_roster() is
# reused as-is; each team is scored against ITS OWN current-week opponent, held at
# that opponent's current ESPN starters (spec 41) - same convention as
# recommend_lineups() / recommend_free_agents().
#
# ponytail: when the trade partner IS my week's matchup opponent, my_*_win_probability
# is optimistic - the received player is counted in my simulated matchup on both
# sides (mine, and the opponent's held lineup). my_delta_expected / trade_score /
# rank are unaffected (lineup value is opponent-independent). Flagged per row with
# partner_is_my_opponent; exclude those rows if win-prob accuracy matters.

library(tidyverse)

if (!exists("evaluate_roster"))    source("./R/decision/roster_evaluator.R")
if (!exists("bridge_espn_to_ffa")) source("./R/decision/league_state.R")
# .parse_slot_ids() / .starting_slots() come from lineup_optimizer.R, sourced by
# roster_evaluator.R

# --- output template (spec 28, M3/M4 house style) -------------------------

.empty_trade_recs <- function() {
  tibble(
    run_id = character(), season = integer(), week = integer(), tag = character(),
    my_team_id = integer(), other_team_id = integer(),
    give_player_id = integer(), give_ffa_id = integer(),
    receive_player_id = integer(), receive_ffa_id = integer(),
    give_position = character(), receive_position = character(),
    my_before_expected = double(), my_after_expected = double(),
    my_delta_expected = double(),
    their_before_expected = double(), their_after_expected = double(),
    their_delta_expected = double(),
    my_before_win_probability = double(), my_after_win_probability = double(),
    my_delta_win_probability = double(),
    fairness = double(), trade_score = double(),
    partner_is_my_opponent = logical(),
    recommendation_rank = integer()
  )
}

# --- recommendations (spec 24-28) ---------------------------------------

# current_players : build_current_league_state() output (all teams).
# espn_snap       : select_espn_snapshot() output (needs $roster_slots, $matchups).
# draws_by_ffa    : named list character(ffa_id) -> numeric(n_sim).
# team_id         : the ESPN team_id to advise (spec 43, one team).
# Returns 0..top_n rows of the .empty_trade_recs() schema, ranked by trade_score
# desc (my_delta_win_probability is reported, not ranked on - MC-noisy, same
# choice recommend_lineups() / recommend_free_agents() make).
recommend_trades <- function(current_players, espn_snap, draws_by_ffa,
                             run_id, season, week, tag,
                             team_id,
                             exclude_status      = "OUT",
                             max_give            = 5L,
                             max_receive_per_pos = 5L,
                             top_n               = 25L,
                             min_delta           = 1e-6,
                             min_their_delta     = 0) {

  slots <- espn_snap$roster_slots
  tid   <- as.integer(team_id)

  # bidirectional team -> opponent map (spec 41) - same as recommend_lineups()
  mu  <- espn_snap$matchups |> distinct(home_team_id, away_team_id)
  opp <- bind_rows(
    transmute(mu, team_id = home_team_id, opponent_team_id = away_team_id),
    transmute(mu, team_id = away_team_id, opponent_team_id = home_team_id)
  )
  my_opp <- opp$opponent_team_id[opp$team_id == tid]
  if (length(my_opp) != 1L) {
    warning(glue::glue("team {tid}: no unique opponent this week; no trade recs"),
            call. = FALSE)
    return(.empty_trade_recs())
  }

  starters_ffa <- function(t) {
    current_players$ffa_id[current_players$team_id == t &
                             current_players$is_starter &
                             !is.na(current_players$ffa_id)]
  }

  # roster's startable players - same filter + one-time relax as recommend_lineups()
  base_roster <- function(t) {
    my <- current_players |> filter(team_id == t)
    b  <- my |> filter(!is.na(ffa_id), !is.na(sim_mean), !is_ir,
                       !injury_status %in% exclude_status)
    if (nrow(b) < sum(my$is_starter, na.rm = TRUE)) {
      b <- my |> filter(!is.na(ffa_id), !is.na(sim_mean), !is_ir)
    }
    b |> select(ffa_id, pos, position, sim_mean, eligible_slot_ids,
                player_name, espn_id)
  }

  has_draws <- function(x) as.character(x) %in% names(draws_by_ffa)

  # starting-slot ids only - the bench (20) / IR (21) slots sit in every player's
  # eligible_slot_ids, so "shares a slot" must be tested against the slots that
  # actually start (spec 16). give x receive is a candidate only if both players
  # can fill a common starting slot (flex-compatible; QB<->QB, K<->K, DST<->DST).
  start_slot_ids <- unique(.starting_slots(slots)$lineup_slot_id)
  start_elig <- function(x) intersect(.parse_slot_ids(x), start_slot_ids)

  # --- my baseline ---------------------------------------------------------
  my_base    <- base_roster(tid)
  my_opp_ffa <- starters_ffa(my_opp)
  my_before  <- evaluate_roster(my_base, slots, draws_by_ffa, my_opp_ffa)
  n_before_me <- nrow(my_before$optimal_lineup[[1]])

  # GIVE pool: the max_give weakest movable players (you trade from surplus, and
  # a strong player rarely nets delta_me > 0 anyway). ponytail: ~max_give x 13
  # partners x max_receive_per_pos evaluate_roster() calls (~a few hundred, a few
  # seconds at n_sim=10000). Widen max_give / max_receive_per_pos if the surplus
  # heuristic misses a good trade.
  give_pool <- my_base |>
    filter(has_draws(ffa_id)) |>
    arrange(sim_mean) |>
    head(max_give)
  if (nrow(give_pool) == 0L) return(.empty_trade_recs())
  give_slots <- lapply(give_pool$eligible_slot_ids, start_elig)

  partners <- setdiff(sort(unique(current_players$team_id)), tid)

  rows <- list()
  for (pt in partners) {
    p_opp <- opp$opponent_team_id[opp$team_id == pt]
    if (length(p_opp) != 1L) {
      warning(glue::glue("team {pt}: no unique opponent this week; skipped as trade partner"),
              call. = FALSE)
      next
    }

    p_base     <- base_roster(pt)
    p_opp_ffa  <- starters_ffa(p_opp)
    p_before   <- evaluate_roster(p_base, slots, draws_by_ffa, p_opp_ffa)
    n_before_them <- nrow(p_before$optimal_lineup[[1]])

    recv_all <- p_base |> filter(has_draws(ffa_id))
    if (nrow(recv_all) == 0L) next

    for (gi in seq_len(nrow(give_pool))) {
      g    <- give_pool[gi, ]
      gset <- give_slots[[gi]]

      # RECEIVE candidates: strict upgrade, shares an eligible slot with the give
      # player (flex-compatible), top max_receive_per_pos per position
      recv <- recv_all |>
        filter(sim_mean > g$sim_mean,
               map_lgl(eligible_slot_ids,
                       ~ length(intersect(start_elig(.x), gset)) > 0)) |>
        group_by(pos) |>
        slice_max(sim_mean, n = max_receive_per_pos, with_ties = FALSE) |>
        ungroup()
      if (nrow(recv) == 0L) next

      my_kept <- my_base |> filter(ffa_id != g$ffa_id)

      for (ri in seq_len(nrow(recv))) {
        r <- recv[ri, ]

        my_cand  <- bind_rows(my_kept, p_base |> filter(ffa_id == r$ffa_id))
        my_after <- suppressWarnings(
          evaluate_roster(my_cand, slots, draws_by_ffa, my_opp_ffa))
        if (nrow(my_after$optimal_lineup[[1]]) < n_before_me) next   # roster went illegal (spec 21)

        d_me <- my_after$expected_points - my_before$expected_points
        if (d_me <= min_delta) next                                  # spec 26 hard rule

        their_cand  <- bind_rows(p_base |> filter(ffa_id != r$ffa_id),
                                 my_base |> filter(ffa_id == g$ffa_id))
        their_after <- suppressWarnings(
          evaluate_roster(their_cand, slots, draws_by_ffa, p_opp_ffa))
        if (nrow(their_after$optimal_lineup[[1]]) < n_before_them) next

        d_them <- their_after$expected_points - p_before$expected_points

        rows[[length(rows) + 1L]] <- tibble(
          run_id  = run_id,
          season  = as.integer(season), week = as.integer(week), tag = tag,
          my_team_id    = tid, other_team_id = as.integer(pt),
          give_player_id    = as.integer(g$espn_id), give_ffa_id    = as.integer(g$ffa_id),
          receive_player_id = as.integer(r$espn_id), receive_ffa_id = as.integer(r$ffa_id),
          give_position    = g$position, receive_position = r$position,
          my_before_expected = my_before$expected_points,
          my_after_expected  = my_after$expected_points,
          my_delta_expected  = d_me,
          their_before_expected = p_before$expected_points,
          their_after_expected  = their_after$expected_points,
          their_delta_expected  = d_them,
          my_before_win_probability = my_before$win_probability,
          my_after_win_probability  = my_after$win_probability,
          my_delta_win_probability  = my_after$win_probability - my_before$win_probability,
          fairness    = -abs(d_me - d_them),
          trade_score = d_me + pmin(d_me, d_them),
          partner_is_my_opponent = (as.integer(pt) == as.integer(my_opp))
        )
      }
    }
  }

  if (length(rows) == 0L) return(.empty_trade_recs())

  # one row per received player: the receive is the real decision, the give is the
  # move that realises it (mirrors recommend_free_agents()' per-add dedup).
  out <- bind_rows(rows) |>
    filter(my_delta_expected > min_delta,
           their_delta_expected >= min_their_delta) |>
    arrange(desc(trade_score), desc(my_delta_expected), give_ffa_id, receive_ffa_id) |>
    distinct(receive_player_id, .keep_all = TRUE) |>
    mutate(recommendation_rank = row_number()) |>
    head(top_n)

  if (nrow(out) == 0L) .empty_trade_recs() else out
}
