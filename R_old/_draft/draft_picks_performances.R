library(tidyverse)
library(glue)
library(broom)
library(ggrepel)

draft <- readRDS("./data/draft_2022_picks.rds") %>% 
  rename(playerId=player.id)
stat <- readRDS("./data/players_points.rds")

stat %>% 
  select(playerId, name, position, week, weekPts, weekSeasonPts) %>% 
  filter(week <= 13) %>% 
  mutate( weekPts = if_else(is.na(weekPts), 0, weekPts),
          weekPts = if_else(is.na(weekSeasonPts), 0, weekSeasonPts)) %>%
  inner_join(draft, by = "playerId") %>% 
  filter(round==1) %>% 
  mutate( team = str_extract(team.name,"\\w+?$"),
          round=as.factor(round) ) %>% 
  ggplot(aes(x=week, y=weekSeasonPts, color=team, group=playerId)) +
  geom_line(aes(linetype=round)) +
  geom_point(aes(shape=round), size=2) +
  xlim(1,16) +
  geom_text_repel(aes(label=if_else(week==13, paste0(player.name," (", position, ")"), "")), show.legend = F, direction = "x") +
  theme_light()
  




