library(tidyverse)
library(lubridate)
library(glue)
library(ffanalytics)
library(furrr)
library(progressr)

# Suppress summarise info
options(dplyr.summarise.inform = FALSE)

# EXECUTION PARAMETERS ####
season <- 2022
config <- yaml::read_yaml("./config/config.yml")

# STEP 1 - GAME SCHEDULE ####

# FANTASY API ACCESS CHECK ####
source("./R/import/checkFantasyAPI.R")
if(!checkFantasyAPI(config$authToken, config$leagueId, 1)) stop("Unable to access Fantasy API!")

# MATCHUPS
source("./R/api/ffa_league.R")

schedule <- 1:14 %>% 
  map(~ffa_league_matchups(config$authToken, config$leagueId, .x))

games <- schedule %>% 
  map(~ffa_extractMatchups(.x))

rosters <- schedule %>% 
  map(~ffa_extractTeamsFromMatchups(.x)) 

# save state
list(
  shedule = schedule, 
  games = games,
  rosters = rosters
) %>% 
  saveRDS("./data/season_simulations_schedule.rds")

# STEP 2 - WEEKLY PROJECTION ####

# scrap combinations
scrape_comb <- expand.grid(
    week = 1:14,
    src = c("CBS", "ESPN", "FantasyPros", "FantasySharks", 
      "FFToday", "FleaFlicker", "NumberFire", "FantasyFootballNerd", 
      "NFL", "RTSports", "Walterfootball"),
    pos = c("QB", "RB", "WR", "TE", "K", "DST"),
    stringsAsFactors = F)

# scrap sequence
scrape_comb <- as_tibble(scrape_comb[sample(1:nrow(scrape_comb), nrow(scrape_comb), replace = F),])

# safety fail
safe_scrape_data <- safely(scrape_data, otherwise = NULL)

with_progress({
  
  pbar <- progressor(steps = nrow(scrape_comb))

  plan(multisession, workers=5)
  full_weekly_scrape <- scrape_comb %>%
    split(1:nrow(.)) %>% 
    future_map(function(.x){
      pbar()
      safe_scrape_data(src=.x$src, pos=.x$pos, week=.x$week, season=2022)    
    })
  plan(sequential)
  
    
})

full_weekly_scrape %>% 
  saveRDS("./data/season_simulation_weekly_scrape.rds")

     