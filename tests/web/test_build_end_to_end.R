# tests/web/test_build_end_to_end.R - build the full bundle from the live .rds
# databases and run the validation gate. Skips when the databases are absent
# (mirrors tests/decision/test_pipeline_integration.R).

suppressMessages({library(tidyverse); library(dm)})

need <- c("./data/decision_db.rds", "./data/espn_db.rds",
          "./data/ffa_db.rds", "./data/analytical_db.rds")
if (!all(file.exists(need))) {
  cat("SKIP test_build_end_to_end.R (missing data/*.rds)\n")
} else {
  source("./R/web/build_web_bundle.R")
  out <- tempfile("web_bundle_")
  suppressWarnings(build_web_bundle(output_dir = out, validate = TRUE))

  stopifnot(
    file.exists(file.path(out, "manifest.json")),
    isTRUE(validate_web_bundle(out))
  )

  cat("PASS test_build_end_to_end.R\n")
}
