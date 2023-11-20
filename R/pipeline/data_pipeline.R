library(tidyverse)
library(dm)
library(glue)
library(ffanalytics)
library(lubridate)

# update projections
getFFAProjections <- function(.season, .week, .tag, .scoreRules){
  
  # scrape the web
  ffa_scrape_db <- scrapeWebData(.season, .week, .tag)
  
  # cache the scrape
  temp_filename <-
    glue(
      "./data/temp/ffa_scrape_db_s{.season}w{.weeknumber}_{.tag}_{.timestamp}.rds",
      .weeknumber = formatC(.week, width = 2, flag = "0"),
      .timestamp = ffa_scrape_db$ffa_scrape[1,]$timestamp
    )

  # save scrape 
  saveRDS(ffa_scrape_db, temp_filename)
    
  # calculates the projection
  ffa_db <- calcProjections(ffa_scrape_db, .scoreRules)

  # cache ffa_db
  temp_filename <-
    glue(
      "./data/temp/ffa_db_s{.season}w{.weeknumber}_{.tag}_{.timestamp}.rds",
      .weeknumber = formatC(.week, width = 2, flag = "0"),
      .timestamp = ffa_scrape_db$ffa_scrape[1,]$timestamp
    )
  
  # save scrape 
  saveRDS(ffa_scrape_db, temp_filename)
  
  # return value
  return(ffa_db)
}

getFantasyTeams <- function(leagueId, authToken){
  team_resp <- nfl_league_teams(authToken, leagueId)
  
  nfl_teams <- team_resp |> 
    nfl_extractTeams()
  
  nfl_owners <- team_resp |> 
    nfl_extractTeamOwners()
  
  nfl_teams_db <- dm(nfl_teams, nfl_owners) |> 
    dm_add_pk(nfl_teams, teamId) |> 
    dm_add_pk(nfl_owners, ownerUserId) |> 
    dm_add_fk(nfl_teams, ownerUserId, nfl_owners)
  
  return(nfl_teams_db)
}

getFantasyPlayers <- function(leagueId, authToken) {
  players_resp <-
    nfl_players(.authToken = authToken,
                .leagueId = leagueId)
  
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
  
  return(nfl_players_db)
  
}

getFantasyStatistics <- function(leagueId, authToken, season, week){
  
  statsDict <- nfl_gameStats() |> 
    nfl_extractStatDict()
  
  players_stats_resp <- nfl_players_stats(authToken, leagueId, season, 1:week)
  
  nfl_stats_db <- players_stats_resp |> 
    nfl_extractPlayersStats(statsDict)
  
  return(nfl_stats_db)
  
}

getFantasyRound <-  function(leagueId, authToken, season, week, tag){
  
  timestamp <- lubridate::now()
  leagueMatchups <- nfl_league_matchups(authToken, leagueId, week)
  matchups_games <- nfl_extractMatchups(leagueMatchups, season)
  teams_rosters_db  <- nfl_extractTeamsFromMatchups(leagueMatchups, season, week, tag, timestamp)   
  teams_stats_db  <- nfl_extractStatsFromMatchups(leagueMatchups, season, week, tag, timestamp)   
  
  nfl_round_db <-
    dm(matchups_games, teams_rosters_db, teams_stats_db) |>
    dm_add_pk(matchups_games, c(season, week, matchupId)) |>
    dm_add_fk(nfl_teams_week_stats, c(season, week, teamId), nfl_teams_round) |>
    dm_add_fk(nfl_teams_season_stats,
              c(season, week, teamId),
              nfl_teams_round)
  
  return(nfl_round_db)
  
}

getFantasyRecap <- function(.authToken, .leagueId, .week, .teams){
  
  nfl_recap_df <- .teams |>
    map_df(\(team, authToken, leagueId, week) {
      nfl_recap_resp <-
        nfl_league_matchups_recap(authToken, leagueId, week, team)
      
      nfl_recap_data <- nfl_recap_resp$content |>
        enframe() |>
        pivot_wider() |>
        unnest(
          c(
            title,
            type,
            written_at,
            weekday,
            league_id,
            season,
            week_num,
            playoff,
            standard_scheduling,
            standard_scoring
          )
        ) |>
        select(leagueId = league_id, season, week = week_num, everything())
      
      return(nfl_recap_data)
    },
    authToken = .authToken,
    leagueId = .leagueId,
    week = .week) |> 
    distinct()
  
}


# update projections database
updateDB <- function(db, db_file){
  
  # verifica se ha uma versão antiga
  if(file.exists(db_file)){
    # atualiza se houver
    db <- readRDS(db_file) |> 
      dm_rows_upsert(db, in_place = F)
  }
  
  saveRDS(db, db_file)
  
  return(db)
}

# salva respostas em arquivo temporário permitindo o reprocessamento
saveTempResp <- function(obj, name, season, week, tag="NA", timestamp=now()){
  
  tsf <- format(timestamp, "%Y%m%d%H%M%S")
  wf  <- formatC(week, width = 2, flag = "0")
  filename <- glue::glue("./data/temp/{name}_s{season}_s{wf}_{tag}_{tsf}.rds")
  saveRDS(obj, filename)
  
}


# MASTER PARAMETERS ####
config <- yaml::read_yaml("./config/config.yml")
.season <- 2023L
.week <- 11L
.leagueId <- config$leagueId
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")
.tag <- "preMNF"

# update ffa_db ####
source("./R/api/ffa_projection.R")
ffa_db <- getFFAProjections(.season, .week, .tag, .scoreRules)
ffa_db <- updateDB(ffa_db, "./data/ffa_db.rds")
dm_draw(ffa_db,view_type = "all", column_types = T, rankdir = "RL")

# update nfl_teams ####
source("./R/api/nfl_league.R")
nfl_teams_db <- getFantasyTeams(config$leagueId, config$authToken)
nfl_teams_db <- updateDB(nfl_teams_db, "./data/nfl_teams_db.rds")
dm_draw(nfl_teams_db, view_type = "all", column_types = T, rankdir = "RL")

# update players  
source("./R/api/nfl_players.R")
nfl_players_db <- getFantasyPlayers(config$leagueId, config$authToken)
nfl_players_db <- updateDB(nfl_players_db, "./data/nfl_players_db.rds")
dm_draw(nfl_players_db, view_type = "all", column_types = T, rankdir = "RL")

# STATISTICS ####
source("./R/api/nfl_game.R")
source("./R/api/nfl_players.R")
nfl_stats_db <- getFantasyStatistics(config$leagueId, config$authToken, .season, .week)
nfl_stats_db <- updateDB(nfl_stats_db, "./data/nfl_stats_db.rds")
dm_draw(nfl_stats_db, view_type = "all", column_types = T, rankdir = "RL")

# FANTASY: ROUND PLAYERS AND MATCHUPS ####
source("./R/api/nfl_league.R")
nfl_round_db <- getFantasyRound(config$leagueId, config$authToken, .season, .week, .tag)
nfl_round_db <- updateDB(nfl_round_db, "./data/nfl_round_db.rds")
dm_draw(nfl_round_db, view_type = "all", column_types = T, rankdir = "RL")


# FANTASY: RECAP ####
source("./R/api/nfl_league.R")
nfl_recap_df <-
  getFantasyRecap(
    config$authToken,
    config$leagueId,
    10,
    readRDS("./data/nfl_teams_db.rds")$nfl_teams$teamId
  )
nfl_recap_db <- nfl_convertRecapDB(nfl_recap_df)
nfl_recap_db <- updateDB(nfl_recap_db, "./data/nfl_recap_db.rds")
dm_draw(nfl_recap_db, view_type = "all", column_types = T, rankdir = "RL")

