# SCRIPT PARA GERAR VARIAS ESTRATEGIAS DE SIMULACAO E AVALIAR O OUTCOME
library(dm)
library(tidyverse)
# PARA CADA JOGADOR COM PONTO NA TEMPORADA 2023

# semena alvo
WEEK <- 7
SEASON <- 2023

# DATABASES
ffa <- readRDS("./data/ffa_db.rds") # projecoes
stt <- readRDS("./data/nfl_stats_db.rds") # pontuacao

# id-map
id_map <- ffa$ffa_player_ids |>
  transmute(id, playerId = as.integer(nfl_id))

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
  inner_join(id_map, join_by(playerId))

# proj errors
source("./R/transformation/simulation.R")
errors <- calcProjectionErrors(SEASON, 1:WEEK)
proj_w_errors <- applyErrorToProjection(proj_source, errors)


# OS VALORES DA PROJETABLE - 1 PTS por AVG TYPE
simulations <- proj_table |>
  mutate(simType = paste0("proj_table_", avg_type),
         seeds = map(points, c)) |>
  select(-avg_type,-points)

# O VALOR DO PROJ_SOURCE DA NFL - 1 PTS
simulations <- proj_source |>
  filter(data_src == "NFL") |>
  mutate(simType = data_src,
         seeds = map(points, c)) |>
  select(-data_src,-points,-tag,-timestamp) |>
  bind_rows(simulations)

# MONTECARLO (PROJ SOURCE) => N
simulations <- proj_source |>
  nest(points = points,
       .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src",
         seeds = map(points, ~ .x$points)) |>
  select(-points) |>
  bind_rows(simulations)

# MONTECARLO (PROJ SOURCE ERRORS) => N
simulations <- proj_w_errors |>
  nest(points = c(points),
       .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_errors",
         seeds = map(points, ~ .x$points)) |>
  select(-points) |>
  bind_rows(simulations)

# MONTECARLO (PROJ SOURCE + ERRORS) => N
simulations <- bind_rows(
  select(proj_source, season, week, id, pos, playerId, points),
  select(proj_w_errors, season, week, id, pos, playerId, points)
) |> nest(points = points,
          .by = c(season, week, id, pos, playerId)) |>
  mutate(simType = "proj_src_w_errors",
         seeds = map(points, ~ .x$points)) |>
  select(-points) |>
  bind_rows(simulations)

# SAMPLING FROM DENSITY(PROJ SOURCE) => N
simulations <- proj_source |>
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
  bind_rows(simulations)

# SAMPLING FROM DENSITY(PROJ SOURCE ERRORS) => N

simulations <- proj_w_errors |>
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
  bind_rows(simulations)

# SAMPLING FROM DENSITY(PROJ SOURCE + ERRORS) => N
simulations <- bind_rows(
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
  bind_rows(simulations)

# MONTECARLO (HISTORICAL DATA) => N
simulations <- points |>
  filter(season < SEASON | (season == SEASON & week < WEEK)) |>
  filter(week != 0) |>
  nest(pts = pts, .by = c(id, playerId)) |>
  mutate(simType = "hist_data",
         seeds = map(pts, ~ .x$pts)) |>
  select(-pts) |>
  mutate(season = SEASON, week = WEEK) |>
  bind_rows(simulations)

# SAMPLING FROM DENSITY(HISTORICAL_DATA) => N

simulations <- points |>
  filter(season < SEASON | (season == SEASON & week < WEEK)) |>
  filter(week != 0) |>
  nest(pts = pts, .by = c(id, playerId)) |>
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
  mutate(season = SEASON, week = WEEK) |>
  bind_rows(simulations)

# MONTECARLO (PROJ SOURCE*BALANCED + ERRORS) +  => N

simulations <-
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
  select(-projPtsErrors, -points) |>
  bind_rows(simulations)


# DENSITY (PROJ SOURCE*BALANCED + ERRORS) => N
simulations <-
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
           if(length(ptsA)<2) {
             respA <- rep(ptsA, 100)             
           } else {
             denA <- density(ptsA)
             iA <- sample(length(denA$x), 100, replace = T, prob = denA$y)
             respA <- denA$x[iA]
           }
           
           # 100 sampling from ptsB set
           if(length(ptsB)<2) {
             respB <- rep(ptsB, 100)             
           } else {
             denB <- density(ptsB)
             iB <- sample(length(denB$x), 100, replace = T, prob = denB$y)
             respB <- denB$x[iB]
           }
           
           # retorna os dois samplings
           return(c(respA, respB))

         })) |>
  select(-projPtsErrors, -points) |>
  bind_rows(simulations)



splot <- simulations |>
  filter(id == "13593") |>
  filter(week == 7) |> 
  unnest(seeds) |> 
  ggplot(aes(x=seeds, fill=simType)) +
  geom_density(alpha=.5) +
  ggplot2::scale_fill_brewer(palette = "Set1") +
  theme_light()

plotly::ggplotly(splot)
