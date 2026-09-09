# Decision engine - Phase 8: free agent add/drop recommendations (spec 13, 19-22).
#
# get_free_agents()      : espn_players ANTI JOIN espn_rosters for the snapshot,
#                          bridged to ffa_id, kept only if it carries a forecast
#                          and is not IR/inactive (spec 13, 21).
# recommend_free_agents(): for one team, score a bounded DROP x ADD grid with
#                          evaluate_roster() and keep the pairs that raise
#                          expected points (spec 19-22, 42).
#
# No new simulation - draws_by_ffa / player_forecasts already cover every
# FFA-projected player, free agents included. evaluate_roster() is reused as-is;
# the opponent is held at its current ESPN starters (spec 41), same as
# recommend_lineups().

library(tidyverse)

if (!exists("evaluate_roster"))      source("./R/decision/roster_evaluator.R")
if (!exists("bridge_espn_to_ffa"))   source("./R/decision/league_state.R")

# --- free agent pool (spec 13) ---------------------------------------------

# position -> canonical eligible_slot_ids string. espn_players carries no slot
# eligibility, so take the most common string seen for that position among the
# snapshot's roster rows.
.fa_slot_map <- function(rosters) {
  rosters |>
    filter(!is.na(eligible_slot_ids), nzchar(eligible_slot_ids)) |>
    count(position, eligible_slot_ids, name = "n") |>
    group_by(position) |>
    slice_max(n, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(position, eligible_slot_ids)
}

# espn_snap  : select_espn_snapshot() output (uses $players, $rosters, $injury).
# player_forecasts : the run's summarise_forecasts() output.
# Returns one row per addable free agent, sorted desc(sim_mean).
get_free_agents <- function(espn_snap, player_forecasts, analytical_db, ffa_db,
                            min_sim_mean = 0,
                            exclude_status = c("OUT", "IR", "DOUBTFUL")) {

  raw <- espn_snap$players |>
    mutate(player_id = as.integer(player_id)) |>
    anti_join(distinct(espn_snap$rosters, player_id), by = "player_id")

  n_raw <- nrow(raw)

  bridged <- bridge_espn_to_ffa(raw, analytical_db, ffa_db)

  fc <- player_forecasts |>
    select(ffa_id, pos, projection, sim_mean, p10, p50, p90, coverage_class)

  inj <- espn_snap$injury
  if (nrow(inj) > 0L) {
    inj <- inj |> select(player_id, inj_status = injury_status, injured, active)
  } else {
    inj <- tibble(player_id = integer(), inj_status = character(),
                  injured = logical(), active = logical())
  }

  slot_map <- .fa_slot_map(espn_snap$rosters)

  out <- bridged |>
    left_join(inj, by = "player_id") |>
    left_join(fc, by = "ffa_id") |>
    left_join(slot_map, by = "position") |>
    transmute(
      season = as.integer(espn_snap$season),
      week   = as.integer(espn_snap$week),
      tag    = espn_snap$tag,
      player_id, ffa_id,
      position,
      pos,
      player_name,
      eligible_slot_ids,
      projection, sim_mean, p10, p50, p90, coverage_class,
      injury_status = inj_status, injured, active,
      bridge_method
    ) |>
    filter(
      !is.na(ffa_id), !is.na(sim_mean), !is.na(eligible_slot_ids),
      sim_mean >= min_sim_mean,
      !(injury_status %in% exclude_status),
      !(injured %in% TRUE), !(active %in% FALSE)
    ) |>
    arrange(desc(sim_mean))

  n_drop <- n_raw - nrow(out)
  if (n_drop > 0L) {
    warning(glue::glue(
      "{n_drop} of {n_raw} unrostered ESPN players dropped from the free agent pool ",
      "(no ffa_id / no forecast / IR / inactive)"
    ), call. = FALSE)
  }

  out
}

# --- add/drop recommendations (spec 19-22) --------------------------------

.empty_fa_recs <- function() {
  tibble(
    run_id = character(), season = integer(), week = integer(), tag = character(),
    team_id = integer(),
    drop_player_id = integer(), drop_ffa_id = integer(),
    add_player_id  = integer(), add_ffa_id  = integer(),
    drop_position = character(), add_position = character(),
    before_expected = double(), after_expected = double(), delta_expected = double(),
    before_win_probability = double(), after_win_probability = double(),
    delta_win_probability  = double(),
    recommendation_rank = integer()
  )
}

# current_players : build_current_league_state() output.
# free_agents     : get_free_agents() output.
# espn_snap       : select_espn_snapshot() output (needs $roster_slots, $matchups).
# draws_by_ffa    : named list character(ffa_id) -> numeric(n_sim).
# team_id         : the ESPN team_id to advise (spec 42, one team).
# Returns 0..top_n rows of the spec-22 free_agent_recommendations schema, ranked
# by delta_expected desc (delta_win_probability is reported, not ranked on - it
# is MC-noisy, same choice recommend_lineups() makes).
recommend_free_agents <- function(current_players, free_agents, espn_snap,
                                  draws_by_ffa, run_id, season, week, tag,
                                  team_id,
                                  exclude_status   = "OUT",
                                  max_adds_per_pos = 5L,
                                  max_drops        = 10L,
                                  top_n            = 25L,
                                  min_delta        = 1e-6) {

  slots <- espn_snap$roster_slots
  tid   <- as.integer(team_id)

  # opponent, held at current ESPN starters (spec 41) - same map as recommend_lineups()
  mu  <- espn_snap$matchups |> distinct(home_team_id, away_team_id)
  opp <- bind_rows(
    transmute(mu, team_id = home_team_id, opponent_team_id = away_team_id),
    transmute(mu, team_id = away_team_id, opponent_team_id = home_team_id)
  )
  ot <- opp$opponent_team_id[opp$team_id == tid]
  if (length(ot) != 1L) {
    warning(glue::glue("team {tid}: no unique opponent this week; no FA recs"),
            call. = FALSE)
    return(.empty_fa_recs())
  }
  opp_ffa <- current_players$ffa_id[current_players$team_id == ot &
                                      current_players$is_starter &
                                      !is.na(current_players$ffa_id)]

  # base roster candidates - same filter + one-time relax as recommend_lineups()
  my   <- current_players |> filter(team_id == tid)
  base <- my |> filter(!is.na(ffa_id), !is.na(sim_mean), !is_ir,
                       !injury_status %in% exclude_status)
  if (nrow(base) < sum(my$is_starter, na.rm = TRUE)) {
    base <- my |> filter(!is.na(ffa_id), !is.na(sim_mean), !is_ir)
  }
  base <- base |>
    select(ffa_id, pos, position, sim_mean, eligible_slot_ids, player_name, espn_id)

  before  <- evaluate_roster(base, slots, draws_by_ffa, opp_ffa)
  n_before <- nrow(before$optimal_lineup[[1]])

  # DROP pool: the weakest kept players + roster dead weight (unmapped / no
  # forecast, not IR) - the latter models "roster full, drop the stash" (spec 21)
  drop_pool <- bind_rows(
    base |> arrange(sim_mean) |> head(max_drops),
    my |> filter(is.na(ffa_id) | is.na(sim_mean), !is_ir) |>
      transmute(ffa_id = as.integer(ffa_id), pos, position, sim_mean = NA_real_,
                eligible_slot_ids, player_name, espn_id)
  ) |> distinct(espn_id, .keep_all = TRUE)

  # ADD pool: top max_adds_per_pos free agents per position that (a) have a draw
  # vector and (b) are not already on the roster (spec 21)
  add_pool <- free_agents |>
    filter(as.character(ffa_id) %in% names(draws_by_ffa),
           !ffa_id %in% base$ffa_id) |>
    group_by(pos) |>
    slice_max(sim_mean, n = max_adds_per_pos, with_ties = FALSE) |>
    ungroup()

  if (nrow(drop_pool) == 0L || nrow(add_pool) == 0L) return(.empty_fa_recs())

  fa_row <- function(a) {
    tibble(ffa_id = a$ffa_id, pos = a$pos, position = a$position, sim_mean = a$sim_mean,
           eligible_slot_ids = a$eligible_slot_ids,
           player_name = a$player_name, espn_id = as.integer(a$player_id))
  }

  rows <- list()
  for (di in seq_len(nrow(drop_pool))) {
    d <- drop_pool[di, ]
    kept <- if (is.na(d$ffa_id)) base else base |> filter(!ffa_id %in% d$ffa_id)
    for (ai in seq_len(nrow(add_pool))) {
      a    <- add_pool[ai, ]
      cand <- bind_rows(kept, fa_row(a))
      after <- suppressWarnings(evaluate_roster(cand, slots, draws_by_ffa, opp_ffa))
      if (nrow(after$optimal_lineup[[1]]) < n_before) next   # roster went illegal (spec 21)

      rows[[length(rows) + 1L]] <- tibble(
        run_id  = run_id,
        season  = as.integer(season), week = as.integer(week), tag = tag,
        team_id = as.integer(team_id),
        drop_player_id = as.integer(d$espn_id), drop_ffa_id = as.integer(d$ffa_id),
        add_player_id  = as.integer(a$player_id), add_ffa_id = as.integer(a$ffa_id),
        drop_position  = d$position, add_position = a$position,
        before_expected = before$expected_points,
        after_expected  = after$expected_points,
        delta_expected  = after$expected_points - before$expected_points,
        before_win_probability = before$win_probability,
        after_win_probability  = after$win_probability,
        delta_win_probability  = after$win_probability - before$win_probability
      )
    }
  }

  if (length(rows) == 0L) return(.empty_fa_recs())

  # one row per free agent: the add is the real decision, the drop is just a move
  # that realises the gain. A better DST otherwise shows up paired with every
  # weak drop.
  # ponytail: keeps the best-delta pairing per add; revisit if per-drop detail matters
  out <- bind_rows(rows) |>
    filter(delta_expected > min_delta) |>
    arrange(desc(delta_expected), desc(delta_win_probability), add_ffa_id, drop_ffa_id) |>
    distinct(add_player_id, .keep_all = TRUE) |>
    mutate(recommendation_rank = row_number()) |>
    head(top_n)

  if (nrow(out) == 0L) .empty_fa_recs() else out
}
