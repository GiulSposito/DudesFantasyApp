# Web bundle - runs.parquet (contract section 10).
# 1 row = 1 decision engine run. is_current flags the resolved run.

library(tidyverse)

build_runs <- function(src, run) {
  src$decision_db$simulation_runs |>
    mutate(is_current = run_id == run$run_id) |>
    arrange(desc(created_at))
}
