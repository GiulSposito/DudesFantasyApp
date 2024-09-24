library(tidyverse)

pts <- readRDS("./data/players_points.rds")

pts %>% 
  filter(id %in% c(13726,14056,10697)) %>% 
  select(id, name, week, weekPts) %>% 
  mutate(
    trade = case_when(
      id==14056 ~ "Murray",
      T ~ "Edmonds_Tannehill"
    )
  ) %>% 
  mutate( weekPts = if_else(is.na(weekPts), 0, weekPts) ) %>% 
  pivot_wider(id_cols=week, names_from="trade", values_from=weekPts, values_fn=sum) %>% 
  filter(week >= 2, complete.cases(.)) %>% 
  pivot_longer(cols = -week, names_to="Trade", values_to="Points") %>% 
  group_by(Trade) %>% 
  mutate(Points=cumsum(Points)) %>% 
  ggplot(aes(x=week, y=Points, color=Trade)) +
  geom_line(size=1)+
  geom_point(size=2)+
  # geom_vline(xintercept = 1.5, color="darkgrey", linetype="dashed", size=1) +
  theme_light() +
  labs( title="Edmonds+Tannehill bomb trade by Murray", subtitle = "Cumulated Points From Week 2") +
  ylim(0,NA) +
  theme(legend.position = "bottom") 

  
?pivot_longer




select(id, name, position, week, weekPts) %>% 
  



