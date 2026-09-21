season_proj_w3 <- season_proj
season_proj <- readRDS("./data/season_projtable.rds")


sproj <- season_proj %>% 
  select(id, first_name, last_name, pos, team, avg_type, floor, points, ceiling, points_vor)

sprojw3 <- season_proj_w3 %>% 
  select(id, avg_type, floor, points, ceiling, points_vor) %>% 
  set_names(paste0("w3_",names(.))) %>% 
  rename(id=w3_id, avg_type=w3_avg_type)

sproj %>% 
  inner_join(sprojw3, by=c("id","avg_type")) %>%
  filter( avg_type=="average",
          pos=="WR") %>% 
  ggplot(aes(x=points, y=w3_points, color=pos)) +
  geom_point() +
  theme_light()
