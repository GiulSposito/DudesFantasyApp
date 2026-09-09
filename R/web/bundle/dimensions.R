# Web bundle - dimension marts (contract sections 11-13).
#   dimensions/teams.parquet        season + team_id
#   dimensions/players.parquet      season + player_id
#   dimensions/roster_slots.parquet season + lineup_slot_id

library(tidyverse)

# first SWID in a possibly comma-joined owner_ids string
.first_owner_id <- function(x) {
  if (is.list(x)) x <- vapply(x, function(v) if (length(v)) as.character(v[[1]]) else NA_character_, character(1))
  str_trim(sub(",.*$", "", as.character(x)))
}

build_dim_teams <- function(src, run) {
  members <- src$espn_db$espn_members |>
    transmute(owner_id = member_id, owner_name = display_name)

  src$espn_db$espn_teams |>
    filter(season == run$season) |>
    mutate(owner_id = .first_owner_id(owner_ids)) |>
    left_join(members, by = "owner_id") |>
    transmute(
      season, team_id, team_name, abbrev, division_id,
      owner_id, owner_name,
      is_my_team = team_id == src$my_team_id
    )
}

build_dim_players <- function(src, run) {
  xref <- src$analytical_db$player_ids |>
    filter(!is.na(espn_id)) |>
    distinct(espn_id, .keep_all = TRUE) |>
    select(espn_id, ffa_id, nfl_id)

  src$espn_db$espn_players |>
    filter(season == run$season) |>
    left_join(xref, by = c("player_id" = "espn_id")) |>
    transmute(
      season, player_id,
      ffa_id, nfl_id,
      player_name,
      position,
      nfl_team = pro_team,
      first_name, last_name
    )
}

build_dim_roster_slots <- function(src, run) {
  src$espn_db$espn_roster_slots |>
    filter(season == run$season) |>
    transmute(
      season,
      lineup_slot_id,
      slot_label = lineup_slot,
      slot_count = count
    )
}
