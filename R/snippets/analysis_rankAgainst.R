library(tidyverse)
library(dm)

# estudar se o rank Aggainst tem influcencia na pontuacao
stt <- readRDS("./data/nfl_stats_db.rds")
ffa <- readRDS("./data/ffa_db.rds")

proj_table <- ffa$ffa_player_ids |> 
  transmute( id, playerId = as.integer(nfl_id)) |> 
  inner_join( ffa$ffa_projtable, by = join_by(id) )

# existe essa info antes do jogo
rank <- 1:11 |> 
  map(~glue::glue("../DudesFantasyFootball/data/rankAgainstPosition_week{.x}.rds")) |> 
  map_df(readRDS)

stt$nfl_players_points |> 
  inner_join(rank, by = join_by(playerId, week)) |> 
  inner_join(proj_table, by = join_by(playerId, season, week)) |> 
  mutate( spread = points-pts,
          spread_pct = spread/pts ) |> 
  ggplot(aes(x=rankAgainstPosition, y=spread_pct)) +
  geom_point(alpha=.5) +
  stat_smooth(method = "lm") +
  theme_light()
  


# proj
proj_points <- ffa$ffa_projtable |> 
  filter(week < 7, tag=="final", avg_type=="average") |> 
  select(season, week, id, pos, points, sd_pts, uncertainty) |> 
  inner_join(transmute(ffa$ffa_player_ids, id, playerId=as.integer(nfl_id)), by = join_by(id)) |> 
  select(season, week, id, playerId, pos, everything()) |> 
  rename(projPts = points, projPtsSD = sd_pts)

# pontos realizados
points <- stt$nfl_players_points |> 
  filter(week!=0, week<7)


points |> 
  inner_join(proj_points, by = join_by(playerId, season, week)) |> 
  inner_join(rank, by = join_by(playerId, week)) |> 
  ## mutate( rankAgainstPosition = as.factor(rankAgainstPosition)) |> 
  group_by( rankAgainstPosition ) |> 
  nest() |> 
  mutate( model = map(data, \(.dt){
    .dt |> 
      lm(pts ~ projPts, data=_)
  }), 
    term = map(model, broom::tidy),
    stat = map(model, broom::glance)
  ) |>  
  unnest(stat) |> 
  unnest(term, names_sep = "_") |> 
  select(rankAgainstPosition, term_term, term_estimate, r.squared, p.value) |> 
  filter(term_term=="projPts") |> 
  ggplot(aes(x=term_estimate, y=r.squared, color=rankAgainstPosition)) +
  geom_point() +
  theme_minimal()

pstats$content$games$`102023`$players[[1]]$advanced$opponent$rankAgainstPosition
pstats$content$games$`102023`$players[[1]]$advanced$DEPRECIATED_DO_NOT_USE
