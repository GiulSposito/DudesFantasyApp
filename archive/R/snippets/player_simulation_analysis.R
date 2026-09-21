dudes_players_simulations |>
  unnest( summ ) |> 
  pivot_wider(id_cols=c(season, week, id, playerId, pos, simType),
              names_from = name, 
              values_from = value) |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  ggplot(aes(x=`75%`, y=pts, color=simType))+
  geom_point(alpha=.3) +
  stat_smooth(method = "lm", se=F) +
  theme_light()
dudes_players_simulations |> 
  
  library(ggridges)

filter(id == "14136", week==10, season==SEASON) |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  unnest(summ) |>
  filter( name=="50%" ) |> 
  mutate(simType = fct_reorder(simType, value)) |> 
  select(simType, simulation, value, pts) |> 
  unnest(simulation) |> 
  ggplot(aes(x=simulation, y=simType, fill=simType)) +
  geom_density_ridges(scale = 2,
                      color = "white",
                      alpha = .7) +  
  geom_vline(xintercept = 0, color="grey", linetype="dashed") +
  geom_hline(aes(yintercept=simType, color=simType),alpha=.3) +
  geom_point(aes(x=value, y=simType), shape=24, color="red", fill="red", show.legend = F, alpha=.5) +
  geom_point(aes(x=pts, y=simType), shape=24, color="black", fill="black", show.legend = F, alpha=.5) +
  theme_light()


fit_models <- dudes_players_simulations |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  select(-seeds, -simulation) |> 
  unnest(summ) |> 
  filter(name=="50%") |> 
  nest(data=c(value, pts), .by=c(simType)) |> 
  mutate( lm = map(data, \(.x) lm(pts~value, .x), .progress=T)) |> 
  mutate( stats = map(lm, broom::augment, .progress=T) ) |> 
  unnest( stats )


dudes_players_simulations |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  select(-seeds, -simulation) |> 
  unnest(summ) |> 
  filter( name %in% c("30%", "70%")) |> 
  mutate( name = str_c("p", str_remove(name, "%"))) |> 
  pivot_wider(
    id_cols=c(season, week, id, playerId, pos, simType, pts),
    names_from = name, 
    values_from = value) |> 
  group_by(simType) |> 
  summarise( in_range=mean(pts>=p30 & pts<=p70) ) |> 
  arrange(desc(in_range))



fit_models |> 
  
  tibble(
    pred = fit_models[1,]$lm[[1]]$fitted.values,
    real = fit_models[1,]$lm[[1]]$model$pts
  ) |> 
  yardstick::rmse(truth=real, estimate=pred)

sqrt(mean(fit_models[1,]$lm[[1]]$residuals^2))

fit_models[1,]$lm[[1]] |> 
  broom::augment()



2^2

?yardstick::rmse()



fit_models |> 
  ggplot(aes(x=p.value, y=r.squared, color=simType)) +
  geom_point(alpha=.5) +
  theme_minimal()


ggplot(aes(
  x = pts.proj,
  y = reorder(full_name,-display.order),
  fill = pos
)) +
  
  geom_point(aes(x=weekPts), shape=24, color="red", fill="red", show.legend = F, alpha=.8) +
  geom_hline(aes(yintercept=reorder(full_name,-display.order), color=pos),alpha=.3) +
  theme_light() +
  xlab("Fantasy Points") +
  ylab("") +
  theme(legend.position = "bottom") 


stt$nfl_players_points |> 
  inner_join(id_map, join_by(playerId)) |> 
  filter(id == "13593", week==WEEK, season==SEASON)

unnest(seeds) |> 
  ggplot(aes(x=seeds, fill=simType)) +
  geom_density(alpha=.5) +
  ggplot2::scale_fill_brewer(type = "qual") +
  theme_light()

plotly::ggplotly(splot)


library(tidyverse)

proj <- list(
  runif(100, 0,10),
  runif(100, 3, 8),
  runif(100, 5,9)
)

tibble(
  id1 = 1:3
) |> 
  expand(id1=id1, id2 = id1) |> 
  filter(id1<id2) |> 
  mutate( win = map2_int(id1, id2, \(i1,i2,prj){
    if(mean(pluck(prj, i1))>mean(pluck(prj, i2))){
      return(i1)
    } else {
      return(i2)
    }
  }, prj = proj)) |> 
  count(win, sort=T)
