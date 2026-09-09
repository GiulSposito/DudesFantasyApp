# Decision engine - Phase 5: matchup simulation (spec 14-15).
#
# For each ESPN head-to-head, sum the aligned Monte Carlo draws of every marked
# starter on each side (draw i of every player comes from the same pipeline seed,
# so they add coherently), then compare the two team totals draw-by-draw.
#
# No RNG here - deterministic given the draws.

library(tidyverse)

# home_ffa_ids / away_ffa_ids : integer vectors of the starters' ffa_id.
# draws_by_ffa : named list, ffa_id (as character) -> numeric(n_sim).
# Returns a 1-row tibble (spec 15 metrics).
simulate_matchup <- function(home_ffa_ids, away_ffa_ids, draws_by_ffa) {
  hk <- as.character(home_ffa_ids)
  ak <- as.character(away_ffa_ids)
  missing <- setdiff(c(hk, ak), names(draws_by_ffa))
  if (length(missing) > 0L) {
    stop(glue::glue("no draw vector for ffa_id: {paste(missing, collapse = ', ')}"),
         call. = FALSE)
  }

  home_total <- reduce(draws_by_ffa[hk], `+`)
  away_total <- reduce(draws_by_ffa[ak], `+`)

  hq <- quantile(home_total, c(.10, .50, .90), names = FALSE)
  aq <- quantile(away_total, c(.10, .50, .90), names = FALSE)

  tibble(
    home_expected = mean(home_total),
    away_expected = mean(away_total),
    home_p10 = hq[1], home_p50 = hq[2], home_p90 = hq[3],
    away_p10 = aq[1], away_p50 = aq[2], away_p90 = aq[3],
    home_win_probability = mean(home_total > away_total),
    away_win_probability = mean(away_total > home_total),
    tie_probability      = mean(home_total == away_total),
    n_sim = length(home_total)
  )
}

# current_players : build_current_league_state() output.
# matchups        : espn_snap$matchups.
# Returns matchup_simulations (spec 15 schema + run_id).
simulate_matchups <- function(current_players, matchups, draws_by_ffa,
                              run_id, season, week, tag) {

  starters <- current_players |> filter(is_starter) |> select(team_id, ffa_id)
  ffids <- function(tid) starters$ffa_id[starters$team_id == tid]

  matchups |>
    distinct(matchup_id, home_team_id, away_team_id) |>
    pmap_dfr(function(matchup_id, home_team_id, away_team_id) {
      bind_cols(
        tibble(run_id = run_id,
               season = as.integer(season), week = as.integer(week), tag = tag,
               matchup_id = matchup_id,
               home_team_id = home_team_id, away_team_id = away_team_id),
        simulate_matchup(ffids(home_team_id), ffids(away_team_id), draws_by_ffa)
      )
    }) |>
    select(run_id, season, week, tag, matchup_id, home_team_id, away_team_id,
           home_expected, away_expected,
           home_p10, home_p50, home_p90, away_p10, away_p50, away_p90,
           home_win_probability, away_win_probability, tie_probability, n_sim)
}
