# NFL Fantasy API pipeline
#
# Split out of the old data_pipeline_ffa_nfl.R: this half pulls league data from
# the NFL Fantasy API (teams, players, stats, rounds, recaps) and persists the
# nfl_*_db.rds databases. The ffanalytics projections half lives in
# data_pipeline_ffa.R.
#
# Needs config$authToken / config$leagueId in config/config.yml (absent since the
# league moved to ESPN - see data_pipeline_espn.R).
#
# Run from the project root:  source("R/pipeline/data_pipeline_nfl.R")

library(tidyverse)
library(dm)
library(glue)
library(lubridate)

# ---- helpers ---------------------------------------------------------------

# update existing rows by PK, insert new ones, persist to an on-disk .rds
updateDB <- function(db, db_file){
  if(file.exists(db_file)){
    db <- readRDS(db_file) |>
      dm_rows_upsert(db, in_place = F)
  }
  saveRDS(db, db_file)
  return(db)
}

# cache a raw API response so a run can be reprocessed without hitting the network
saveTempResp <- function(obj, name, season, week, tag="NA", timestamp=now()){
  tsf <- format(timestamp, "%Y%m%d%H%M%S")
  wf  <- formatC(week, width = 2, flag = "0")
  filename <- glue::glue("./data/temp/{name}_s{season}_s{wf}_{tag}_{tsf}.rds")
  saveRDS(obj, filename)
}

# draw a dm ERD to a PNG file. Works around DiagrammeR >= 1.0.11, whose htmlwidget
# renderer fails in the RStudio Viewer with "Layout was not done"; export_svg()
# uses the DOT->SVG path instead. Needs DiagrammeRsvg + rsvg.
dm_draw_png <- function(dm, ..., file, width = 2400) {
  svg <- DiagrammeRsvg::export_svg(dm::dm_draw(dm, ...))
  rsvg::rsvg_png(charToRaw(svg), file, width = width)
  file
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

  players_stats_resp <- nfl_players_stats(authToken, leagueId, season, week)

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

# MASTER PARAMETERS ####
config <- yaml::read_yaml("./config/config.yml")
.season <- 2026L
.week <- 0L
.leagueId <- config$leagueId
.tag <- "season"

# update nfl_teams ####
source("./R/api/nfl_league.R")
nfl_teams_db <- getFantasyTeams(config$leagueId, config$authToken)
nfl_teams_db <- updateDB(nfl_teams_db, "./data/nfl_teams_db.rds")
dm_draw_png(nfl_teams_db, view_type = "all", column_types = T, rankdir = "RL",
            file = "./data/temp/nfl_teams_db.png")

# update players
source("./R/api/nfl_players.R")
nfl_players_db <- getFantasyPlayers(config$leagueId, config$authToken)
nfl_players_db <- updateDB(nfl_players_db, "./data/nfl_players_db.rds")
dm_draw_png(nfl_players_db, view_type = "all", column_types = T, rankdir = "RL",
            file = "./data/temp/nfl_players_db.png")

# STATISTICS ####
source("./R/api/nfl_game.R")
source("./R/api/nfl_players.R")
nfl_stats_db <- getFantasyStatistics(config$leagueId, config$authToken, .season, 1:.week)
nfl_stats_db <- updateDB(nfl_stats_db, "./data/nfl_stats_db.rds")
dm_draw_png(nfl_stats_db, view_type = "all", column_types = T, rankdir = "RL",
            file = "./data/temp/nfl_stats_db.png")

# FANTASY: ROUND PLAYERS AND MATCHUPS ####
source("./R/api/nfl_league.R")
nfl_round_db <- getFantasyRound(config$leagueId, config$authToken, .season, .week, .tag)
nfl_round_db <- updateDB(nfl_round_db, "./data/nfl_round_db.rds")
dm_draw_png(nfl_round_db, view_type = "all", column_types = T, rankdir = "RL",
            file = "./data/temp/nfl_round_db.png")

# FANTASY: RECAP ####
if(.tag=="final") {
  source("./R/api/nfl_league.R")
  nfl_recap_df <-
    getFantasyRecap(
      config$authToken,
      config$leagueId,
      .week,
      readRDS("./data/nfl_teams_db.rds")$nfl_teams$teamId
    )
  nfl_recap_db <- nfl_convertRecapDB(nfl_recap_df)
  nfl_recap_db <- updateDB(nfl_recap_db, "./data/nfl_recap_db.rds")
  dm_draw_png(
    nfl_recap_db,
    view_type = "all",
    column_types = T,
    rankdir = "RL",
    file = "./data/temp/nfl_recap_db.png"
  )
}
