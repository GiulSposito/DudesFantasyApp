# Decision engine - Phase 6: lineup optimizer (spec 16, 16.1) + lineup
# recommendation (spec 17).
#
# optimize_lineup() finds the best legal starting lineup for a roster, maximising
# sum(sim_mean) subject to the ESPN slot rules. Slot counts AND per-player slot
# eligibility come from the ESPN data (spec 16: never hard-code QB/RB/WR/...
# counts) - `espn_roster_slots` for the open slots, each player's
# `eligible_slot_ids` for what they can fill.
#
# No LP solver is installed and the project resists adding one; the problem is
# tiny (9 slots, ~15 candidates), so this is an exact recursive assignment with
# branch-and-bound. Deterministic: candidates carry a total order (sim_mean then
# ffa_id) so ties never depend on input row order.
#
# Objective 2 (spec 16.2, maximise P(win)) is deferred past Milestone 3 - the M3
# acceptance only needs P(win) *reported* for the current and the max-EV lineup.

library(tidyverse)

if (!exists("simulate_matchup")) source("./R/decision/matchup_simulation.R")

# "2,3,23" -> c(2L, 3L, 23L); "" / NA -> integer(0)
.parse_slot_ids <- function(x) {
  if (length(x) != 1L || is.na(x) || !nzchar(x)) return(integer())
  as.integer(strsplit(x, ",", fixed = TRUE)[[1]])
}

# open starting slots from espn_roster_slots, one row per slot instance (spec 16)
.starting_slots <- function(roster_slots) {
  roster_slots |>
    filter(count > 0, !lineup_slot %in% c("BE", "IR")) |>
    select(lineup_slot_id, lineup_slot, count) |>
    tidyr::uncount(count)
}

# --- optimizer -------------------------------------------------------------

# candidates : tibble, one row per roster player that MAY start. Required cols:
#   ffa_id, pos, sim_mean, eligible_slot_ids, player_name, espn_id.
#   The caller drops NA ffa_id / NA sim_mean and injured players first.
# roster_slots : espn_snap$roster_slots (already season-filtered).
# Returns one row per FILLED starting slot: lineup_slot_id, lineup_slot, ffa_id,
# pos, sim_mean, player_name, espn_id - ordered by lineup_slot_id, desc(sim_mean).
optimize_lineup <- function(candidates, roster_slots) {

  slots  <- .starting_slots(roster_slots)
  n_slot <- nrow(slots)
  if (n_slot == 0L) stop("optimize_lineup: no open starting slots", call. = FALSE)

  cand <- candidates |>
    filter(!is.na(ffa_id), !is.na(sim_mean)) |>
    arrange(desc(sim_mean), ffa_id)          # total order -> deterministic ties
  if (nrow(cand) == 0L) {
    stop("optimize_lineup: no candidates with a forecast", call. = FALSE)
  }

  elig <- lapply(cand$eligible_slot_ids, .parse_slot_ids)
  # rows eligible for each slot instance, then reorder slots most-constrained-first
  slot_cands <- lapply(slots$lineup_slot_id, function(sid) {
    which(vapply(elig, function(e) sid %in% e, logical(1)))
  })
  ord        <- order(lengths(slot_cands))   # stable: identical slot types stay adjacent
  slots      <- slots[ord, ]
  slot_cands <- slot_cands[ord]

  sm   <- cand$sim_mean
  topk <- c(0, cumsum(sm))                   # topk[k + 1] = sum of the k largest sim_mean
  bound_after <- function(i) topk[min(n_slot - i + 1L, length(sm)) + 1L]

  best <- list(val = -Inf, pick = NULL)

  rec <- function(i, used, val, picks) {
    if (i > n_slot) {
      if (val > best$val) best <<- list(val = val, pick = picks)
      return(invisible())
    }
    if (val + bound_after(i) <= best$val) return(invisible())   # branch-and-bound

    rows <- slot_cands[[i]]
    rows <- rows[!used[rows]]
    # symmetry cut: consecutive identical slot types are interchangeable
    if (i > 1L && slots$lineup_slot_id[i] == slots$lineup_slot_id[i - 1L]) {
      rows <- rows[rows > picks[i - 1L]]
    }
    for (r in rows) {
      used[r] <- TRUE
      rec(i + 1L, used, val + sm[r], c(picks, r))
      used[r] <- FALSE
    }
  }
  rec(1L, logical(nrow(cand)), 0, integer())

  if (is.infinite(best$val)) {
    # short bench / exclusions leave a slot unfillable - greedy partial, don't stop
    warning("optimize_lineup: roster cannot fill every slot; returning partial lineup",
            call. = FALSE)
    used  <- logical(nrow(cand))
    picks <- rep(NA_integer_, n_slot)
    for (i in seq_len(n_slot)) {
      free <- slot_cands[[i]][!used[slot_cands[[i]]]]
      if (length(free)) { picks[i] <- free[1L]; used[free[1L]] <- TRUE }
    }
    sel <- picks
  } else {
    sel <- best$pick
  }

  keep <- !is.na(sel)
  tibble(
    lineup_slot_id = slots$lineup_slot_id[keep],
    lineup_slot    = slots$lineup_slot[keep],
    ffa_id         = cand$ffa_id[sel[keep]],
    pos            = cand$pos[sel[keep]],
    sim_mean       = cand$sim_mean[sel[keep]],
    player_name    = cand$player_name[sel[keep]],
    espn_id        = cand$espn_id[sel[keep]]
  ) |>
    arrange(lineup_slot_id, desc(sim_mean))
}

# greedy "top-k per position + best flex" - NOT used in production, kept as the
# test oracle for the single-flex case (provably optimal there).
.optimize_lineup_greedy <- function(candidates, roster_slots) {
  slots <- .starting_slots(roster_slots)
  cand  <- candidates |> filter(!is.na(ffa_id), !is.na(sim_mean)) |>
    arrange(desc(sim_mean), ffa_id)
  cand$e <- lapply(cand$eligible_slot_ids, .parse_slot_ids)
  used <- logical(nrow(cand)); out <- integer()
  # fixed (single-position-eligible) slots first, then flex slots
  slot_ids <- slots$lineup_slot_id
  n_elig   <- vapply(slot_ids, function(sid) sum(vapply(cand$e, function(e) sid %in% e, logical(1))), integer(1))
  for (sid in slot_ids[order(n_elig)]) {
    r <- which(!used & vapply(cand$e, function(e) sid %in% e, logical(1)))
    if (length(r)) { used[r[1]] <- TRUE; out <- c(out, r[1]) }
  }
  cand[out, ] |> transmute(ffa_id, pos, sim_mean, player_name, espn_id) |>
    arrange(desc(sim_mean))
}

# --- lineup recommendation (spec 17, 41) ---------------------------------

.empty_lineup_recs <- function() {
  tibble(
    run_id = character(), season = integer(), week = integer(), tag = character(),
    team_id = integer(),
    player_out = integer(), player_in = integer(),
    player_out_name = character(), player_in_name = character(),
    slot = character(),
    current_expected = double(), optimized_expected = double(),
    delta_expected = double(),
    current_win_probability = double(), optimized_win_probability = double(),
    delta_win_probability = double(),
    recommendation_rank = integer()
  )
}

# current_players : build_current_league_state() output.
# espn_snap       : select_espn_snapshot() output (needs $roster_slots, $matchups).
# draws_by_ffa    : named list character(ffa_id) -> numeric(n_sim).
# Returns list(evaluations = 1 row/team, recommendations = 0+ rows/team, spec 17).
#
# Each team is optimised on its own, with the opponent held at their CURRENT ESPN
# starters (spec 41). "optimal P(win)" is NOT guaranteed >= "current P(win)": a
# higher-mean lineup can match up worse against a specific opponent. Only
# expected points is monotone.
recommend_lineups <- function(current_players, espn_snap, draws_by_ffa,
                              run_id, season, week, tag,
                              exclude_status = "OUT", locked_ffa = integer()) {

  if (!exists("evaluate_roster")) source("./R/decision/roster_evaluator.R")

  slots <- espn_snap$roster_slots
  if (!"is_locked" %in% names(current_players)) current_players$is_locked <- FALSE
  locked_of <- function(df) df$ffa_id[coalesce(df$is_locked, FALSE) | df$ffa_id %in% locked_ffa]

  mu  <- espn_snap$matchups |> distinct(home_team_id, away_team_id)
  opp <- bind_rows(
    transmute(mu, team_id = home_team_id, opponent_team_id = away_team_id),
    transmute(mu, team_id = away_team_id, opponent_team_id = home_team_id)
  )

  starters_ffa <- function(tid) {
    current_players$ffa_id[current_players$team_id == tid &
                             current_players$is_starter &
                             !is.na(current_players$ffa_id)]
  }

  evals <- list()
  recs  <- list()

  for (t in sort(unique(current_players$team_id))) {
    ot <- opp$opponent_team_id[opp$team_id == t]
    if (length(ot) != 1L) {
      warning(glue::glue("team {t}: no unique opponent this week; skipped"),
              call. = FALSE)
      next
    }
    opp_ffa <- starters_ffa(ot)
    cur_ffa <- starters_ffa(t)

    cand <- current_players |>
      filter(team_id == t, !is.na(ffa_id), !is.na(sim_mean),
             !is_ir, !injury_status %in% exclude_status)
    # relax injury exclusion once if it leaves the roster short (spec: never fail
    # a run over injuries)
    if (nrow(cand) < length(cur_ffa)) {
      cand <- current_players |>
        filter(team_id == t, !is.na(ffa_id), !is.na(sim_mean), !is_ir)
    }
    # a locked player whose game has begun cannot be moved: drop locked bench
    # players from consideration, pin locked starters into the lineup.
    tlocked <- locked_of(cand)
    cand    <- cand |> filter(!(ffa_id %in% tlocked & !is_starter))
    pin_t   <- intersect(tlocked, cand$ffa_id[cand$is_starter])

    cur_mm <- simulate_matchup(cur_ffa, opp_ffa, draws_by_ffa)
    ev     <- evaluate_roster(cand, slots, draws_by_ffa, opp_ffa, pinned_ffa = pin_t)
    opt    <- ev$optimal_lineup[[1]]

    evals[[length(evals) + 1L]] <- tibble(
      run_id = run_id,
      season = as.integer(season), week = as.integer(week), tag = tag,
      team_id = as.integer(t), opponent_team_id = as.integer(ot),
      current_expected        = cur_mm$home_expected,
      current_p10 = cur_mm$home_p10, current_p50 = cur_mm$home_p50,
      current_p90 = cur_mm$home_p90,
      current_win_probability = cur_mm$home_win_probability,
      optimal_expected        = ev$expected_points,
      optimal_p10 = ev$p10, optimal_p50 = ev$p50, optimal_p90 = ev$p90,
      optimal_win_probability = ev$win_probability,
      bench_value             = ev$bench_value,
      n_substitutions         = length(setdiff(cur_ffa, opt$ffa_id))
    )

    # locked players can't be swapped (pinning already prevents it; guard anyway)
    outs <- setdiff(setdiff(cur_ffa, opt$ffa_id), tlocked)
    ins  <- setdiff(setdiff(opt$ffa_id, cur_ffa), tlocked)
    if (length(outs) > 0L && length(outs) == length(ins)) {
      cp  <- current_players |> filter(team_id == t)
      nm  <- function(f) cp$player_name[match(f, cp$ffa_id)]
      eid <- function(f) as.integer(cp$espn_id[match(f, cp$ffa_id)])
      sm  <- function(f) cp$sim_mean[match(f, cp$ffa_id)]

      o <- outs[order(-sm(outs))]
      i <- ins[order(-sm(ins))]
      recs[[length(recs) + 1L]] <- tibble(
        run_id = run_id,
        season = as.integer(season), week = as.integer(week), tag = tag,
        team_id = as.integer(t),
        player_out = eid(o), player_in = eid(i),
        player_out_name = nm(o), player_in_name = nm(i),
        slot = opt$lineup_slot[match(i, opt$ffa_id)],
        current_expected          = cur_mm$home_expected,
        optimized_expected        = ev$expected_points,
        delta_expected            = ev$expected_points - cur_mm$home_expected,
        current_win_probability   = cur_mm$home_win_probability,
        optimized_win_probability = ev$win_probability,
        delta_win_probability     = ev$win_probability - cur_mm$home_win_probability,
        .marginal = sm(i) - sm(o)
      ) |>
        arrange(desc(.marginal)) |>
        mutate(recommendation_rank = row_number()) |>
        select(-.marginal)
    }
  }

  list(
    evaluations     = bind_rows(evals),
    recommendations = if (length(recs)) bind_rows(recs) else .empty_lineup_recs()
  )
}
