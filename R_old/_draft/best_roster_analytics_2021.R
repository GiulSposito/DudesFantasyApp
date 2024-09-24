library(tidyverse)

sim <- readRDS("./data/simulation_v5_week5_preMNF.rds")

psim <- sim$players_sim

# readRDS("./data/players_points.rds")

pstats <- sim$players_stats %>% 
  select(playerId, name, position, rankAgainstPosition, weekPts) %>% 
  unnest(weekPts) %>% 
  group_by(playerId) %>% 
  mutate(
    ptsMean=mean(weekPts, na.rm = T)
  ) %>% 
  ungroup() %>% 
  filter( week==4 ) %>% 
  rename(rankA = rankAgainstPosition) %>% 
  select(-week, -weekPts)

mypprojs <- psim %>%
  filter( is.na(injuryGameStatus) | injuryGameStatus=="Questionable" ) %>% 
  filter(teamId == 4, isReserveStatus==F ) %>% 
  select(playerId, id, pts.proj, simulation.org) %>% 
  mutate(
    ttest = map(pts.proj, ~broom::tidy(t.test(.x)))
  ) %>% 
  unnest(ttest)
  
myteamsim <- pstats %>% 
  inner_join(mypprojs) %>%
  arrange(desc(conf.low))  %>% 
  select(-parameter, -method, -alternative, -pts.proj, -simulation.org, -statistic)

library(ggrepel)

myteamsim %>% 
  select(id, name, position, rankA, season=weekSeasonPts, ptsMean) %>% 
  inner_join(readRDS("./data/dudesffa_projpoints_week5.rds")) %>% 
  arrange(desc(estimate)) %>% 
  ggplot(aes(x=ptsMean, y=estimate, color=position)) +
  geom_point() +
  geom_text_repel(aes(label=name)) +
  geom_errorbar(aes(ymin=conf.low, ymax=conf.high)) +
  geom_abline(aes(slope=1, intercept=0), linetype="dashed") + 
  theme_minimal()
  

myteamsim %>% 
  select(id, name, position, rankA, season=weekSeasonPts, ptsMean) %>% 
  inner_join(readRDS("./data/dudesffa_projpoints_week5.rds")) %>% 
  arrange(desc(estimate))


roster <- tibble(
  pos = c("QB","WR","RB","TE","K","DEF"),
  qtd = c(1,2,2,1,1,1)
)

roster %>% 
  split(1:nrow(.)) %>% 
  map_df(function(.x, .players){
    .players %>% 
      filter(position==.x$pos) %>% 
      slice_max(n=.x$qtd, order_by=estimate)
  }, .players = myteamsim )




.players <- myteamsim
.x <- roster[2,]

myteamsim %>% 
  dplyr::top_n(n = 4, rankA)

?top_n

df <- data.frame(x = c(6.1, 4.1, 1.1, 10.1, 3.1, 1.1, 1.1), y=c(9,8,7,6,5,4,3))

df %>% top_n(n=2, wt=x)  # highest values
myteamsim %>% top_n(n=2,wt=rankA)  # highest values
df %>% top_n(2) # lowest values


mypprojs[1,]$pts.proj[[1]] %>% 
  hist()
