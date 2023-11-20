# SCRIPT PARA GERAR VARIAS ESTRATEGIAS DE SIMULACAO E AVALIAR O OUTCOME
library(dm)
library(tidyverse)
# PARA CADA JOGADOR COM PONTO NA TEMPORADA 2023

# MASTER PARAMETERS ####
WEEK <- 11
SEASON <- 2023

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

dudes_players_seeds <- dudes_simSeeds |>
  anti_join(bye_week, by = join_by(season, week, id, playerId))
  # mutate(seedStats = map(seeds, \(.x) {
  #   if (length(.x) < 2)
  #     return(NULL)
  #   if (length(unique(.x)) <= 2)
  #     return(NULL)
  #   return(broom::tidy(t.test(.x)))
  # },
  # .progress = T))


# SAVE DATABASE ####
simDB <-  dm(dudes_simSeeds) |> 
  dm_add_pk(dudes_simSeeds, c(season, week, id, playerId, pos, simType))

updateDB(simDB, "./data/dudes_simulation.rds")

# TEST & DRAFTS ####
oneValueSimType <-
  c("NFL",
    "proj_table_average",
    "proj_table_robust",
    "proj_table_weighted")

dudes_players_simulations <- dudes_players_seeds |> 
  filter( ! simType %in% oneValueSimType ) |> 
  mutate( simulation = map(seeds, sample, size=1000, replace=T, .progress="Resampling Seeds") ) |> 
  mutate( summ = map(seeds, \(.seeds){
    .seeds |> 
      quantile(c(0.05,.25,.30,.50,.7,.75,.95)) |> 
      enframe() 
  }, .progress="Summarising Data") )


dudes_players_simulations

nfl_round_db <- readRDS("./data/nfl_round_db.rds")
stt$nfl_players_points
ply$nfl_players

roster_sim <- nfl_round_db$nfl_teams_rosters |> 
  filter(timestamp==max(timestamp), .by = c(season, week, teamId)) |> 
  filter(teamId==4, season==2023, week==11) |> 
  inner_join(dudes_players_simulations,by = join_by(season, week, playerId)) |> 
  select(-tag, -timestamp, -slotPosition, -isEditable, -isReserveStatus) |> 
  filter(simType=="proj_src_errors_density") 

roster_pts <- nfl_round_db$nfl_teams_rosters |> 
  filter(timestamp==max(timestamp), .by = c(season, week, teamId)) |> 
  select(season, week, teamId, rosterSlotId, playerId) |> 
  left_join(stt$nfl_players_points,by = join_by(season, week, playerId)) |> 
  mutate( pts = if_else(is.na(pts), 0, pts)) |> 
  left_join(select(ply$nfl_players, playerId, name, position), by = join_by(playerId))

best_pos <- roster_sim  |>
  select(playerId1 = playerId) |>
  expand_grid(playerId2 = playerId1) |>
  inner_join(select(roster_sim, playerId1 = playerId, pos1 = pos),
             by = join_by(playerId1)) |>
  inner_join(select(roster_sim, playerId2 = playerId, pos2 = pos),
             by = join_by(playerId2)) |>
  filter(pos1 == pos2, playerId1 < playerId2) |>
  mutate(best = map2_int(playerId1, playerId2,
                        function(id1, id2, sim) {
                          s1 <- sim |> filter(playerId == id1) |> pull(simulation)
                          s2 <-
                            sim |> filter(playerId == id2) |> pull(simulation)
                          if (mean(s1[[1]] > s2[[1]]) > .5) {
                            return(id1)
                          } else {
                            return(id2)
                          }
                        }, sim = roster_sim)) |>
  count(pos1, best, sort = T) |> 
  set_names(c("pos", "playerId", "rank"))

roster_remaing <- roster_sim |> 
  anti_join(best_pos, by = join_by(playerId, pos)) |> 
  filter(rosterSlotId < 20) |> 
  transmute(pos, playerId, rank=1)

best_roster <- best_pos |> 
  bind_rows(roster_remaing) |> 
  arrange(desc(rank)) |> 
  left_join( filter(stt$nfl_players_points, season==2023, week==11), by = join_by(playerId) )

best_roster

best_roster[c(1:6,8,10,11),]$pts |> sum(na.rm = T)

tibble(
  pos = c("QB", "WR", "RB", "TE", "K", "DST"),
  
)


best_pos
  
split(best_pos, 1:nrow(best_pos))



nfl_round_db$nfl_teams_round

nfl_teams_db <- readRDS("./data/nfl_teams_db.rds")
nfl_teams_db$nfl_teams

dudes_players_simulations |> 
  inner_join(```)





dudes_players_simulations |>
  unnest( summ ) |> 
  pivot_wider(id_cols=c(season, week, id, playerId, pos, simType),
              names_from = name, 
              values_from = value) |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  ggplot(aes(x=`75%`, y=pts, color=simType))+
  geom_point(alpha=.3) +
  stat_smooth(method = "lm", se=F) +
  theme_light()
dudes_players_simulations |> 

library(ggridges)

  filter(id == "14136", week==10, season==SEASON) |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  unnest(summ) |>
  filter( name=="50%" ) |> 
  mutate(simType = fct_reorder(simType, value)) |> 
  select(simType, simulation, value, pts) |> 
  unnest(simulation) |> 
  ggplot(aes(x=simulation, y=simType, fill=simType)) +
  geom_density_ridges(scale = 2,
                      color = "white",
                      alpha = .7) +  
  geom_vline(xintercept = 0, color="grey", linetype="dashed") +
  geom_hline(aes(yintercept=simType, color=simType),alpha=.3) +
  geom_point(aes(x=value, y=simType), shape=24, color="red", fill="red", show.legend = F, alpha=.5) +
  geom_point(aes(x=pts, y=simType), shape=24, color="black", fill="black", show.legend = F, alpha=.5) +
  theme_light()
  

fit_models <- dudes_players_simulations |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  select(-seeds, -simulation) |> 
  unnest(summ) |> 
  filter(name=="50%") |> 
  nest(data=c(value, pts), .by=c(simType)) |> 
  mutate( lm = map(data, \(.x) lm(pts~value, .x), .progress=T)) |> 
  mutate( stats = map(lm, broom::augment, .progress=T) ) |> 
  unnest( stats )


dudes_players_simulations |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  select(-seeds, -simulation) |> 
  unnest(summ) |> 
  filter( name %in% c("30%", "70%")) |> 
  mutate( name = str_c("p", str_remove(name, "%"))) |> 
  pivot_wider(
    id_cols=c(season, week, id, playerId, pos, simType, pts),
    names_from = name, 
    values_from = value) |> 
  group_by(simType) |> 
  summarise( in_range=mean(pts>=p30 & pts<=p70) ) |> 
  arrange(desc(in_range))



fit_models |> 

tibble(
  pred = fit_models[1,]$lm[[1]]$fitted.values,
  real = fit_models[1,]$lm[[1]]$model$pts
) |> 
  yardstick::rmse(truth=real, estimate=pred)

sqrt(mean(fit_models[1,]$lm[[1]]$residuals^2))

fit_models[1,]$lm[[1]] |> 
  broom::augment()



2^2

?yardstick::rmse()
  
  
  
fit_models |> 
  ggplot(aes(x=p.value, y=r.squared, color=simType)) +
  geom_point(alpha=.5) +
  theme_minimal()


ggplot(aes(
  x = pts.proj,
  y = reorder(full_name,-display.order),
  fill = pos
)) +

  geom_point(aes(x=weekPts), shape=24, color="red", fill="red", show.legend = F, alpha=.8) +
  geom_hline(aes(yintercept=reorder(full_name,-display.order), color=pos),alpha=.3) +
  theme_light() +
  xlab("Fantasy Points") +
  ylab("") +
  theme(legend.position = "bottom") 

  
stt$nfl_players_points |> 
  inner_join(id_map, join_by(playerId)) |> 
  filter(id == "13593", week==WEEK, season==SEASON)
  
  unnest(seeds) |> 
  ggplot(aes(x=seeds, fill=simType)) +
  geom_density(alpha=.5) +
  ggplot2::scale_fill_brewer(type = "qual") +
  theme_light()

plotly::ggplotly(splot)


library(tidyverse)

proj <- list(
  runif(100, 0,10),
  runif(100, 3, 8),
  runif(100, 5,9)
)

tibble(
  id1 = 1:3
) |> 
  expand(id1=id1, id2 = id1) |> 
  filter(id1<id2) |> 
  mutate( win = map2_int(id1, id2, \(i1,i2,prj){
    if(mean(pluck(prj, i1))>mean(pluck(prj, i2))){
      return(i1)
    } else {
      return(i2)
    }
  }, prj = proj)) |> 
  count(win, sort=T)




