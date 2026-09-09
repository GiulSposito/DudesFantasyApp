# Web bundle - projections/source_projections.parquet (contract section 23) +
# projections/source_accuracy.parquet (contract section 24).

library(tidyverse)

build_source_projections <- function(src, run) {
  xref <- src$analytical_db$player_ids |> distinct(ffa_id, espn_id, nfl_id)

  espn_nm <- src$espn_db$espn_players |>
    filter(season == run$season) |>
    transmute(espn_id = player_id, espn_name = player_name, espn_team = pro_team)

  ffa_nm <- src$ffa_db$ffa_players |>
    transmute(ffa_id = as.integer(id),
              ffa_name = str_squish(paste(first_name, last_name)),
              ffa_team = team) |>
    distinct(ffa_id, .keep_all = TRUE)

  src$ffa_db$ffa_proj_source_points |>
    filter(season == run$season, week == run$week, tag == run$tag,
           timestamp == run$ffa_timestamp) |>
    mutate(ffa_id = suppressWarnings(as.integer(id))) |>
    filter(!is.na(ffa_id)) |>
    left_join(xref, by = "ffa_id") |>
    left_join(espn_nm, by = "espn_id") |>
    left_join(ffa_nm, by = "ffa_id") |>
    transmute(
      run_id = run$run_id,
      ffa_id, espn_id,
      player_name = coalesce(espn_name, ffa_name),
      position = pos,
      nfl_team = coalesce(espn_team, ffa_team),
      data_src,
      projected_points = points
    ) |>
    distinct(run_id, ffa_id, position, data_src, .keep_all = TRUE)
}

build_source_accuracy <- function(src, run) {
  src$analytical_db$source_errors |>
    transmute(
      season, data_src,
      position = pos,
      bias, mae, rmse, n
    )
}
