library(dm)
library(tidyverse)

## normalize FFA Predictions ####

# load
ffa_db <- readRDS("./data/ffa_db.rds")
ffa_hist <- readRDS("./historic/ffa_db.rds")

# season/weeks
ffa_hist$ffa_proj_source_points |>
  distinct(season, week, data_src) |> 
  count(season, week) |> 
  pivot_wider(id_cols = season, names_from=week, values_from = n)

# season/weeks
ffa_db$ffa_proj_source_points |> 
  distinct(season, week, data_src) |> 
  count(season, week) |> 
  pivot_wider(id_cols = season, names_from=week, values_from = n)

# union
ffa_projection_source <- bind_rows(
    mutate(ffa_hist$ffa_proj_source_points,week=as.integer(week)),
    ffa_db$ffa_proj_source_points
  ) |> 
  select(season, week, tag, timestamp, data_src, ffa_id=id, pos, proj_points=points) |> 
  mutate(ffa_id = as.integer(ffa_id)) |> 
  filter(!is.na(proj_points)) |> 
  distinct() |> 
  filter(season!=2026, week!=0) |> 
  filter(!(pos %in% c("FB", "Kenneth Walker III"))) # polution coming from somewhere

# quantas fontes distintas por semana?
ffa_projection_source |> 
  distinct(season, week, data_src) |> 
  count(season, week) |> 
  pivot_wider(id_cols = season, names_from=week, values_from = n)

# ACTUAL PONTS #####

nfl_stats <- readRDS("./data/nfl_stats_db.rds")
nfl_hist <- readRDS("./historic/nfl_stats_db.rds")

nfl_stats$nfl_players_points |> 
  filter(!is.na(pts)) |> 
  distinct(season,week) |> 
  count(season)

nfl_hist$nfl_players_points |> 
  filter(!is.na(pts)) |> 
  distinct(season,week) |> 
  count(season)

# actual points 
nfl_player_points <- bind_rows(
  nfl_stats$nfl_players_points,
  nfl_hist$nfl_players_points
) |> 
  filter(!is.na(pts)) |> 
  rename(nfl_id=playerId, points=pts) |> 
  distinct()


## common keys 
player_ids <- ffa_db$ffa_player_ids |> 
  select(ffa_id=id, nfl_id, espn_id, numfire_id) |> 
  mutate(
    ffa_id = as.integer(ffa_id),
    nfl_id = as.integer(nfl_id), 
    espn_id = as.integer(espn_id)
  ) |> 
  distinct()

## tabelas governandas
ffa_projection_source |> nrow()
nfl_player_points |> nrow()
player_ids |> nrow()

# COMPLETUDE DE CHAVES ######

# missing players in FFA (tem estatística na NFL mas não tem ID no FFA)
nfl_players <- readRDS("./data/nfl_players_db.rds")
nfl_player <- nfl_players$nfl_players |> select(nfl_id=playerId, firstName, lastName, position)
nfl_player_points |> 
  anti_join(player_ids, by = join_by(nfl_id)) |> 
  inner_join(nfl_player, by = join_by(nfl_id)) |> 
  distinct(nfl_id, firstName, lastName, position)

# missing players in NFL (tem ID no FFA mas não tem estatísca na NFL)
player_ids |> 
  anti_join(nfl_player_points, by = join_by(nfl_id))

# pegando a ultimo registro de cada semana não importa a tag #####
ffa_projection_source

# ESCOLHENDO BASELINE DE PROJECAO #####
last_weekly_tag_ts<- ffa_projection_source |> 
  select(season, week, tag, timestamp) |> 
  distinct() |> 
  group_by(season, week) |> 
  filter(timestamp==max(timestamp)) |> # qual é a tag que tem a data mais antiga da semana 
  ungroup()

# filtra por temporada, semana, tag e timestamp que é o último da semana
last_weekly_projections <- ffa_projection_source |> 
  inner_join(last_weekly_tag_ts,by = join_by(season, week, tag, timestamp)) |> 
  select(-tag, -timestamp)
  
# teste de cobertura por source
last_weekly_projections |> 
  distinct(season, week, data_src) |> 
  count(season,week) |> 
  pivot_wider(id_cols=season, names_from=week, values_from=n)

# teste de cobertura por position
last_weekly_projections |> 
  distinct(season, data_src, pos) |> 
  count(season,data_src) |> 
  pivot_wider(id_cols=season, names_from=data_src, values_from=n)

# check se projeções são corrigidas para alguam source
last_weekly_projections |> 
  count(season, week) |> 
  pivot_wider(id_cols=season, names_from=week, values_from=n)


# Estudando se as projeções são corrigidas pós pontuação
last_weekly_projections |> 
  left_join(player_ids, by = join_by(ffa_id)) |> 
  left_join(nfl_player_points) |> 
  filter(proj_points==points) |> 
  filter(points!=0) |> 
  count(data_src, season, week, sort=T) 

# Há uma suspeita nas semanas 16 da tempora 24 e 25 da CBS
# removendo
ffa_projections <- last_weekly_projections |> 
  filter(!(data_src == "CBS" & season %in% c(2024, 2025) & week == 16))

# quantas fontes por semana?
ffa_projections |> 
  distinct(season, week, data_src) |>
  count(season, week) |> 
  pivot_wider(id_cols=season, names_from=week, values_from=n)

# base analitica
ffa_projections
nfl_player_points
player_ids

projections_errors <- player_ids |> 
  inner_join(ffa_projections, by = join_by(ffa_id)) |> 
  inner_join(nfl_player_points, by = join_by(nfl_id, season, week)) |> 
  mutate( error = points - proj_points,
          abs_error = abs(error), 
          squared_error = error^2 )

source_errors <- projections_errors |>
  summarise(
    bias = mean(error),
    mae = mean(abs_error),
    rmse = sqrt(mean(squared_error)),
    n = n(),
    .by = c(data_src, pos, season)
  ) |> 
  arrange(data_src, pos, season)

consensus_projections <- ffa_projections |>
  summarise(
    # Quantidade e composição das fontes
    n_sources = n_distinct(data_src),
    sources = paste( sort(unique(data_src)), collapse = ", " ),
    
    # Projeção de consenso
    projection = mean(proj_points,na.rm = TRUE),
    
    # Estatísticas descritivas das projeções
    source_median = median(proj_points,na.rm = TRUE),
    source_sd = if (n_distinct(data_src) >= 2)
      {sd(proj_points, na.rm = TRUE)} else 
      {NA_real_},
    
    source_mad = if (n_distinct(data_src) >= 2)
      {mad(proj_points, na.rm = TRUE)} else 
      {NA_real_},
    
    source_min = min(proj_points, na.rm = TRUE),
    source_max = max(proj_points, na.rm = TRUE),
    
    .by = c(season,week,ffa_id,pos)
  ) |>
  mutate(
    source_range = if_else(
      n_sources >= 2,
      source_max - source_min,
      NA_real_
    )
  )

consensus_error_history <- consensus_projections |>
  inner_join(player_ids, by = join_by(ffa_id)) |>
  inner_join(nfl_player_points, by = join_by(nfl_id, season, week)) |>
  rename(actual_points = points) |>
  mutate(
    residual = actual_points - projection,
    abs_residual = abs(residual),
    squared_residual = residual^2,
    consensus_type = "mean"
  ) |>
  mutate(
    coverage_class = case_when(
      n_sources == 1 ~ "single",
      n_sources <= 3 ~ "sparse",
      TRUE           ~ "ensemble"
    )
  )

# check
consensus_error_history |>
  summarise(
    n = n(),
    bias = mean(residual, na.rm = TRUE),
    mae = mean(abs_residual, na.rm = TRUE),
    rmse = sqrt(mean(squared_residual, na.rm = TRUE)),
    residual_sd = sd(residual, na.rm = TRUE),
    .by = c(pos, coverage_class)
  ) |>
  arrange(pos, coverage_class)

# tabelas governadas
ffa_projections
nfl_player_points
player_ids
source_errors
consensus_projections
consensus_error_history

# analytical database
analytical_dm <- dm(
  # DATA SETS ----------------------------
  ffa_projections = ffa_projections,
  nfl_player_points = nfl_player_points,
  player_ids = player_ids,
  source_errors = source_errors,
  consensus_projections = consensus_projections,
  consensus_error_history = consensus_error_history) |>
  
  # PRIMARY KEYS ---------------------------
  # Uma linha por jogador FFA
  dm_add_pk(player_ids, ffa_id, check = TRUE) |>
  # Uma projeção por jogador/source/semana
  dm_add_pk(ffa_projections, c(season, week, data_src, ffa_id, pos), check = TRUE) |>
  # Um resultado real por jogador NFL/semana
  dm_add_pk(nfl_player_points, c(nfl_id, season, week), check = TRUE) |>
  # Um resumo de performance por source/posição/temporada
  dm_add_pk(source_errors, c(data_src, pos, season), check = TRUE) |>
  # Um consensus por jogador/semana
  dm_add_pk(consensus_projections, c(season, week, ffa_id, pos), check = TRUE) |>
  # Um erro de consensus por jogador/semana
  dm_add_pk(consensus_error_history, c(season, week, ffa_id, pos), check = TRUE) 
  
  # FOREIGN KEYS ---------------------------
  # dm_add_fk(ffa_projections, ffa_id, player_ids, check = TRUE) |> missing ids !!!
  # dm_add_fk(consensus_projections, ffa_id, player_ids, check = TRUE) |>
  # dm_add_fk(consensus_error_history, ffa_id, player_ids, check = TRUE)


# draw a dm ERD to a PNG file. Works around DiagrammeR >= 1.0.11, whose htmlwidget
# renderer fails in the RStudio Viewer with "Layout was not done"; export_svg()
# uses the DOT->SVG path instead. Needs DiagrammeRsvg + rsvg.
dm_draw_png <- function(dm, ..., file, width = 2400) {
  svg <- DiagrammeRsvg::export_svg(dm::dm_draw(dm, ...))
  rsvg::rsvg_png(charToRaw(svg), file, width = width)
  file
}

# persist it
dm_draw_png(ffa_db, view_type = "all", column_types = TRUE, rankdir = "RL", file = "./export/analytical_db.png")
analytical_dm
saveRDS(analytical_dm, "./data/analytical_db.rds")