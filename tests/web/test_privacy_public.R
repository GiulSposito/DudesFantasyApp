# tests/web/test_privacy_public.R - a public bundle carries no owner/manager
# real-name identifiers, as column OR as value (contract section 36).
# Builds fresh to a temp dir; skips when live data is absent.

suppressMessages({library(tidyverse); library(dm); library(nanoparquet)})

need <- c("./data/decision_db.rds", "./data/espn_db.rds",
          "./data/ffa_db.rds", "./data/analytical_db.rds")
if (!all(file.exists(need))) {
  cat("SKIP test_privacy_public.R (missing data/*.rds)\n")
} else {
  source("./R/web/build_web_bundle.R")
  out <- file.path(tempdir(), paste0("web_pub_", as.integer(Sys.time())))
  suppressWarnings(build_web_bundle(output_dir = out, privacy = "public"))

  members <- readRDS("./data/espn_db.rds")$espn_members
  full_nm <- str_squish(paste(members$first_name, members$last_name))
  banned  <- unique(stats::na.omit(c(members$display_name, full_nm)))
  banned  <- banned[nchar(banned) > 1]

  files <- list.files(out, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
  for (f in files) {
    d <- as.data.frame(read_parquet(f))
    if ("owner_name" %in% names(d)) stop(basename(f), " still has owner_name")
    chr <- d[vapply(d, is.character, logical(1))]
    hit <- intersect(unlist(chr, use.names = FALSE), banned)
    if (length(hit)) stop(basename(f), " leaks member name value(s): ",
                          paste(head(hit, 3), collapse = ", "))
  }

  cat("PASS test_privacy_public.R\n")
}
