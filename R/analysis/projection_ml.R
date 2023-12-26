library(dm)
library(tidyverse)

ffa <- readRDS("./data/ffa_db.rds")
stt <- readRDS("./data/nfl_stats_db.rds")

map_id <- ffa$ffa_player_ids |> 
  transmute(id, playerId=as.integer(nfl_id))

proj_table <- ffa$ffa_projtable |> 
  filter(timestamp==max(timestamp), .by=c(season, week)) |> 
  arrange(season,week) |> 
  inner_join(map_id, by="id")

proj_table_pts <- proj_table |> 
  inner_join(stt$nfl_players_points, by = join_by(season, week, playerId))

best_avg_type <- proj_table_pts |>
  select(avg_type, points, pts) |>
  nest(data = c(points, pts), .by = avg_type) |>
  mutate(
    lm = map(data, ~lm(pts ~ points, data = .x)),
    mstats = map(lm, broom::glance),
    rmse = map_dbl(lm, ~sqrt(mean(.x$residuals^2)))) |>
  # unnest(mstats) |> 
  filter( rmse==min(rmse)) |>
  pull(avg_type)

proj_table_pts |> 
  skimr::skim()

proj_df <- proj_table_pts |> 
  filter(avg_type == best_avg_type) |> 
  select(-tag, -timestamp, -avg_type) |> 
  mutate( above_proj = as.factor(pts>points))


# LINEAR REG ####

library(tidymodels)

set.seed(1975)
proj_split <- initial_split(proj_df)
proj_tr <- training(proj_split)
proj_ts <- testing(proj_split)

proj_tr |> 
  skimr::skim()

proj_rec <- proj_tr |> 
  recipe(pts ~ .) |> 
  update_role(c(season, week, id, playerId, above_proj), new_role = "id") |> 
  step_nzv(all_numeric_predictors()) |> 
  step_string2factor(all_nominal_predictors()) |> 
  step_impute_knn(c(sd_pts, pos_ecr, sd_ecr, uncertainty)) |> 
  step_corr(all_numeric_predictors()) |> 
  step_dummy(pos)

lm_spec <- linear_reg() 

proj_wf <- workflow(preprocessor = proj_rec, spec = lm_spec)

lm_res <- proj_wf |> 
  fit(data=proj_tr)

predict(lm_res, proj_ts) |> 
  bind_cols(proj_ts) |> 
  metrics(truth=pts,estimate=.pred)

library(vip)
vip(extract_fit_parsnip(lm_res))

lm_res |> 
  extract_fit_parsnip() |> 
  tidy() |> 
  filter(term!="(Intercept)") |> 
  slice_max(abs(estimate), n=10) |> 
  mutate( term = fct_reorder(term, estimate)) |> 
  ggplot(aes(x=estimate, y=term, color=estimate>=0, fill=estimate>=0)) +
  geom_point(size=2) +
  geom_col(width = .05) +
  theme_minimal()
  
# RF ####

proj_rf_spec <- rand_forest(mode = "regression") |> 
  set_engine("ranger",   importance = "impurity")

proj_rf_wf <- workflow(preprocessor = proj_rec, spec = proj_rf_spec)

rf_res <- proj_rf_wf |> 
  fit(data=proj_tr)

predict(rf_res, proj_ts) |> 
  bind_cols(proj_ts) |> 
  metrics(truth=pts,estimate=.pred)

rf_res |> 
  pull_workflow_fit() |> 
  vip()

# LOGISTIC ####

proj_rec <- proj_tr |> 
  recipe(above_proj ~ .) |> 
  update_role(c(season, week, id, playerId, pts), new_role = "id") |> 
  step_nzv(all_numeric_predictors()) |> 
  step_string2factor(all_nominal_predictors()) |> 
  step_impute_knn(c(sd_pts, pos_ecr, sd_ecr, uncertainty)) |> 
  step_corr(all_numeric_predictors()) |> 
  step_dummy(pos)


glm_spec <- logistic_reg()

proj_glm_wf <- workflow(proj_rec, glm_spec) 

glm_res <- proj_glm_wf |> 
  fit(data=proj_tr)

predict(glm_res, proj_ts) |> 
  bind_cols(proj_ts) |> 
  metrics(truth=above_proj,estimate=.pred_class)

predict(glm_res, proj_ts) |> 
  bind_cols(proj_ts) |> 
  conf_mat(truth=above_proj,estimate=.pred_class)

glm_res |> 
  pull_workflow_fit() |> 
  vip()




