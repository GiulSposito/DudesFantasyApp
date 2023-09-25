library(tidyverse)
library(dm)
library(glue)
library(ffanalytics)

# MASTER PARAMETERS ####
config <- yaml::read_yaml("./config/config.yml")
.season <- 2023
.week <- 3
.leagueId <- config$leagueId
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")
.tag <- "preTNF"

# PROJECTION SCRAPING ####
source("./R/api/ffa_projection.R")
.ffa_scrape_db <- scrapeWebData(.tag, .week, .season)

# temp
saveRDS(.ffa_scrape_db, "./data/ffa_scrap_db_temp.rds")
.ffa_scrape_db <- readRDS("./data/ffa_scrap_db_temp.rds")

# FFA CALCULATIONS
ffa_db <- calcProjections(.ffa_scrape_db, .scoreRules)
dm_draw(ffa_db, view_type = "all", column_types = F)

ffa_db$ffa_scrape |> 
  filter(season==2023, week==3) |> 
  filter(timestamp == max(timestamp)) |> 
  select(-scrapeData) |> 
  inner_join(ffa_db$ffa_projtable)

# FFA SECTION ####

# FFA PLAYER IDS ####
load("../ffanalytics/R/sysdata.rda")
ffa_player_ids <- player_ids

# FFA SCRAPPING SITES ####
source("./R/import/ffa_player_projection.R")
webScrape <- scrapPlayersPredictions(week, season)

# FFA PROJECT TABLE ####
ffa_raw_projection_table <- 
  projections_table(webScrape, .scoreRules) |> 
  add_ecr() |> 
  add_uncertainty() |> 
  add_player_info()

ffa_projtable <- ffa_raw_projection_table |> 
  select(avg_type:uncertainty) |> 
  mutate(
    season = .season,
    week = .week
  ) |> 
  select(season, week, avg_type, id, everything()) |> 
  distinct()

# FFA SITE POINTS ####
source("./R_old/simulation/data_src_proj_table.R")
ffa_raw_source_points <- projections_table_data_sources(webScrape, yaml::read_yaml("./config/score_settings.yml")) 

ffa_proj_source_points <- ffa_raw_source_points |>
  mutate(season = .season, week = .week) |> 
  select(season, week, data_src, id, pos, everything())

# FFA PLAYERS ####
ffa_players <- ffa_raw_projection_table |> 
  select(id:pos, first_name:exp) |> 
  distinct()

ffa_db <- dm(ffa_player_ids, ffa_players, ffa_projtable, ffa_proj_source_points) |> 
  dm_add_pk(ffa_player_ids, id, check = T) |> 
  dm_add_pk(ffa_players, c(id, pos), check=T) |> 
  dm_add_pk(ffa_projtable, c(season, week, avg_type, id, pos), check = T) |> 
  dm_add_fk(ffa_players, id, ffa_player_ids) |> 
  dm_add_fk(ffa_projtable, c(id, pos), ffa_players) |> 
  dm_add_pk(ffa_proj_source_points, c(season, week, data_src, id, pos), check=T) |> 
  dm_add_fk(ffa_proj_source_points, c(id, pos), ffa_players)

dm_draw(ffa_db, view_type = "all", column_types = F)

ffa_db |> 
  saveRDS("./new_db/ffa_db_w03_s23.rds")

# NFL ####

# TEAMS

source("./R/api/ffa_league.R")
team_resp <- ffa_league_teams(config$authToken, config$leagueId)

nfl_teams <- team_resp |> 
  ffa_extractTeams()

nfl_owners <- team_resp |> 
  ffa_extractTeamOwners()

nfl_db <- dm(nfl_teams, nfl_owners) |> 
  dm_add_pk(nfl_teams, teamId) |> 
  dm_add_pk(nfl_owners, ownerUserId) |> 
  dm_add_fk(nfl_teams, ownerUserId, nfl_owners)

dm_draw(nfl_db, view_type="all")

# PLAYERS
source("./R/api/ffa_players.R")

players <- ffa_players(.authToken = config$authToken, .leagueId = config$leagueId)

players |> ffa_extractPlayers()


players_stats <- ffa_players_stats(config$authToken, config$leagueId, .season, 1:.week) %>%  
  ffa_extractPlayersStats()

teamsResp$content$games[[1]]$leagues[[1]] |> 
  pull()


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