sim <- readRDS("./data/simulation_v5_week1_preTNF.rds")
season <-  readRDS("./data/season_proj_stats.rds") %>% 
  filter(avg_type=="average")


# carregando tabelas de "de para" de IDs de Jogadores
load("../ffanalytics/R/sysdata.rda") # <<- Players IDs !!!
my_player_ids <- player_ids %>%
  transmute( id = as.integer(id), nfl_id = as.integer(nfl_id))


team_pos <- sim$teams %>% 
  select(teamId, name, rosters) %>% 
  unnest(rosters) %>% 
  filter(complete.cases(.)) %>% 
  inner_join(my_player_ids, by=c("playerId"="nfl_id")) %>% 
  inner_join(mutate(season, id=as.integer(id)), by="id") %>% 
  select(teamId, name, pos, first_name, last_name, floor, points, ceiling)  %>% 
  group_by(teamId, name, pos) %>% 
  summarise(
    floor=mean(floor, na.rm = T),
    points=mean(points, na.rm = T), 
    ceiling=mean(ceiling, na.rm = T),
    .groups="drop"
  )

pos_avg <- sim$teams %>% 
  select(teamId, name, rosters) %>% 
  unnest(rosters) %>% 
  filter(complete.cases(.)) %>% 
  inner_join(my_player_ids, by=c("playerId"="nfl_id")) %>% 
  inner_join(mutate(season, id=as.integer(id)), by="id") %>% 
  select(pos, floor, points, ceiling) %>% 
  group_by(pos) %>% 
  summarise(
    floor_avg   = mean(floor, na.rm = T),
    points_avg  = mean(points, na.rm = T), 
    ceiling_avg = mean(ceiling, na.rm = T),
    .groups="drop"
  )

team_pos %>% 
  inner_join(pos_avg, by="pos") %>% 
  mutate(strengh = points - points_avg) %>% 
  mutate( name = fct_reorder(name, strengh )) %>% 
  ggplot(aes(y=pos, x=strength, fill=pos, color=pos)) +
  geom_point(size=2) +
  geom_bar(stat="identity", width = .1) +
  geom_vline(xintercept=0, color="grey", linetype="dashed" ) + 
  facet_wrap(~name ) +
  theme_light()

  
             