# tests/decision/test_consensus.R - consensus math, single-source handling, coverage_class.

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/snapshot.R")
source("./R/decision/current_consensus.R")

row <- function(id, src, pts, pos = "WR") tibble(
  ffa_id = as.integer(id), pos = pos, data_src = src, proj_points = pts
)

# player 1: 4 sources (ensemble); player 2: 1 source (single); player 3: 3 sources (sparse)
ps <- bind_rows(
  row(1, "CBS", 10), row(1, "ESPN", 20), row(1, "NFL", 30), row(1, "FP", 40),
  row(2, "CBS", 12),
  row(3, "CBS", 5, "RB"), row(3, "ESPN", 7, "RB"), row(3, "NFL", 9, "RB")
)
snap <- list(proj_source = ps, season = 2025, week = 4, tag = "preview")
con <- build_current_consensus(snap)

p1 <- con |> filter(ffa_id == 1)
stopifnot(
  p1$projection == mean(c(10, 20, 30, 40)),
  p1$source_median == median(c(10, 20, 30, 40)),
  p1$n_sources == 4L, p1$coverage_class == "ensemble",
  p1$source_range == 30
)

p2 <- con |> filter(ffa_id == 2)
stopifnot(
  p2$projection == 12, p2$n_sources == 1L, p2$coverage_class == "single",
  is.na(p2$source_sd), is.na(p2$source_mad), is.na(p2$source_range)
)

p3 <- con |> filter(ffa_id == 3)
stopifnot(p3$n_sources == 3L, p3$coverage_class == "sparse", !is.na(p3$source_sd))

stopifnot(
  is.integer(con$season), con$season[1] == 2025L,
  isTRUE(check_one_consensus_per_player(con))
)

# duplicate consensus row is rejected
derr <- tryCatch(check_one_consensus_per_player(bind_rows(con, p1)), error = conditionMessage)
stopifnot(grepl("duplicated", derr))

cat("PASS test_consensus.R\n")
