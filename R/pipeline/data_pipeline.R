library(tidyverse)
library(dm)
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

# update projections database
updateFFAProjetions <- function(ffa_db, .ffa_db_file="./data/ffa_db.rds"){
  
  # verifica se ha uma versão antiga
  if(file.exists(.ffa_db_file)){
    # atualiza se houver
    old_ffa_db <- readRDS(.ffa_db_file)
    ffa_db <- dm_rows_upsert(old_ffa_db, ffa_db, in_place = F)
  }
  
  saveRDS(ffa_db, .ffa_db_file)
  
  return(ffa_db)
}

# update projections database
updateFantasyTeams <- function(nfl_teams_db, .db_file="./data/nfl_teams_db.rds"){
  
  # verifica se ha uma versão antiga
  if(file.exists(.db_file)){
    # atualiza se houver
    old_nfl_teams_db <- readRDS(.db_file)
    nfl_teams_db <- dm_rows_upsert(old_nfl_teams_db, nfl_teams_db, in_place = F)
  }
  
  saveRDS(nfl_teams_db, .db_file)
  
  return(nfl_teams_db)
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


# MASTER PARAMETERS ####
config <- yaml::read_yaml("./config/config.yml")
.season <- 2023L
.week <- 5L
.leagueId <- config$leagueId
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")
.tag <- "final"

# update ffa_db ####
source("./R/api/ffa_projection.R")
ffa_db <- getFFAProjections(.season, .week, .tag, .scoreRules)
ffa_db <- updateFFAProjetions(ffa_db)
dm_draw(ffa_db,view_type = "all", column_types = T)

# update nfl_teams ####
source("./R/api/nfl_league.R")
nfl_teams_db <- getFantasyTeams(config$leagueId, config$authToken)
nfl_teams_db <- updateFantasyTeams(nfl_teams_db)
dm_draw(nfl_teams_db, view_type = "all", column_types = T)

# update players 
source("./R/api/nfl_players.R")
nfl_players_db <- getFantasyPlayers(config$leagueId, config$authToken)
dm_draw(nfl_players_db, view_type = "all", column_types = T)



# STATISTICS ####

source("./R/api/nfl_game.R")
statsDict <- nfl_gameStats() |> 
  nfl_extractStatDict()

source("./R/api/nfl_players.R")
players_stats_resp <- nfl_players_stats(config$authToken, config$leagueId, .season, 1:.week)

nfl_stats_db2023 <- players_stats_resp |> 
  nfl_extractPlayersStats(statsDict)

pbar 

db <- nfl_stats_db2023 |> 
  dm_rows_upsert(nfl_stats_db2022, in_place = F, progress = T)

db$nfl_players_points |> 
  pivot_wider(id_cols=playerId, names_from=c(season,week), values_from = pts)






