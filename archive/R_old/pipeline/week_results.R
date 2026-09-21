library(tidyverse)
library(lubridate)
library(glue)
library(ffanalytics)

# parametros de execucao
weeks <- 1:11
week <- tail(weeks,1)

config <- yaml::read_yaml("./config/config.yml")

# API ACCESS CHECK ####
source("./R/import/checkFantasyAPI.R")
if(!checkFantasyAPI(config$authToken, config$leagueId, week)) stop("Unable to access Fantasy API!")

# import machups
# source("./R/import/import_matchups.R")
# matchups <- weeks %>% 
#   map( importMatchups, .saveToFile = F )

source("./R/api/ffa_league.R")
matchups_resps <- weeks %>% 
  map( ~ffa_league_matchups(config$authToken, config$leagueId, .week = .x, .incRosters = F) )

matchups <- matchups_resps %>% 
  map( ffa_extractMatchups )
  
saveRDS(matchups, "./data/post_matchups_results.rds")

# # import player statistics
# source("./R/import/import_player_stats.R")
# player_stats <- importPlayerStatistics(1:week, .saveToFile = F)
# saveRDS(player_stats, "./data/players_points.rds")

