library(tidyverse)

pstats <- readRDS("./data/players_points.rds")

rstats <- pstats %>% 
  select(playerId, researchStatsWeek) %>%
  distinct() %>% 
  unnest(researchStatsWeek)

ppoints <- pstats %>% 
  select(playerId, name, position, week, weekPts)

pscores <- ppoints %>% 
  inner_join(rstats, by=c("playerId","week")) %>% 
  filter(!is.na(percentStarted)) %>% 
  filter(percentStarted > 0, !is.na(weekPts)) %>%
  group_by(week, position) %>% 
  mutate( weekPosAvgPoints = mean(weekPts) ) %>%
  ungroup() %>% 
  select(week, playerId, name, position, weekPts, weekPosAvgPoints, percentStarted) %>% 
  mutate( diffPoints = weekPts - weekPosAvgPoints)

sims <- fs::dir_ls("./data/2021") %>%
  .[str_detect(.,"final")] %>% 
  map(readRDS)

team_points <- sims %>% 
  map_df(function(.sim){
    .sim$teams %>%
      select(teamId, week.stats) %>% 
      unnest(week.stats) %>% 
      return()
  })

scoreAvg <- team_points$pts %>% mean()
team_points$pts %>% mean()
team_points$pts %>% sd()
scoreAvg <- 111.48 

qqnorm(team_points$pts)

fpow <- team_points$pts %>% 
  ecdf()

fpow %>% summary()

fpow(scoreAvg)

plot(fpow, xlab="pontos", ylab="probalidade de vitória", main="Cummulative Distribution")  

fgw <- pscores %>% 
  mutate( impact = fpow(scoreAvg + diffPoints)-.5,
          fgw    = impact*(percentStarted/100) )

xlsx::write.xlsx(fgw, "./static/exports/2021/fgw_week_final.xlsx")


