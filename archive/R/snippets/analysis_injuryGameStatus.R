

# entender se o injury status report tem influencia sobre os pontos
# comparar projecao com realizado separando os injuried dos note injuried

# pontos projetados => project table
proj_points <- ffa_db$ffa_projtable |> 
  filter(week < 7, tag=="final", avg_type=="average") |> 
  select(season, week, id, pos, points, sd_pts, uncertainty) |> 
  inner_join(transmute(ffa_db$ffa_player_ids, id, playerId=as.integer(nfl_id)), by = join_by(id)) |> 
  select(season, week, id, playerId, pos, everything()) |> 
  rename(projPts = points, projPtsSD = sd_pts)

# pontos realizados
points <- nfl_stats_db$nfl_players_points |> 
  filter(week!=0, week<7)

# injury status
injury <- readRDS("../DudesFantasyFootball/data/players_points.rds") |> 
  select(playerId, week, injuryGameStatus) 

?fct_

proj_points |> 
  inner_join(points,by = join_by(season, week, playerId)) |> 
  inner_join(injury,by = join_by(week, playerId)) |> 
  filter(pts<30) |> 
  mutate(confidency = cut(1-uncertainty, 5)) |> 
  ggplot(aes(x=projPts, y=pts, color=confidency)) +
  #geom_errorbarh(aes(xmin=projPts-projPtsSD, xmax=projPts+projPtsSD)) +
  geom_point() +
  geom_abline(intercept = 0, slope = 1, linetype="dashed", color="black") +
  stat_smooth(method = "lm", se = F) +
  theme_minimal()
