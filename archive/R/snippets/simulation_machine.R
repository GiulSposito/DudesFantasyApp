# SCRIPT PARA GERAR VARIAS ESTRATEGIAS DE SIMULACAO E AVALIAR O OUTCOME
library(dm)
library(tidyverse)
# PARA CADA JOGADOR COM PONTO NA TEMPORADA 2023

# MASTER PARAMETERS ####
WEEK <- 1L
SEASON <- 2024L

# SOURCE DATABASES ####
ffa <- readRDS("./data/ffa_db.rds") # projecoes
stt <- readRDS("./data/nfl_stats_db.rds") # pontuacao
ply <- readRDS("./data/nfl_players_db.rds") # players info

# id-map
id_map <- ffa$ffa_player_ids |>
  transmute(id, playerId = as.integer(nfl_id))

# bye week info
bye_week <- ply$nfl_players |> 
  select(playerId, week=byeWeek) |> 
  inner_join(id_map, join_by(playerId)) |> 
  mutate(season=SEASON)

# proj table
proj_table <- ffa$ffa_projtable |>
  filter(timestamp == max(timestamp), .by = c(season, week)) |>
  filter(week != 0, week <= WEEK, season == SEASON) |>
  select(season, week, id, pos, avg_type, points) |>
  inner_join(id_map, join_by(id))

# proj source
proj_source <- ffa$ffa_proj_source_points |>
  filter(week != 0, week <= WEEK, season == SEASON) |>
  filter(timestamp == max(timestamp), .by = c(season, week)) |>
  # select(-timestamp, -tag) |>
  inner_join(id_map, join_by(id))

# point hist
points <- stt$nfl_players_points |>
  filter(week != 0) |>
  inner_join(id_map, join_by(playerId)) |>
  inner_join(select(ply$nfl_players, playerId, pos = position),
             by = join_by(playerId)) |>
  mutate(pos = if_else(pos == "DEF", "DST", pos))

# proj errors
source("./R/transformation/simulation.R")
errors <- calcProjectionErrors(SEASON, 1:WEEK)
proj_w_errors <- applyErrorToProjection(proj_source, errors)

# 1 PTS SEEDS ####

cli::cli_progress_bar("Generating Seeds...", total = 15)

# OS VALORES DA PROJETABLE - 1 PTS por AVG TYPE
dudes_simSeeds <- proj_table |>
  mutate(simType = paste0("proj_table_", avg_type),
         seeds = map(points, c)) |>
  select(-avg_type, -points)

cli::cli_progress_update()

# O VALOR DO PROJ_SOURCE DA NFL - 1 PTS
dudes_simSeeds <- proj_source |>
  filter(data_src == "NFL") |>
  mutate(simType = data_src,
         seeds = map(points, c)) |>
  select(-data_src, -points, -tag, -timestamp) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# N PTS SEEDS ####

# MONTECARLO (PROJ SOURCE) => N
dudes_simSeeds <- proj_source |>
  nest(points = points,
       .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src",
         seeds = map(points, ~ .x$points)) |>
  select(-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# MONTECARLO (PROJ SOURCE ERRORS) => N
dudes_simSeeds <- proj_w_errors |>
  nest(points = c(points),
       .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_errors",
         seeds = map(points, ~ .x$points)) |>
  select(-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# MONTECARLO (PROJ SOURCE + ERRORS) => N
dudes_simSeeds <- bind_rows(
  select(proj_source, season, week, id, pos, playerId, points),
  select(proj_w_errors, season, week, id, pos, playerId, points)
) |> nest(points = points,
        .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_w_errors",
         seeds = map(points, ~ .x$points)) |>
  select(-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# SAMPLING FROM DENSITY(PROJ SOURCE) => N
dudes_simSeeds <- proj_source |>
  nest(points = points,
       .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_density",
         seeds = map(points, \(pts) {
           if (nrow(pts) < 2)
             return(pts$points)
           den <- density(pts$points)
           i <-
             sample(length(den$x), 100, replace = T, prob = den$y)
           return(den$x[i])
         })) |>
  select(-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# SAMPLING FROM DENSITY(PROJ SOURCE ERRORS) => N

dudes_simSeeds <- proj_w_errors |>
  nest(points = c(points),
       .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_errors_density",
         seeds = map(points, \(pts) {
           if (nrow(pts) < 2)
             return(pts$points)
           den <- density(pts$points)
           i <-
             sample(length(den$x), 100, replace = T, prob = den$y)
           return(den$x[i])
         })) |>
  select(-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# SAMPLING FROM DENSITY(PROJ SOURCE + ERRORS) => N
dudes_simSeeds <- bind_rows(
  select(proj_source, season, week, id, pos, playerId, points),
  select(proj_w_errors, season, week, id, pos, playerId, points)
) |> nest(points = points,
          .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_w_errors_density",
         seeds = map(points, \(pts) {
           if (nrow(pts) < 2)
             return(pts$points)
           den <- density(pts$points)
           i <-
             sample(length(den$x), 100, replace = T, prob = den$y)
           return(den$x[i])
         })) |>
  select(-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# MONTECARLO (HISTORICAL DATA) => N
dudes_simSeeds <- 1:WEEK |>
  map_df(\(.WEEK, .SEASON, .points) {
    .points |>
      filter(season < .SEASON |
               (season == .SEASON & week < .WEEK)) |>
      filter(week != 0) |>
      nest(pts = pts, .by = c(id, playerId, pos)) |>
      mutate(simType = "hist_data",
             seeds = map(pts, ~ .x$pts)) |>
      select(-pts) |>
      mutate(season = .SEASON, week = .WEEK)
  }, .SEASON = SEASON, .points = points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# SAMPLING FROM DENSITY(HISTORICAL_DATA) => N
dudes_simSeeds <- 1:WEEK |>
  map_df(\(.WEEK, .SEASON, .points) {
    .points |>
      filter(season < .SEASON |
               (season == .SEASON & week < .WEEK)) |>
      filter(week != 0) |>
      nest(pts = pts, .by = c(id, playerId, pos)) |>
      mutate(simType = "hist_data_density",
             seeds = map(pts, \(pts) {
               if (nrow(pts) < 2)
                 return(pts$pts)
               den <- density(pts$pts)
               i <-
                 sample(length(den$x), 100, replace = T, prob = den$y)
               return(den$x[i])
             })) |>
      select(-pts) |>
      mutate(season = .SEASON, week = .WEEK)
  }, .SEASON = SEASON, .points = points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# MONTECARLO (PROJ SOURCE*BALANCED + ERRORS) +  => N
dudes_simSeeds <-
  inner_join(
    # projecoes com erro
    proj_w_errors |>
      nest(
        projPtsErrors = points,
        .by = c(season, week, id, playerId, pos)
      ) |>
      mutate(projPtsErrors = map(projPtsErrors, ~ .x$points)),
    # projecoes da semana
    proj_source |>
      nest(
        points = points,
        .by = c(season, week, id, playerId, pos)
      ) |>
      mutate(points = map(points, ~ .x$points)),
    # join
    by = join_by(season, week, id, playerId, pos)
  ) |>
  mutate(simType = "proj_src_w_errors_balanced",
         seeds = map2(projPtsErrors, points, \(ptsA, ptsB) {
           # tamanho dos vetores
           lenA <- length(ptsA)
           lenB <- length(ptsB)
           
           # retorna vetores de igual representacao
           if (lenA == lenB)
             return(c(ptsA, ptsB))
           if (lenA > lenB)
             return(c(ptsA, ptsB, sample(ptsB, lenA - lenB, replace = T)))
           if (lenA < lenB)
             return(c(ptsA, ptsB, sample(ptsA, lenB - lenA, replace = T)))
           
         })) |>
  select(-projPtsErrors,-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# DENSITY (PROJ SOURCE*BALANCED + ERRORS) => N
dudes_simSeeds <-
  inner_join(
    # projecoes com erro
    proj_w_errors |>
      nest(
        projPtsErrors = points,
        .by = c(season, week, id, playerId, pos)
      ) |>
      mutate(projPtsErrors = map(projPtsErrors, ~ .x$points)),
    # projecoes da semana
    proj_source |>
      nest(
        points = points,
        .by = c(season, week, id, playerId, pos)
      ) |>
      mutate(points = map(points, ~ .x$points)),
    # join
    by = join_by(season, week, id, playerId, pos)
  ) |>
  mutate(simType = "proj_src_w_errors_balanced_density",
         seeds = map2(projPtsErrors, points, \(ptsA, ptsB) {
           # 100 sampling from ptsA set
           if (length(ptsA) < 2) {
             respA <- rep(ptsA, 100)
           } else {
             denA <- density(ptsA)
             iA <-
               sample(length(denA$x),
                      100,
                      replace = T,
                      prob = denA$y)
             respA <- denA$x[iA]
           }
           
           # 100 sampling from ptsB set
           if (length(ptsB) < 2) {
             respB <- rep(ptsB, 100)
           } else {
             denB <- density(ptsB)
             iB <-
               sample(length(denB$x),
                      100,
                      replace = T,
                      prob = denB$y)
             respB <- denB$x[iB]
           }
           
           denAB <- density(c(respA, respB))
           iAB <-
             sample(length(denAB$x), 100, replace = T, prob = denAB$y)
           
           # retorna os dois samplings
           return(denAB$x[iAB])
           
         })) |>
  select(-projPtsErrors,-points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# MONTECARLO (CURRENT SEASON PERF) => N
dudes_simSeeds <- 1:WEEK |>
  map_df(\(.WEEK, .SEASON, .points) {
    .points |>
      filter(season == .SEASON & week < .WEEK) |>
      filter(week != 0) |>
      nest(pts = pts, .by = c(id, playerId, pos)) |>
      mutate(simType = "current_season_his",
             seeds = map(pts, ~ .x$pts)) |>
      select(-pts) |>
      mutate(season = .SEASON, week = .WEEK)
  }, .SEASON = SEASON, .points = points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# SAMPLING FROM DENSITY(CURRENT SEASON PERF) => N
dudes_simSeeds <- 1:WEEK |>
  map_df(\(.WEEK, .SEASON, .points) {
    .points |>
      filter(season == .SEASON & week < .WEEK) |>
      filter(week != 0) |>
      nest(pts = pts, .by = c(id, playerId, pos)) |>
      mutate(simType = "current_season_his_density",
             seeds = map(pts, \(pts) {
               if (nrow(pts) < 2)
                 return(pts$pts)
               den <- density(pts$pts)
               i <-
                 sample(length(den$x), 100, replace = T, prob = den$y)
               return(den$x[i])
             })) |>
      select(-pts) |>
      mutate(season = .SEASON, week = .WEEK)
  }, .SEASON = SEASON, .points = points) |>
  bind_rows(dudes_simSeeds)

cli::cli_progress_update()

# MIX DENSITY PROJ_SOURCE_W_ERRORS + CURRENT_PERFORMANCE
dudes_simSeeds <-
  dudes_simSeeds |>
  filter(
    simType %in% c(
      "current_season_his_density",
      "proj_src_errors_density",
      "proj_src_density"
    )
  ) |>
  mutate(seeds = map(seeds, \(sds) {
    if (length(sds) != 100) {
      return(sample(sds, size = 100, replace = T))
    } else {
      return(sds)
    }
  })) |>
  pivot_wider(
    id_cols = c(season, week, id, playerId, pos),
    names_from = simType,
    values_from = seeds,
    values_fn = c
  ) |>
  mutate(
    seeds = map2(proj_src_density, proj_src_errors_density, c),
    seeds = map2(seeds, current_season_his_density, c),
    simType = "proj_src_w_error_current_season_density"
  ) |>
  select(season, week, id, playerId, pos, simType, seeds) |>
  bind_rows(dudes_simSeeds) |>
  arrange(season, week, id, playerId, pos, simType)

cli::cli_progress_done()

# REMOVE BYE WEEK SEEDS 
dudes_players_seeds <- dudes_simSeeds |>
  anti_join(bye_week, by = join_by(season, week, id, playerId))

# perform simulations
oneValueSimType <-
  c("NFL",
    "proj_table_average",
    "proj_table_robust",
    "proj_table_weighted")

dudes_players_simulations <- dudes_players_seeds |> 
  filter( ! simType %in% oneValueSimType ) |> 
  mutate( simulation = map(seeds, sample, size=1000, replace=T, .progress="Resampling Seeds") ) |> 
  mutate( simQuantiles = map(seeds, \(.seeds){
    .seeds |> 
      quantile(c(0.05,.15,.30,.50,.7,.85,.95)) |> 
      enframe() 
  }, .progress="Summarising Data") ) |> 
  select(-seeds)


# SAVE DATABASE ####
simDB <-  dm(dudes_players_seeds, dudes_players_simulations) |> 
  dm_add_pk(dudes_players_seeds, c(season, week, id, playerId, pos, simType)) |> 
  dm_add_pk(dudes_players_simulations, c(season, week, id, playerId, pos, simType))

dm_draw(simDB, view_type = "all", column_types = T)

updateDB(simDB, "./data/dudes_simulation_db.rds")

