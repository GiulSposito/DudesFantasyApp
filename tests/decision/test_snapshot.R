# tests/decision/test_snapshot.R - snapshot selection + FFA quality guard.
# Standalone: source() from the project root. Uses stopifnot(), no framework.

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/snapshot.R")

# --- fixture: two timestamps for the same season/week/tag --------------------
mk <- function(ts, src, pts) tibble(
  season = 2025L, week = 3L, tag = "preview", timestamp = as.POSIXct(ts, tz = "UTC"),
  data_src = src, id = "100", pos = "WR", points = pts
)
fix <- bind_rows(
  mk("2025-09-01 10:00", "CBS", 10), mk("2025-09-01 10:00", "ESPN", 12),
  mk("2025-09-02 09:00", "CBS", 20), mk("2025-09-02 09:00", "ESPN", 22)   # newer
)
ffa_db <- dm(ffa_proj_source_points = fix)

snap <- select_ffa_snapshot(ffa_db, 2025, 3, "preview")
stopifnot(
  snap$timestamp == as.POSIXct("2025-09-02 09:00", tz = "UTC"),
  nrow(snap$proj_source) == 2,                       # only newest timestamp's rows
  all(snap$proj_source$proj_points %in% c(20, 22)),
  is.integer(snap$proj_source$ffa_id), snap$proj_source$ffa_id[1] == 100L
)

# --- missing snapshot errors -----------------------------------------------
err <- tryCatch(select_ffa_snapshot(ffa_db, 2025, 9, "preview"), error = conditionMessage)
stopifnot(grepl("not found in ffa_db", err))

# --- quality guard: duplicate data_src/ffa_id/pos ---------------------------
dup <- bind_rows(mk("2025-09-02 09:00", "CBS", 20), mk("2025-09-02 09:00", "CBS", 21)) |>
  mutate(ffa_id = as.integer(id), proj_points = points)
derr <- tryCatch(check_ffa_snapshot_quality(dup), error = conditionMessage)
stopifnot(grepl("duplicated", derr))

# clean snapshot passes
stopifnot(isTRUE(check_ffa_snapshot_quality(
  mutate(snap$proj_source)
)))

cat("PASS test_snapshot.R\n")
