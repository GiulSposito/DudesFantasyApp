library(tidyverse)

season <- readRDS("./data/season_proj_stats.rds")
week <- readRDS("./data/week1_players_projections.rds")

ids <- season %>% 
  filter(avg_type=="average", last_name %in% c("Claypool", "Green")) %>% 
  select(id, pos, first_name, last_name, team) %>% 
  pull(id)

season %>% 
  filter( avg_type=="average") %>% 
  select( id, pos, first_name, last_name, team, everything()) %>% 
  filter( id %in% ids) %>% 
  mutate( name = glue::glue("{first_name} {last_name} ({pos}) {team}") ) %>% 
  mutate( name = fct_reorder(name, points)) %>% 
  ggplot(aes(y=points, x=name)) +
  geom_pointrange(aes(ymin=floor, ymax=ceiling)) +
  geom_point() +
  coord_flip() +
  labs(x="player", y="season points") +
  theme_light()

sim <- readRDS("./data/simulation_v5_week2_posWaivers.rds")

sim$teams %>% 
  select(teamId, name)

tibble(
  tradeId = 1,
  propTeamId = 1,
  toTeamId = 2,
  sendPlayer = 12650,
  recvPlayer = 12652
)

week %>% 
  filter( avg_type=="average") %>% 
  select( id, pos, first_name, last_name, team, injuryGameStatus, rankAgainstPosition, everything()) %>% 
  filter( id %in% c(12650,12652)) %>% 
  inner_join(readRDS("./data/injuryGameStatusAbbr.rds"), by = "injuryGameStatus") %>% 
  mutate( injuryAbbr = if_else(is.na(injuryAbbr), "", paste0("(", injuryAbbr, ")"))) %>% 
  mutate( name = glue::glue("{first_name} {last_name} {team} {injuryAbbr}") ) %>% 
  mutate( name = fct_reorder(name, points)) %>% 
  ggplot(aes(y=points, x=name)) +
  geom_pointrange(aes(ymin=floor, ymax=ceiling)) +
  geom_point() +
  coord_flip() +
  labs(x="player", y="week 1 points") +
  theme_light()

readRDS("./data/injuryGameStatusAbbr.rds")
