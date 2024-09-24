library(tidyverse)
library(glue)

.week <- 16

players <- readRDS(glue("./data/week{.week}_players_projections.rds"))

players %>% 
  filter( str_detect(last_name, "Boyd|Thomas") ) %>% 
  select(id, name) %>% 
  distinct()
         
players %>% 
  filter( id %in% c(12650,12652) ) %>% 
  select(name, week, weekPts, weekSeasonPts) %>% 
  arrange(name, week) %>% 
  ggplot(aes(x=week, y=weekSeasonPts, color=name)) +
  geom_text(x=16, y=160, label="WR 33", color="#00CDCD", vjust=0) +
  geom_text(x=16, y=50, label="WR 99", color="#FF4040", vjust=-1) +
  geom_point(size=2) +
  geom_line(size=1.2) +
  labs(title="Bomb Trade", subtitle = "Robot receive Thomas vs Mules receive Boyd") +
  labs(y="Season Pts") +
  theme_light()


players %>% 
  filter(week==16, position=="WR") %>% 
  select(id, pts=weekSeasonPts) %>% 
  slice_max(pts, n=14) %>% 
  mutate(wr_rank=rank(-pts)) %>% 
  select(-pts) %>% 
  inner_join(players) %>% 
  select(name, week, weekPts, weekSeasonPts, wr_rank) %>% 
  mutate(wr_label = if_else(week==16, paste0("WR ", wr_rank), NA_character_)) %>% 
  mutate(name = fct_reorder(name, wr_rank)) %>% 
  ggplot(aes(x=week, y=weekSeasonPts, color=name)) +
  geom_point(size=2, alpha=.8) +
  geom_line(size=1.2, alpha=.5) +
  geom_text(aes(label=wr_label), show.legend = F) +
  theme_light()
