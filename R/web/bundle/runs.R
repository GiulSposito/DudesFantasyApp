# Web bundle - runs.parquet (contract section 10).
# 1 row = 1 decision engine run. is_current flags the resolved run.

library(tidyverse)

build_runs <- function(src, run) {
  # last fantasy scoring period (regular season + playoffs), for weeks-left math
  final_period <- src$espn_db$espn_league |>
    filter(season == run$season) |> pull(final_scoring_period)
  src$decision_db$simulation_runs |>
    mutate(is_current = run_id == run$run_id,
           final_scoring_period = as.integer(final_period[1])) |>
    arrange(desc(created_at))
}
