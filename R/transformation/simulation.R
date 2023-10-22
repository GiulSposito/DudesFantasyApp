library(tidyverse)
library(dm)
library(lubridate)
library(glue)

# calcula os erros das projeções dos datasources
calcProjectionErrors <- function(season, weeks, tag=""){
  
  # projections
  ffa <- readRDS("./data/ffa_db.rds")
  
  # seleciona temporada e semaanas
  proj_source_points <- ffa$ffa_proj_source_points |>
    filter(season %in% season,
           week %in% weeks)
  
  # se tem uma tag, usa
  if (tag != "")
    proj_source_points <- proj_source_points |>
    filter(tag == tag)
  
  # pega o maior timestamp
  proj_source_points <- proj_source_points |> 
    filter(timestamp==max(timestamp), .by=c(season,week)) |> 
    select(-tag, -timestamp) |> 
    arrange(season, week, id, pos, data_src)
  
  # player id map
  id_map <- ffa$ffa_player_ids |> 
    transmute(id, playerId = as.integer(nfl_id))
  
  # pega os pontos feitos
  nfl <- readRDS("./data/nfl_stats_db.rds")

  dudes_proj_errors <- nfl$nfl_players_points |>
    inner_join(id_map, by = join_by(playerId)) |>
    inner_join(proj_source_points, by = join_by(season, week, id)) |>
    transmute(season, week, id, playerId, pos, data_src,
              ptsError = pts - points)   
  
  return(dudes_proj_errors)
    
}

# aplica os erros de projeções passadas a uma projeção atual
applyErrorToProjection <- function(ffa_projections, dudes_errors){

  inner_join(
    select(ffa_projections, season, week, tag, timestamp, id, pos, data_src, ptsProj=points),
    select(dudes_errors, fromSeason=season, fromWeek=week, data_src, id, playerId, pos, ptsError),
    by = join_by(id, pos, data_src)
  ) |> 
    mutate( points = ptsProj+ptsError ) |> 
    select(season, week, tag, timestamp, id, playerId, pos, points, everything())
  
  
}

