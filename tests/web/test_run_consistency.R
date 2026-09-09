# tests/web/test_run_consistency.R - every current/* and projections/* mart
# carrying run_id references exactly the manifest's current run
# (contract section 32.3).

suppressMessages({library(nanoparquet); library(jsonlite)})

FIX <- "./tests/fixtures/web_bundle"
rp  <- function(x) as.data.frame(read_parquet(file.path(FIX, x)))

man <- read_json(file.path(FIX, "manifest.json"))
run_id <- man$current$run_id
stopifnot(!is.null(run_id), nchar(run_id) > 0)

runs <- rp("runs.parquet")
stopifnot(run_id %in% runs$run_id, sum(runs$is_current) == 1L,
          runs$run_id[runs$is_current] == run_id)

files <- list.files(file.path(FIX, c("current", "projections")),
                    pattern = "\\.parquet$", full.names = TRUE)

for (f in files) {
  d <- as.data.frame(read_parquet(f))
  if (!"run_id" %in% names(d) || nrow(d) == 0L) next
  if (any(d$run_id != run_id)) stop(basename(f), ": foreign run_id present")
}

cat("PASS test_run_consistency.R\n")
