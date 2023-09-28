library(tidyverse)
library(dm)
library(glue)
library(ffanalytics)

# MASTER PARAMETERS ####
config <- yaml::read_yaml("./config/config.yml")
.season <- 2023
.week <- 4
.leagueId <- config$leagueId
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")
.tag <- "posWaivers"


# NFL ####

# TEAMS ####

source("./R/api/nfl_league.R")
team_resp <- nfl_league_teams(config$authToken, config$leagueId)

nfl_teams <- team_resp |> 
  nfl_extractTeams()

nfl_owners <- team_resp |> 
  nfl_extractTeamOwners()

nfl_db <- dm(nfl_teams, nfl_owners) |> 
  dm_add_pk(nfl_teams, teamId) |> 
  dm_add_pk(nfl_owners, ownerUserId) |> 
  dm_add_fk(nfl_teams, ownerUserId, nfl_owners)

dm_draw(nfl_db, view_type="all")

# PLAYERS ####
source("./R/api/nfl_players.R")
players_resp <- nfl_players(.authToken = config$authToken, .leagueId = config$leagueId)
players_raw <- players_resp |> nfl_extractPlayers()

nfl_players <- players_raw |> 
  select(-injuryGameStatus)

nfl_player_injury_status <- players_raw |> 
  mutate(timestamp = lubridate::now()) |> 
  select(playerId, timestamp, injuryGameStatus) 

nfl_db <- dm(nfl_db, nfl_players, nfl_player_injury_status) |> 
  dm_add_pk(nfl_players, playerId) |> 
  dm_add_pk(nfl_player_injury_status, c(playerId, timestamp)) |> 
  dm_add_fk(nfl_player_injury_status, playerId, nfl_players)

dm_draw(nfl_db, view_type="all", column_types = T)
  
# STATISTICS ####
source("./R/api/nfl_players.R")
players_stats_resp <- nfl_players_stats(config$authToken, config$leagueId, .season, 1:.week)

playersStatsResp <- players_stats_resp


players_stats_raw <- player_stats_resp %>%  
  nfl_extractPlayersStats()




players_stats_raw |> 
  glimpse()

players_stats_resp$content |> View()

players_stats_resp$response |> 
  content("text") |> 
  fromJSON(flatten = T) |> 
  View()

  toJSON() |> 
  fromJSON(simplifyVector = T, simplifyDataFrame = T) |> 
  str()


team_resp$content$games[[1]] |> 
  toJSON() |> 
  fromJSON()
  flatten()

our_df <- your_list %>%
  
  # make json, then make list
  toJSON() %>%
  fromJSON() %>%
  
  # remove classification level
  purrr::flatten() %>%
  
  # turn nested lists into dataframes
  map_if(is_list, as_tibble) %>%
  
  # bind_cols needs tibbles to be in lists
  map_if(is_tibble, list) %>%
  
  # creates nested dataframe
  bind_cols()