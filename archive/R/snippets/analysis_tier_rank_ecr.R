library(dm)
library(tidyverse)


ffa <- readRDS("./data/ffa_db.rds")
stt <- readRDS("./data/nfl_stats_db.rds")

map_id <- ffa$ffa_player_ids |> 
  transmute(id=id, playerId=as.integer(nfl_id))

points <- stt$nfl_players_points |> 
  inner_join(map_id, by = join_by(playerId))

ffa$ffa_projtable |>
  filter(avg_type == "average") |>
  filter(timestamp == max(timestamp), .by = c(season, week)) |>
  inner_join(points, by = join_by(season, week, id)) |> 
  select(
    id,
    pos,
    floor,
    projPts=points,
    pts,
    ceiling,
    floor_rank,
    rank,
    ceiling_rank,
    pos_rank,
    pos_ecr,
    tier,
    uncertainty
  ) |> 
  mutate( ptsCenter = pts-projPts,
          scale = sd(pts), 
          norm = ptsCenter/scale, .by=pos ) |> 
  ggplot(aes(x = norm, y = pos_ecr, color = as.factor(round(pos_ecr)), alpha=uncertainty)) +
  geom_point() +
  theme_minimal()
