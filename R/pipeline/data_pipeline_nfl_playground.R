library(tidyverse)
library(dm)
library(glue)
library(ffanalytics)
library(lubridate)

# MASTER PARAMETERS ####
config <- yaml::read_yaml("./config/config.yml")
.season <- 2023L
.week <- 4L
.leagueId <- config$leagueId
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")
.tag <- "posTNF"


# https://cran.r-project.org/web/packages/ffscrapr/ffscrapr.pdf

# NFL ####

# TEAMS ####

source("./R/api/nfl_league.R")
team_resp <- nfl_league_teams(config$authToken, config$leagueId)

nfl_teams <- team_resp |> 
  nfl_extractTeams()

nfl_owners <- team_resp |> 
  nfl_extractTeamOwners()

nfl_fantasy_teams_db <- dm(nfl_teams, nfl_owners) |> 
  dm_add_pk(nfl_teams, teamId) |> 
  dm_add_pk(nfl_owners, ownerUserId) |> 
  dm_add_fk(nfl_teams, ownerUserId, nfl_owners)

dm_draw(nfl_fantasy_teams_db, view_type="all")

# PLAYERS ####
source("./R/api/nfl_players.R")
players_resp <- nfl_players(.authToken = config$authToken, .leagueId = config$leagueId)
players_raw <- players_resp |> nfl_extractPlayers()

nfl_players <- players_raw |> 
  select(-injuryGameStatus)

nfl_player_injury_status <- players_raw |> 
  mutate(timestamp = lubridate::now()) |> 
  select(playerId, timestamp, injuryGameStatus) 

nfl_players_db <- dm(nfl_players, nfl_player_injury_status) |> 
  dm_add_pk(nfl_players, playerId) |> 
  dm_add_pk(nfl_player_injury_status, c(playerId, timestamp)) |> 
  dm_add_fk(nfl_player_injury_status, playerId, nfl_players)

dm_draw(nfl_players_db, view_type="all")
  
# STATISTICS ####

source("./R/api/nfl_game.R")
statsDict <- nfl_gameStats() |> 
  nfl_extractStatDict()

source("./R/api/nfl_players.R")
players_stats_resp <- nfl_players_stats(config$authToken, config$leagueId, .season, 1:.week)

nfl_stats_db <- players_stats_resp |> 
  nfl_extractPlayersStats(statsDict)

dm_draw(nfl_stats_db, view_type="all", column_types = T)


# GAME E ROSTER ####

# FANTASY: PLAYERS AND MATCHUPS ####
source("./R/api/nfl_league.R")
tstamp <- lubridate::now()
leagueMatchups <- nfl_league_matchups(config$authToken, config$leagueId, .week)
matchups_games <- nfl_extractMatchups(leagueMatchups, .season)
teams_rosters_db  <- nfl_extractTeamsFromMatchups(leagueMatchups, .season, .week, .tag, tstamp)   
teams_stats_db  <- nfl_extractStatsFromMatchups(leagueMatchups, .season, .week, .tag, tstamp)   

nfl_round_db <-
  dm(matchups_games, teams_rosters_db, teams_stats_db) |>
  dm_add_pk(matchups_games, c(season, week, matchupId)) |>
  dm_add_fk(nfl_teams_week_stats, c(season, week, teamId), nfl_teams_round) |>
  dm_add_fk(nfl_teams_season_stats,
            c(season, week, teamId),
            nfl_teams_round)

dm_draw(nfl_round_db, view_type = "all", column_types = T)


nfl_db <- dm(nfl_fantasy_teams_db,
   nfl_players_db,
   nfl_stats_db,
   nfl_round_db) |>
  dm_add_fk(nfl_players_stats, c(playerId), nfl_players) |>
  dm_add_fk(nfl_players_points, c(playerId), nfl_players) |>
  dm_add_fk(nfl_players_adv_stats, c(playerId), nfl_players) |>
  dm_add_fk(nfl_teams_round, c(teamId), nfl_teams)

nfl_db |>
  dm_draw(view_type = "all")
