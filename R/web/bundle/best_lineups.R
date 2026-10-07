# Web bundle - history/best_lineups.parquet.
# 1 row = 1 starting slot of a "best possible lineup" for a closed week, built
# from real ESPN points. PK season + week + kind + player_id.
#   kind "league"       best players rostered by any fantasy team (dream team)
#   kind "free_agents"  best players nobody rostered
# A week is closed once it has an ESPN snapshot tagged "final"; rosters and
# points both come from that week's newest "final" snapshot. Feeds the two
# cards under the matchup grid on Placar da rodada.

library(tidyverse)

if (!exists("optimize_lineup")) source("./R/decision/lineup_optimizer.R")
if (!exists(".fa_slot_map"))    source("./R/decision/free_agents.R")

build_best_lineups <- function(src, run) {
  finals <- src$espn_db$espn_rosters |>
    filter(season == run$season, tag == "final", timestamp <= run$espn_timestamp)
  if (nrow(finals) == 0L) return(.empty_best_lineups())
  finals <- finals |> group_by(week) |> filter(timestamp == max(timestamp)) |> ungroup()

  slots <- src$espn_db$espn_roster_slots |> filter(season == run$season)

  bind_rows(lapply(sort(unique(finals$week)), function(w) {
    ros <- finals |> filter(week == w)
    pts <- src$espn_db$espn_players_points |>
      filter(season == run$season, timestamp == ros$timestamp[1], week == w,
             stat_source_id == 0, stat_split_type_id == 1) |>
      left_join(distinct(ros, player_id, team_id), by = "player_id") |>
      inner_join(.fa_slot_map(ros), by = "position")

    best <- function(pool, kind) {
      # no position fills more than 3 slots, so the top 5 per position suffice
      cand <- pool |>
        group_by(position) |>
        slice_max(fantasy_points, n = 5, with_ties = FALSE) |>
        ungroup() |>
        transmute(ffa_id = player_id, espn_id = player_id, pos = position,
                  sim_mean = fantasy_points, eligible_slot_ids, player_name)
      optimize_lineup(cand, slots) |>
        transmute(season = as.integer(run$season), week = as.integer(w), kind,
                  slot_order = row_number(), lineup_slot_id, lineup_slot,
                  player_id = espn_id) |>
        left_join(pool |> select(player_id, player_name, position,
                                 nfl_team = pro_team, points = fantasy_points, team_id),
                  by = "player_id")
    }
    bind_rows(best(filter(pts, !is.na(team_id)), "league"),
              best(filter(pts, is.na(team_id)), "free_agents"))
  }))
}

.empty_best_lineups <- function() {
  tibble(season = integer(), week = integer(), kind = character(),
         slot_order = integer(), lineup_slot_id = integer(), lineup_slot = character(),
         player_id = integer(), player_name = character(), position = character(),
         nfl_team = character(), points = double(), team_id = integer())
}
