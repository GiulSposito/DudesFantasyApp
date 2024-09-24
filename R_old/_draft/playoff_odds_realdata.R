library(tidyverse)
library(glue)
source("./R/api/ffa_league.R")

config <- yaml::read_yaml("./config/config.yml") 

# season matchups
matchups_resp <- 1:14 %>% 
 map(~ffa_league_matchups(config$authToken,config$leagueId, .x, F)) 

# extract schedule
schedule <- matchups_resp %>% 
  map_df(ffa_extractMatchups) %>% 
  select(week, aTeam = awayTeam.teamId, hTeam = homeTeam.teamId, aWinOut=awayTeam.outcome, hWinOut=homeTeam.outcome ) %>% 
  mutate(
    aWin = case_when(
      aWinOut == "" ~ NA,
      aWinOut == "loss" ~ F,
      T ~ T 
    ),
    hWin = case_when(
      hWinOut == "" ~ NA,
      hWinOut == "loss" ~ F,
      T ~ T 
    )
  ) %>% 
  select(-aWinOut, -hWinOut)

# game results (points)
game_results <- 1:14 %>% 
  map(~glue("./data/simulation_v5_week{.x}_final.rds")) %>% 
  map(readRDS) %>% 
  map(pluck, "matchup_sim") %>% 
  map_df(~select(.x, week, aTeam=awayTeam.teamId, hTeam=homeTeam.teamId, 
                 aScore=awayTeam.totalPts, hScore=homeTeam.totalPts))

matchups <- schedule %>% 
  left_join(game_results, by = c("week", "aTeam", "hTeam")) %>% 
  arrange(desc(week), aTeam, hTeam)

simGames <- simulateGames(matchups,1) %>% 
  arrange(simId, desc(week), aTeam, hTeam)

simulations <- simGames %>% 
  nest(-simId) %>% 
  mutate( ranking = map(data, calcRank) ) %>% 
  select(-data) %>% 
  unnest(ranking) %>% 
  select(simId, week, team, rank ) %>% 
  count( week, team, rank ) %>% 
  mutate( prob = n/max(simGames$simId) )
  # pivot_wider(id_cols = c(week, rank), names_from = team, values_from = prob, values_fill = 0)

simulations %>% 
  filter(week==14) %>% 
  arrange(desc(prob)) %>% 
  select(-week, -n) %>% 
  pivot_wider(id_cols=rank, names_from=team, values_from = prob) %>% 
  arrange(rank)

teams <- readRDS("./data/simulation_v5_week1_final.rds")$teams

teams %>% 
  arrange(teamId, name) %>% 
  select(teamId, name)
