# tests/web/test_resolve_run.R - resolve_run(): the site's "current" run is the
# newest run of the latest week, so re-processing an older week (made later)
# does not turn the site back to that week.

suppressMessages({library(tidyverse); library(dm)})
source("./R/web/build_web_bundle.R")

ts <- function(x) as.POSIXct(x, tz = "UTC")
runs <- tibble(
  run_id     = c("w7-final", "w8-preTNF", "w8-posTNF", "w1-final-rerun"),
  created_at = ts(c("2026-10-27 08:00", "2026-10-29 20:00", "2026-10-30 07:50", "2026-10-30 09:00")),
  season     = 2026L,
  week       = c(7L, 8L, 8L, 1L)
)
db <- list(simulation_runs = runs)

stopifnot(
  resolve_run(db)$run_id == "w8-posTNF",                  # latest week wins over the later re-run
  resolve_run(db, "w8-preTNF")$run_id == "w8-preTNF",     # explicit run_id still honoured
  inherits(tryCatch(resolve_run(db, "nope"), error = identity), "error")
)
cat("PASS test_resolve_run.R\n")
