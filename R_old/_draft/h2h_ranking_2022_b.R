# # install.packages("nflseedR")
# library(nflseedR)
# 
# ?compute_division_ranks
# 
# games <- tibble(
#   sim = 1,
#   game_type = "REG",
#   week = c(1,1,2,2,3,3),
#   away_team = c("A","C","A","B","A","B"),
#   home_team = c("B","D","C","D","D","C"),
#   result = c(1,-1000,-1,1,1,-1)
# )
# 
# teams <- tibble(
#   sim = 1,
#   team = c("A","B","C","D"),
#   conf = "dudes", 
#   division = "dudes"
# )
# 
# res <- compute_division_ranks(games, teams, 2, T)
# 
# res
# 
# res$h2h %>% 
#   pivot_wider(id_cols=c(sim, team), names_from = opp, values_from = h2h_wins)


library(tidyverse)
library(glue)
source("./R/api/ffa_league.R")
library(nflseedR)
config <- yaml::read_yaml("./config/config.yml")

### DATA SET PREPARATION

sim <- readRDS("./data/simulation_v5_week1_final.rds")

teams <- sim$teams %>% 
  select(teamId, name) %>% 
  mutate(nickname=str_trim(str_extract(name, "\\b(\\w+)$"))) %>% 
  mutate(nickname=janitor::make_clean_names(nickname)) %>% 
  select(id=teamId, name=nickname)


games <- 1:13 %>% 
  map_df(function(.w){
    
    sim <- glue("./data/simulation_v5_week{.w}_final.rds") %T>% 
      print() %>% 
      readRDS()
    
    match_result <- sim$matchups %>% 
      select(week, awayTeam.teamId, awayTeam.outcome, homeTeam.teamId, homeTeam.outcome) %>% 
      set_names(c("week", "away.id","away.win","home.id","home.win"))
    
    match_points <- sim$matchup_sim %>%
      select(week, homeTeam.teamId, awayTeam.teamId, homeTeam.totalPts, awayTeam.totalPts) %>% 
      set_names(c("week","home.id","away.id", "home.pts", "away.pts"))
    
    inner_join(match_result, match_points, by = c("week", "away.id", "home.id"))
  }) %>% 
  inner_join(teams, by=c("away.id"="id")) %>% 
  rename(away_team=name) %>% 
  inner_join(teams, by=c("home.id"="id")) %>% 
  rename(home_team=name) %>% 
  mutate(result = home.pts - away.pts) %>% 
  mutate( sim = 1, game_type = "REG") %>% 
  select(sim, game_type, week, away_team, home_team, result)

teams_div <- teams %>% 
  mutate(sim=1, conf="dudes", division="dudes") %>% 
  select(sim, team=name, conf, division)

# res <- compute_division_ranks(games, teams_div, 2, T)

full_schedule <- 1:14 %>% 
  map(~ffa_league_matchups(config$authToken, config$leagueId, .x, F))

remaining_schedule <- full_schedule %>% 
  map_df(ffa_extractMatchups) %>%
  filter(homeTeam.outcome=="") %>% 
  select(week, away_id=awayTeam.teamId, home_id=homeTeam.teamId) %>% 
  left_join(teams, by=c("away_id"="id")) %>% 
  rename(away_team=name) %>% 
  left_join(teams, by=c("home_id"="id")) %>% 
  rename(home_team=name) %>% 
  select(week, away_team, home_team)

game_sims <- 1:1000 %>%
  map_df(function(.sim, .rschd, .games) {
    .rschd %>%
      mutate(result = rnorm(nrow(.), 0, sd(.games$result))) %>%
      bind_rows(.games) %>%
      mutate(sim = .sim, game_type="REG") %>%
      return()
  }, .rschd = remaining_schedule, .games = games) %>% 
  arrange(sim, week) %>% 
  select(sim, week, away_team, home_team, result, game_type)

teams_div_sim <-   1:1000 %>% 
  map_df(function(.sim, .teams){
    .teams %>% 
      mutate(sim=.sim, conf="dudes", division="dudes") %>% 
      select(sim, team=name, conf, division)
  }, .teams=teams)

res <- compute_division_ranks(game_sims, teams_div_sim, tiebreaker_depth = 3, .debug=T)

plff <- res$standings %>% 
  select(sim, team, div_rank) %>% 
  mutate(playoffs = div_rank<7) %>% 
  count(team, playoffs) %>% 
  mutate(pct = round(100*n/1000)) %>% 
  pivot_wider(id_cols = team, names_from = playoffs, values_from = pct) %>% 
  select(team, playoffs=`TRUE`) %>% 
  mutate(playoffs = if_else(is.na(playoffs), 0, playoffs)) %>% 
  arrange(desc(playoffs))

pos <- res$standings %>% 
  count(team, div_rank) %>% 
  mutate(rank = fct_reorder(paste0("rnk_", div_rank), div_rank),
         pct=round(100*(n/1000))) %>% 
  arrange(div_rank) %>% 
  mutate(pct=if_else(is.na(pct), 0, pct)) %>% 
  pivot_wider(team, names_from = rank, values_from = pct)

r <- res$standings %>% 
  count(team, div_rank) %>% 
  group_by(team) %>% 
  filter(n==max(n)) %>% 
  ungroup() %>% 
  select(team, rank=div_rank)

r %>% 
  inner_join(plff, by="team") %>% 
  inner_join(pos, by="team") %>% 
  arrange(desc(-rank)) %>% 
  select(-rank)
