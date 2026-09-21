library(tidyverse)
library(dm)

ffa <- readRDS("./data/ffa_db.rds")
nfl <- readRDS("./data/nfl_stats_db.rds")

proj <- ffa$ffa_projtable |> 
  filter(week!=0, season==2023) |>
  group_by(week) |> 
  filter(timestamp==max(timestamp)) |> 
  ungroup()

pts <- nfl$nfl_players_points |> 
  filter(week!=0, season==2023)

id_map <- ffa$ffa_player_ids |> 
  select(id, nfl_id) |> 
  transmute(id, playerId=as.integer(nfl_id))

raw_dt <- proj |> 
  inner_join(id_map, by = join_by(id)) |>
  inner_join(pts, by = join_by(season, week, playerId))

raw_dt |> 
  ggplot(aes(points, pts, color=pos)) +
  geom_point() +
  facet_grid(rows=vars(week), cols=vars(pos)) +
  theme_minimal()


dt <- raw_dt |>
  arrange(week, id, pos) |>
  select(-season, -tag, -timestamp, -playerId) |>
  # select(id, pos, week, avg_type, points, sd_pts) |>
  pivot_wider(
    id_cols = c(week, id, pos, pos_ecr, sd_ecr, pts),
    names_from = avg_type,
    values_from = c(points, sd_pts, dropoff, floor, ceiling, points_vor, floor_vor,
                    ceiling_vor, rank, floor_rank, ceiling_rank, pos_rank, tier,
                    uncertainty)
  )

library(tidymodels)

stat_split <- initial_split(dt, strata = pos)
stat_tr <- training(stat_split)
stat_ts <- testing(stat_split)

stat_rec <- stat_tr |> 
  recipe(pts~.) |> 
  update_role(id, new_role = "ID") |> 
  step_dummy(pos) |> 
  prep()

stat_rec |> juice() |> 
  skimr::skim()

pts_spec <- linear_reg(penalty = 0.1, mixture = 1) |> 
  set_engine("glmnet")

wf <- workflow(stat_rec, pts_spec)

fit <- fit(wf, stat_tr)

y_hat <- predict(fit, new_data = stat_ts)

y_hat |> 
  bind_cols(stat_ts) |> 
  #metrics(truth=pts, estimate=.pred) |> 
  ggplot(aes(x=pts, y=.pred, color=pos)) +
  geom_point() +
  theme_minimal()

fit |> 
  extract_fit_engine() |> 
  vip::vip()




