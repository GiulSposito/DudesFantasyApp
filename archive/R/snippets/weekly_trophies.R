library(tidyverse)
library(dm)

stats <- readRDS("./data/nfl_stats_db.rds")
playersDB <- readRDS("./data/nfl_players_db.rds")
round <- readRDS("./data/nfl_round_db.rds")
teams <- readRDS("./data/nfl_teams_db.rds")


round |> 
  dm_draw(view_type = "all", column_types = T)


rosters <- round$nfl_teams_rosters |> 
  filter(tag=="final", week==8L)

points <- stats$nfl_players_points |> 
  filter(season==2023, week==8L)

players <- playersDB$nfl_players |> 
  select(playerId, name, position)

rosters |> 
  inner_join(points, by = join_by(season, week, playerId)) |> 
  inner_join(playersDB$nfl_players, by = join_by(playerId)) |> 
  select(teamId, slotPosition, rosterSlotId, playerId, player=name, position, pts) |> 
  inner_join(teams$nfl_teams, by = join_by(teamId)) |>
  filter(rosterSlotId < 20) |> 
  select(player, position, pts, team=name) |> 
  slice_max(pts, n=1)
  

rosters |> 
  inner_join(points, by = join_by(season, week, playerId)) |> 
  inner_join(playersDB$nfl_players, by = join_by(playerId)) |> 
  select(teamId, slotPosition, rosterSlotId, playerId, player=name, position, pts) |> 
  inner_join(teams$nfl_teams, by = join_by(teamId)) |> 
  filter(rosterSlotId >= 20) |> 
  select(player, position, pts, team=name) |> 
  slice_max(pts, n=1)

rosters |> 
  inner_join(points, by = join_by(season, week, playerId)) |> 
  inner_join(playersDB$nfl_players, by = join_by(playerId)) |> 
  select(teamId, slotPosition, rosterSlotId, playerId, player=name, position, pts) |> 
  inner_join(teams$nfl_teams, by = join_by(teamId)) |> 
  filter(rosterSlotId < 20) |> 
  select(player, position, pts, team=name) |> 
  group_by(team) |> 
  slice_max(pts, n=2) |> 
  mutate(pts_total=sum(pts)) |> 
  ungroup() |> 
  slice_max(pts_total, n=1)




