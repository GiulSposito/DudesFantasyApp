library(tidyverse)

stat <- readRDS("./data/2021/players_points.rds")
proj <- readRDS("./data/season_weekly_proj.rds")

stat %>% names()
proj %>% names()

stat %>% 
  filter(str_detect(name, "Kyle"), position=="QB", nflTeamAbbr=="ARI")

proj %>% 
  filter(id==14056) %>% 
  ggplot(aes(x=week, y=points)) +
  geom_point() +
  geom_vline(xintercept = 7, linetype="dashed", color="grey") +
  stat_smooth() +
  theme_light()

proj %>% 
  filter(id==14056) %>% 
  group_by(week) %>% 
  summarise(points = mean(points, na.rm=T), .groups="drop") %>% 
  ggplot(aes(x=week, y=points)) +
  geom_point() +
  geom_vline(xintercept = 7, linetype="dashed", color="grey") +
  stat_smooth() +
  theme_light() +
  labs(title="Kyle Murray | Season 2022", subtitle = "Avg Weekly Projection")

stat %>% 
  filter(id==14056) %>% 
  ggplot(aes(x=week, y=weekPts)) +
  geom_point() +
  geom_vline(xintercept = 7, linetype="dashed", color="grey") +
  stat_smooth() +
  theme_light() + 
  labs(title="Kyle Murray | Season 2021")

  