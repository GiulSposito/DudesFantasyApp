# Decision engine - Phase 9: 1x1 trade recommendations (spec 24-28, 43).
#
# recommend_trades(): for each advised team (team_id = NULL means every team in the
# league - spec 43), score a bounded GIVE x RECEIVE grid of single-for-single swaps
# against every other team, and keep the ones that raise that team's expected
# points (spec 26) - preferring the ones that also help (or at least don't hurt)
# the partner (spec 26-27). recommendation_rank restarts at 1 per my_team_id.
#
# No new simulation - draws_by_ffa already covers every FFA-projected player, so a
# received player has a draw vector without re-simulating. evaluate_roster() is
# reused as-is; each team is scored against ITS OWN current-week opponent, held at
# that opponent's current ESPN starters (spec 41) - same convention as
# recommend_lineups() / recommend_free_agents().
#
# Three ranking scopes (docs/horizon_projections.md): week (W0, this week's
# Monte Carlo - recommendation_rank), future (W1..W3, ESPN weekly projections -
# rank_future) and horizon (W0..W3 - rank_horizon). A row is kept when it ranks
# in any scope; each scope has its own top_n. Future values are lineup means per
# target week (evaluate_roster_horizon()), no win probability. Bye players are
# excluded from the week scope only - in the others the bye is just a 0 week.
#
# ponytail: O(advised teams x partners) evaluate_roster() calls - W0 baselines
# are recomputed per advising team (the horizon baseline is cached per team).
# A few minutes for the whole league at n_sim=10000; memoise if that ever matters.
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
    my_delta_future = double(), my_delta_horizon = double(),
    their_delta_future = double(), their_delta_horizon = double(),
    my_before_win_probability = double(), my_after_win_probability = double(),
    my_delta_win_probability = double(),
    fairness = double(), trade_score = double(),
    partner_is_my_opponent = logical(),
    recommendation_rank = integer(),
    rank_future = integer(), rank_horizon = integer()
  )
}

# --- recommendations (spec 24-28) ---------------------------------------

# current_players : build_current_league_state() output (all teams).
# espn_snap       : select_espn_snapshot() output (needs $roster_slots, $matchups;
#                   optional $bye_teams, $horizon).
# draws_by_ffa    : named list character(ffa_id) -> numeric(n_sim).
# team_id         : ESPN team_id(s) to advise, or NULL for every team (spec 43).
# Returns up to top_n rows per scope PER advised team of the .empty_trade_recs()
# schema. Each scope ranks by its own score, delta_me + min(delta_me, delta_them)
# (trade_score for the week scope), with ranks restarting at 1 per team; a rank
# is NA where the row doesn't place in that scope. Without a horizon the future /
# horizon columns are NA and only recommendation_rank is set.
# (my_delta_win_probability is reported, not ranked on - MC-noisy, same choice
# recommend_lineups() / recommend_free_agents() make).
recommend_trades <- function(current_players, espn_snap, draws_by_ffa,
                             run_id, season, week, tag,
                             team_id             = NULL,
                             exclude_status      = "OUT",
                             max_give            = 5L,
                             max_receive_per_pos = 5L,
                             top_n               = 25L,
                             min_delta           = 1e-6,
                             min_their_delta     = 0,
                             locked_ffa          = integer()) {

  slots <- espn_snap$roster_slots
  if (!"is_locked" %in% names(current_players)) current_players$is_locked <- FALSE
  # players whose game has begun: cannot be given or received, must stay started
  locked_all <- union(as.integer(locked_ffa),
                      current_players$ffa_id[coalesce(current_players$is_locked, FALSE)])
  # pin only locked STARTERS (must stay in their slot); a locked BENCH player
  # can't be moved either but was never in the lineup, so it isn't pinned - it's
  # just excluded from the candidate pool below, same as recommend_lineups().
  pin_of <- function(base) intersect(locked_all, base$ffa_id[base$is_starter])
  # bye-week players forecast 0 this week - a one-week hole, not trade value:
  # kept out of the week scope (pools + ranking); the future / horizon scopes
  # see the bye as one 0 week among four.
  bye_ffa <- current_players$ffa_id[current_players$nfl_team %in% espn_snap$bye_teams]

  # W1..W3 (docs/horizon_projections.md)
  hz     <- espn_snap$horizon
  has_hz <- !is.null(hz) && nrow(hz) > 0L
  # future-weeks roster: every mapped, non-IR player - this week's OUT status and
  # game locks don't bind the next weeks. Baseline cached once per team.
  # ponytail: locked players stay out of the trade pools in every scope (only
  # bites late-week runs)
  h_base <- if (has_hz) {
    teams <- sort(unique(current_players$team_id))
    set_names(lapply(teams, function(t) {
      current_players |>
        filter(team_id == t, !is.na(ffa_id), !is_ir) |>
        select(ffa_id, pos, sim_mean, eligible_slot_ids, player_name, espn_id)
    }), teams)
  }
  h_before <- if (has_hz) {
    vapply(h_base, evaluate_roster_horizon, numeric(1), roster_slots = slots, horizon = hz)
  }
  # team t's future-weeks delta when out_id leaves and in_id (from team in_t) arrives
  h_delta <- function(t, out_id, in_t, in_id) {
    if (!has_hz) return(NA_real_)
    b    <- h_base[[as.character(t)]]
    from <- h_base[[as.character(in_t)]]
    evaluate_roster_horizon(bind_rows(b[b$espn_id != out_id, ], from[from$espn_id == in_id, ]),
                            slots, hz) - h_before[[as.character(t)]]
  }

  # bidirectional team -> opponent map (spec 41) - same as recommend_lineups()
  mu  <- espn_snap$matchups |> distinct(home_team_id, away_team_id)
  opp <- bind_rows(
    transmute(mu, team_id = home_team_id, opponent_team_id = away_team_id),
    transmute(mu, team_id = away_team_id, opponent_team_id = home_team_id)
  )

  starters_ffa <- function(t) {
    current_players$ffa_id[current_players$team_id == t &
                             current_players$is_starter &
                             !is.na(current_players$ffa_id)]
  }

  # roster's startable players - same filter + one-time relax as recommend_lineups()
  base_roster <- function(t) {
    my    <- current_players |> filter(team_id == t)
    valid <- my |> filter(!is.na(ffa_id), !is.na(sim_mean), !is_ir)
    # a locked player can't be moved regardless of injury status, so
    # exclude_status only screens candidates that could still be swapped
    # (same fix as recommend_lineups()).
    b <- valid |> filter(ffa_id %in% locked_all | !injury_status %in% exclude_status)
    # locked bench players can't be inserted into the lineup this week either -
    # drop them from consideration, same as recommend_lineups().
    tlocked <- intersect(locked_all, b$ffa_id)
    b <- b |> filter(!(ffa_id %in% tlocked & !is_starter))
    b |> select(ffa_id, pos, position, sim_mean, eligible_slot_ids,
                player_name, espn_id, is_starter) |>
      # per-player value in each scope, for picking the candidate pools
      mutate(fut = .future_points(espn_id, hz), hzv = sim_mean + fut)
  }

  has_draws <- function(x) as.character(x) %in% names(draws_by_ffa)

  # starting-slot ids only - the bench (20) / IR (21) slots sit in every player's
  # eligible_slot_ids, so "shares a slot" must be tested against the slots that
  # actually start (spec 16). give x receive is a candidate only if both players
  # can fill a common starting slot (flex-compatible; QB<->QB, K<->K, DST<->DST).
  start_slot_ids <- unique(.starting_slots(slots)$lineup_slot_id)
  start_elig <- function(x) intersect(.parse_slot_ids(x), start_slot_ids)

  # --- per-team recommender (spec 43: run for one team or the whole league) --
  advise_team <- function(tid) {
  tid <- as.integer(tid)
  my_opp <- opp$opponent_team_id[opp$team_id == tid]
  if (length(my_opp) != 1L) {
    warning(glue::glue("team {tid}: no unique opponent this week; no trade recs"),
            call. = FALSE)
    return(.empty_trade_recs())
  }

  # --- my baseline ---------------------------------------------------------
  my_base    <- base_roster(tid)
  my_opp_ffa <- starters_ffa(my_opp)
  my_pin     <- pin_of(my_base)
  my_before  <- evaluate_roster(my_base, slots, draws_by_ffa, my_opp_ffa, pinned_ffa = my_pin)
  n_before_me <- nrow(my_before$optimal_lineup[[1]])

  # GIVE pool: the max_give weakest movable players (you trade from surplus, and
  # a strong player rarely nets delta_me > 0 anyway) in each scope, unioned.
  # ~max_give x ~13 partners x max_receive_per_pos evaluate_roster() calls per
  # advised team and scope. Widen max_give / max_receive_per_pos if the surplus
  # heuristic misses a good trade.
  movable   <- my_base |> filter(has_draws(ffa_id), !ffa_id %in% locked_all)
  give_pool <- bind_rows(
    movable |> filter(!ffa_id %in% bye_ffa) |> arrange(sim_mean) |> head(max_give),
    if (has_hz) movable |> arrange(fut) |> head(max_give),
    if (has_hz) movable |> arrange(hzv) |> head(max_give)
  ) |>
    distinct(ffa_id, .keep_all = TRUE)
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
    p_pin      <- pin_of(p_base)
    p_before   <- evaluate_roster(p_base, slots, draws_by_ffa, p_opp_ffa, pinned_ffa = p_pin)
    n_before_them <- nrow(p_before$optimal_lineup[[1]])

    recv_all <- p_base |> filter(has_draws(ffa_id), !ffa_id %in% locked_all)
    if (nrow(recv_all) == 0L) next

    for (gi in seq_len(nrow(give_pool))) {
      g    <- give_pool[gi, ]
      gset <- give_slots[[gi]]

      # RECEIVE candidates: shares an eligible slot with the give player
      # (flex-compatible); per scope, a strict upgrade in that scope's value, top
      # max_receive_per_pos per position; unioned across scopes
      g_bye <- g$ffa_id %in% bye_ffa
      ok    <- recv_all |>
        filter(map_lgl(eligible_slot_ids, ~ length(intersect(start_elig(.x), gset)) > 0))
      top   <- function(d, v) {
        d |> group_by(pos) |>
          slice_max({{ v }}, n = max_receive_per_pos, with_ties = FALSE) |>
          ungroup()
      }
      recv <- bind_rows(
        if (!g_bye) top(filter(ok, !ffa_id %in% bye_ffa, sim_mean > g$sim_mean), sim_mean),
        if (has_hz) top(filter(ok, fut > g$fut), fut),
        if (has_hz) top(filter(ok, hzv > g$hzv), hzv)
      )
      if (nrow(recv) == 0L) next
      recv <- recv |> distinct(ffa_id, .keep_all = TRUE)

      my_kept <- my_base |> filter(ffa_id != g$ffa_id)

      for (ri in seq_len(nrow(recv))) {
        r <- recv[ri, ]

        my_cand  <- bind_rows(my_kept, p_base |> filter(ffa_id == r$ffa_id))
        my_after <- suppressWarnings(
          evaluate_roster(my_cand, slots, draws_by_ffa, my_opp_ffa, pinned_ffa = my_pin))
        if (nrow(my_after$optimal_lineup[[1]]) < n_before_me) next   # roster went illegal (spec 21)

        d_me   <- my_after$expected_points - my_before$expected_points
        is_bye <- g_bye || r$ffa_id %in% bye_ffa
        f_me   <- h_delta(tid, g$espn_id, pt, r$espn_id)
        # spec 26 hard rule, per scope: skip unless my side gains in at least one
        if (max(c(if (!is_bye) d_me, if (has_hz) c(f_me, d_me + f_me), -Inf)) <= min_delta) next

        their_cand  <- bind_rows(p_base |> filter(ffa_id != r$ffa_id),
                                 my_base |> filter(ffa_id == g$ffa_id))
        their_after <- suppressWarnings(
          evaluate_roster(their_cand, slots, draws_by_ffa, p_opp_ffa, pinned_ffa = p_pin))
        if (nrow(their_after$optimal_lineup[[1]]) < n_before_them) next

        d_them <- their_after$expected_points - p_before$expected_points
        f_them <- h_delta(pt, r$espn_id, tid, g$espn_id)

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
          my_delta_future     = f_me,   my_delta_horizon    = d_me + f_me,
          their_delta_future  = f_them, their_delta_horizon = d_them + f_them,
          my_before_win_probability = my_before$win_probability,
          my_after_win_probability  = my_after$win_probability,
          my_delta_win_probability  = my_after$win_probability - my_before$win_probability,
          fairness    = -abs(d_me - d_them),
          trade_score = d_me + pmin(d_me, d_them),
          partner_is_my_opponent = (as.integer(pt) == as.integer(my_opp)),
          .bye = is_bye
        )
      }
    }
  }

  if (length(rows) == 0L) return(.empty_trade_recs())

  # per scope: one row per received player (the receive is the real decision, the
  # give is the move that realises it - mirrors recommend_free_agents()' per-add
  # dedup), ranked by delta_me + min(delta_me, delta_them) (= trade_score in the
  # week scope), top_n. The three ranks land on the same rows - (give, receive)
  # is unique within one advised team.
  all <- bind_rows(rows)
  ranked <- function(d, my, their, col) {
    d |>
      filter(.data[[my]] > min_delta, .data[[their]] >= min_their_delta) |>
      arrange(desc(.data[[my]] + pmin(.data[[my]], .data[[their]])), desc(.data[[my]]),
              give_ffa_id, receive_ffa_id) |>
      distinct(receive_player_id, .keep_all = TRUE) |>
      head(top_n) |>
      transmute(give_player_id, receive_player_id, !!col := row_number())
  }
  k <- c("give_player_id", "receive_player_id")
  out <- all |>
    left_join(ranked(filter(all, !.bye), "my_delta_expected", "their_delta_expected",
                     "recommendation_rank"), by = k) |>
    left_join(ranked(all, "my_delta_future", "their_delta_future", "rank_future"), by = k) |>
    left_join(ranked(all, "my_delta_horizon", "their_delta_horizon", "rank_horizon"), by = k) |>
    filter(!is.na(recommendation_rank) | !is.na(rank_future) | !is.na(rank_horizon)) |>
    arrange(recommendation_rank, rank_horizon, rank_future) |>
    select(all_of(names(.empty_trade_recs())))

  if (nrow(out) == 0L) .empty_trade_recs() else out
  }

  advisors <- if (is.null(team_id)) {
    sort(unique(as.integer(current_players$team_id)))
  } else {
    as.integer(team_id)
  }

  out <- bind_rows(lapply(advisors, advise_team))
  if (nrow(out) == 0L) .empty_trade_recs() else out
}
