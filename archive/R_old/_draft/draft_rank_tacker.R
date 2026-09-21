library(tidyverse)
library(ggrepel)
library(ggimage)

draft <- readRDS("./data/draft_2022_picks.rds")
sim <- readRDS("./data/simulation_v5_week13_final.rds")
players_stats <- sim$players_stats


rndpicks <- draft %>% 
  #filter(round<=6) %>% 
  inner_join(players_stats, by=c("player.id"="playerId")) %>% 
  unnest(weekPts) %>% 
  select(round, pick, player.name, position, week, weekPts, 
         weekSeasonPts, imageUrl, team.name, round) %>% 
  filter(week==13)

drf_rnk <- rndpicks %>% 
  select(rank = pick, player.name, position,imageUrl, team.name, round) %>% 
  mutate(week=0)

wk_rnk <- rndpicks %>% 
  mutate( rank = rank(-weekSeasonPts) ) %>% 
  select(week, rank, player.name, position,imageUrl, team.name, round)

# bind_rows(drf_rnk, wk_rnk) %>% 
#   ggplot(aes(week, -rank, group=player.name)) +
#   geom_point(aes(color=position)) + 
#   geom_line(aes(color=position)) + 
#   geom_text_repel(aes(label=if_else(week==0,player.name,as.character(NA)))) +
#   geom_image(aes(image=if_else(week==13,imageUrl, as.character(NA)))) +
#   theme_void() +
#   theme(legend.position = "bottom")

  
bind_rows(drf_rnk, wk_rnk) %>% 
  select(player.name, team.name, round, rank, week) %>% 
  mutate(status=case_when(
    week==0 ~ "pick",
    week==13~ "rank"
  )) %>% 
  pivot_wider(id_cols=c(player.name, team.name,round), names_from="status", values_from = "rank") %>% 
  mutate( gain = pick-rank ) %>% 
  arrange(pick) 


bind_rows(drf_rnk, wk_rnk) %>% 
  select(player.name, team.name, rank, week) %>% 
  mutate(status=case_when(
    week==0 ~ "pick",
    week==13~ "rank"
  )) %>% 
  pivot_wider(id_cols=c(player.name, team.name), names_from="status", values_from = "rank") %>% 
  mutate( gain = pick-rank ) %>% 
  group_by(team.name) %>% 
  summarise(total_gain=sum(gain)) %>% 
  arrange(desc(total_gain))

bind_rows(drf_rnk, wk_rnk) %>% 
  select(player.name, team.name, round, rank, week) %>% 
  mutate(status=case_when(
    week==0 ~ "pick",
    week==13~ "rank"
  )) %>% 
  pivot_wider(id_cols=c(player.name, team.name, round), names_from="status", values_from = "rank") %>% 
  mutate( gain = pick-rank ) %>% 
  slice_max(abs(gain), n=20) %>% 
  arrange(-gain)



