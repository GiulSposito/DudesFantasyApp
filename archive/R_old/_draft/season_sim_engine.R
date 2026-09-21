library(tidyverse)

# schedule da temporada
season_games <- readRDS("./data/season_simulations_schedule.rds")
# projeções semana a semana
season_wproj <- readRDS("./data/season_weekly_proj.rds")

# dados dos jogadores
players <- readRDS("./data/players_points.rds")
players <- players %>% 
  select(playerId, firstName, lastName, byeWeek) %>% 
  distinct()

# carregando tabelas de "de para" de IDs de Jogadores
load("../ffanalytics/R/sysdata.rda") # <<- Players IDs !!!
my_player_ids <- player_ids %>%
  mutate(playerId = as.integer(nfl_id)) %>% 
  select(id, playerId)

season_games$games %>% 
  bind_rows() %>%
  select(week, matchupId, homeTeam.teamId, homeTeam.outcome, awayTeam.teamId, awayTeam.outcome) %>% 
  arrange(week, matchupId)

roster <- season_games$rosters[[1]] %>% 
  unnest(rosters) %>%
  select(teamId, playerId) %>% 
  filter(complete.cases(.)) %>% 
  distinct()

sim_data <- season_wproj %>% 
  select(week, id, pos, points) %>% 
  distinct() %>% 
  group_by(week, id, pos) %>% 
  nest(data=points) %>% 
  ungroup() %>% 
  mutate(
    stats = map(data, function(.x){
      
      arr_pts <- .x$points
      
      if(length(arr_pts)>2){
        stats <- broom::tidy(t.test(arr_pts)) %>% 
          select(conf.low, estimate, conf.high)
      } else {
        stats <- tibble(
          conf.low = min(arr_pts),
          estimate = mean(arr_pts),
          conf.high = max(arr_pts)
        )
      }
      
      tibble(week_pts = list(arr_pts),
             n = length(arr_pts)) %>% 
        bind_cols(stats) %>% 
        return()
      
    })    
  ) %>% 
  unnest(stats) %>% 
  inner_join(my_player_ids, by="id") %>%
  right_join(roster, by="playerId") %>%
  filter(!is.na(week)) %>% 
  inner_join(players, by="playerId")

# melhor time FIXED
best_roster_fixed <- tibble(
  pos = c("QB","WR","RB","TE","K", "DST"),
  qtd = c(1,2,2,1,1,1)
) %>% 
  split(1:nrow(.)) %>% 
  map_df(function(.x, staff){
    staff %>% 
      filter(byeWeek!=week, pos==.x$pos) %>% 
      group_by(teamId, week) %>% 
      slice_max(estimate, n=.x$qtd) %>% 
      mutate( slot = 1:n() ) %>% 
      ungroup() 
  }, staff=sim_data) %>% 
  select(week, teamId, pos, slot, id, everything())

best_roster_week <- sim_data %>% 
  anti_join(best_roster_fixed, by = c("week", "id", "pos", "data", "week_pts", "n", "conf.low", "estimate", "conf.high", "playerId", "teamId",
                                      "firstName", "lastName", "byeWeek")) %>% 
  filter(byeWeek!=week, pos %in% c("WR","RB")) %>% 
  group_by(teamId, week) %>% 
  slice_max(estimate, n=1) %>% 
  ungroup() %>% 
  mutate(pos="W/R") %>% 
  mutate(slot=1) %>% 
  bind_rows(best_roster_fixed) %>% 
  select(week, teamId, pos, slot, id, everything())

best_roster_week %>%
  mutate( slot = paste0(pos, slot)) %>% 
  complete(week, teamId, slot) %>% 
  filter(is.na(id)) %>% 
  count(week, teamId, slot) %>% 
  pivot_wider(id_cols=c(week, teamId), names_from=slot, values_from = n) %>% 
  filter(!complete.cases(.)) 

best_roster_week %>%
  mutate( slot = paste0(pos, slot)) %>% 
  mutate( sim_pts = map(week_pts, sample, size=1000, replace=T) ) %>% 
  group_by(week, teamId) %>% 
  nest() %>% 
  mutate( team_scores = map(data, function(.x){
    
  }))


x[1,]$data[[1]]$sim_pts
  
  
  select(slot, sim_pts) %>% 
  pivot_wider(id_cols=NULL, names_from = slot, values_from = sim_pts) %>% 
  mutate()




