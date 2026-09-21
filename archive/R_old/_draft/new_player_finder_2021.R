season_proj 


myTeam <- sim$teams %>% 
  filter(teamId==4) %>% 
  select(name, rosters) %>% 
  unnest(rosters) %>%
  select(playerId, slotPosition) %>% 
  left_join(select(sim$players_id, id, playerId=nfl_id), by="playerId") %>% 
  mutate(id=as.character(id)) %>% 
  inner_join(season_proj, by="id") %>% 
  filter(avg_type=="average") %>% 
  arrange(desc(ceiling_vor))
 
fa <- sim$teams %>% 
  select(rosters) %>% 
  unnest(rosters) %>% 
  select(playerId) %>% 
  left_join(select(sim$players_id, id, playerId=nfl_id), by="playerId") %>% 
  mutate(id=as.character(id)) %>% 
  anti_join(season_proj,., by="id") %>% 
  filter(avg_type=="average") %>% 
  arrange(desc(points_vor))

myTeam %>% 
  select(-playerId, -slotPosition) %>% 
  bind_rows(fa) %>% 
  arrange(desc(points_vor)) %>% 
  View()
