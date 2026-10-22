# Web bundle - draft/draft.parquet (contract section 27).
# 1 row = 1 player of the run's season: every drafted player plus the undrafted
# ones who scored. PK season + player_id. What each pick returned so far:
#   vor               points over the replacement level of the position (best
#                     player outside the league-wide starting lineups)
#   value_over_expected  vor - the mean vor of the picks around it (about one
#                     round), i.e. better / worse than its draft slot returned
#   decision_value    the same against the ESPN pre-season projection (what the
#                     draft room showed): a good / bad pick by the info of then
#   luck_value        value_over_expected - decision_value (they sum exactly)
# Feeds the Draft page (Liga menu).

library(tidyverse)

if (!exists(".optimize_lineup_greedy")) source("./R/decision/lineup_optimizer.R")
if (!exists(".fa_slot_map"))            source("./R/decision/free_agents.R")

.NFL_GAMES <- 17L   # regular-season games per NFL team

build_draft <- function(src, run) {
  e <- src$espn_db
  picks <- e$espn_draft |> filter(season == run$season)
  if (nrow(picks) == 0L) return(.empty_draft())

  pts <- e$espn_players_points |>
    filter(season == run$season, stat_season == run$season,
           timestamp <= run$espn_timestamp)

  # season totals so far, from the newest snapshot
  actual <- pts |>
    filter(stat_source_id == 0L, stat_split_type_id == 0L) |>
    slice_max(timestamp, n = 1, with_ties = TRUE) |>
    transmute(player_id, points = fantasy_points)

  # weeks with points (bye / did not play score nothing), newest snapshot per week
  weeks <- pts |>
    filter(stat_source_id == 0L, stat_split_type_id == 1L) |>
    slice_max(timestamp, n = 1, with_ties = TRUE, by = week) |>
    summarise(weeks_scored = sum(coalesce(fantasy_points, 0) != 0), .by = player_id)

  # pre-season projection: the earliest snapshot before the season's first
  # kickoff that covers the most drafted players (the first snapshots of a
  # season carry only a handful of projections)
  games <- e$espn_pro_games |> filter(season == run$season)
  proj <- pts |>
    filter(stat_source_id == 1L, stat_split_type_id == 0L,
           timestamp < min(games$game_date))
  if (nrow(proj) > 0L) {
    first_full <- proj |>
      summarise(n = sum(player_id %in% picks$player_id), .by = timestamp) |>
      filter(n == max(n)) |>
      slice_min(timestamp, n = 1)
    proj <- proj |> filter(timestamp == first_full$timestamp)
  }
  proj <- proj |> transmute(player_id, proj_points = fantasy_points)

  # NFL games already played by each pro team: prorates the season projection
  played <- games |>
    filter(coalesce(stats_official, FALSE), game_date <= run$espn_timestamp)
  team_games <- bind_rows(transmute(played, pro_team_id = home_pro_team_id),
                          transmute(played, pro_team_id = away_pro_team_id)) |>
    count(pro_team_id, name = "team_games")

  rosters <- e$espn_rosters |>
    filter(season == run$season, timestamp <= run$espn_timestamp)
  # current owner: newest snapshot of the newest week (a "final" snapshot of a
  # past week can be fetched later and carries no acquisition_type)
  owners <- rosters |>
    slice_max(week, n = 1, with_ties = TRUE) |>
    slice_max(timestamp, n = 1, with_ties = TRUE) |>
    transmute(player_id, owner_team_id = team_id, acquisition_type)

  pool <- e$espn_players |>
    filter(season == run$season) |>
    transmute(player_id, player_name, position, nfl_team = pro_team, pro_team_id) |>
    left_join(actual, by = "player_id") |>
    left_join(weeks, by = "player_id") |>
    left_join(proj, by = "player_id") |>
    left_join(team_games, by = "pro_team_id") |>
    left_join(.fa_slot_map(rosters), by = "position") |>
    mutate(points = coalesce(points, 0),
           weeks_scored = coalesce(weeks_scored, 0L),
           proj_points_to_date = proj_points * coalesce(team_games, 0L) / .NFL_GAMES)

  # replacement level: every team's starting slots filled league-wide
  n_teams <- n_distinct(picks$team_id)
  slots <- e$espn_roster_slots |>
    filter(season == run$season) |>
    mutate(count = count * n_teams)
  repl      <- .replacement_level(pool, "points", slots)
  repl_proj <- .replacement_level(pool, "proj_points_to_date", slots)

  radius <- n_teams %/% 2L
  pool |>
    left_join(repl, by = "position") |>
    left_join(rename(repl_proj, proj_replacement = replacement), by = "position") |>
    mutate(vor = points - coalesce(replacement, 0),
           proj_vor = proj_points_to_date - coalesce(proj_replacement, 0),
           pos_rank = min_rank(desc(points)),
           proj_pos_rank = min_rank(desc(proj_points)),
           .by = position) |>
    left_join(picks |> transmute(player_id, overall_pick, round, round_pick,
                                 draft_team_id = team_id),
              by = "player_id") |>
    left_join(owners, by = "player_id") |>
    filter(!is.na(overall_pick) | points != 0) |>
    mutate(draft_pos_rank = if_else(is.na(overall_pick), NA_integer_,
                                    min_rank(overall_pick)), .by = position) |>
    mutate(
      pos_rank_delta      = draft_pos_rank - pos_rank,
      vor_expected        = .expected_by_pick(overall_pick, vor, radius),
      value_over_expected = vor - vor_expected,
      proj_vor_expected   = .expected_by_pick(overall_pick, proj_vor, radius),
      decision_value      = proj_vor - proj_vor_expected,
      luck_value          = value_over_expected - decision_value
    ) |>
    transmute(
      season = as.integer(run$season), player_id, player_name, position, nfl_team,
      overall_pick, round, round_pick, draft_team_id, owner_team_id, acquisition_type,
      points, weeks_scored, proj_points, proj_points_to_date,
      pos_rank, proj_pos_rank, draft_pos_rank, pos_rank_delta,
      vor, vor_expected, value_over_expected,
      proj_vor, proj_vor_expected, decision_value, luck_value
    ) |>
    arrange(overall_pick, desc(points))
}

# Points of the best player outside the league-wide starting lineups, per
# position, by `value` (a pool column). The greedy fill is exact with a single
# flex type, which is this league's case (see .optimize_lineup_greedy()).
.replacement_level <- function(pool, value, slots) {
  cand <- pool |>
    filter(!is.na(.data[[value]]), !is.na(eligible_slot_ids)) |>
    transmute(ffa_id = player_id, espn_id = player_id, pos = position,
              sim_mean = .data[[value]], eligible_slot_ids, player_name)
  starters <- .optimize_lineup_greedy(cand, slots)$ffa_id
  cand |>
    filter(!ffa_id %in% starters) |>
    summarise(replacement = max(sim_mean), .by = pos) |>
    rename(position = pos)
}

# Mean of `value` over the drafted picks within `radius` of each pick; NA for
# undrafted players (pick NA).
.expected_by_pick <- function(pick, value, radius) {
  drafted <- !is.na(pick)
  vapply(pick, function(p) {
    if (is.na(p)) return(NA_real_)
    v <- value[drafted & abs(pick - p) <= radius]
    if (all(is.na(v))) NA_real_ else mean(v, na.rm = TRUE)
  }, double(1))
}

.empty_draft <- function() {
  tibble(season = integer(), player_id = integer(), player_name = character(),
         position = character(), nfl_team = character(),
         overall_pick = integer(), round = integer(), round_pick = integer(),
         draft_team_id = integer(), owner_team_id = integer(),
         acquisition_type = character(),
         points = double(), weeks_scored = integer(),
         proj_points = double(), proj_points_to_date = double(),
         pos_rank = integer(), proj_pos_rank = integer(),
         draft_pos_rank = integer(), pos_rank_delta = integer(),
         vor = double(), vor_expected = double(), value_over_expected = double(),
         proj_vor = double(), proj_vor_expected = double(),
         decision_value = double(), luck_value = double())
}
