# tests/decision/test_lineup_optimizer.R - optimize_lineup (spec 16, 16.1).

suppressMessages({library(tidyverse)})
source("./R/decision/lineup_optimizer.R")

# mini league: QB1, RB2, WR2, RB/WR flex1, TE1, K1, D/ST1, BE3  -> 9 starters
slots <- tibble(
  season = 2026L,
  lineup_slot_id = c(0L, 2L, 4L, 3L, 6L, 17L, 16L, 20L, 21L),
  lineup_slot    = c("QB","RB","WR","RB/WR","TE","K","D/ST","BE","IR"),
  count          = c(1L, 2L, 2L, 1L, 1L, 1L, 1L, 3L, 0L)
)

E <- c(QB = "0,7,20", RB = "2,3,23,7,20", WR = "3,4,5,23,7,20",
       TE = "5,6,23,7,20", K = "17,20", DST = "16,20")
mk <- function(id, pos, sm) tibble(
  ffa_id = as.integer(id), pos = pos, sim_mean = sm,
  eligible_slot_ids = E[[pos]], player_name = paste0(pos, id), espn_id = as.integer(id * 10)
)

base <- bind_rows(
  mk(1, "QB", 18), mk(2, "QB", 12),
  mk(10, "TE", 9), mk(11, "TE", 6),
  mk(20, "K", 8),  mk(21, "K", 5),
  mk(30, "DST", 7), mk(31, "DST", 4)
)

# --- 1: slot counts come from the fixture, not hard-coded -----------------
cand1 <- bind_rows(base,
  mk(40,"RB",12), mk(41,"RB",10), mk(42,"RB",8),
  mk(50,"WR",9),  mk(51,"WR",7),  mk(52,"WR",6))
o1 <- optimize_lineup(cand1, slots)
stopifnot(nrow(o1) == 9)                                   # 1+2+2+1+1+1+1

slots_1wr <- slots |> mutate(count = if_else(lineup_slot == "WR", 1L, count))
stopifnot(nrow(optimize_lineup(cand1, slots_1wr)) == 8)

# --- 2: FLEX picks the higher-value eligible player ----------------------
flex_row <- function(o) o[o$lineup_slot == "RB/WR", ]
# RB depth 12/10/8, WR depth 9/7/6 -> RB slots 12,10; WR slots 9,7; flex = RB 8
stopifnot(flex_row(o1)$pos == "RB", flex_row(o1)$sim_mean == 8)

cand2 <- bind_rows(base,
  mk(40,"RB",12), mk(41,"RB",10), mk(42,"RB",6),
  mk(50,"WR",9),  mk(51,"WR",7),  mk(52,"WR",8))
o2 <- optimize_lineup(cand2, slots)
# RB slots 12,10; WR slots 9,8; flex = best of {RB 6, WR 7} = WR 7
stopifnot(flex_row(o2)$pos == "WR", flex_row(o2)$sim_mean == 7)

# matches the greedy single-flex oracle
stopifnot(setequal(o1$ffa_id, .optimize_lineup_greedy(cand1, slots)$ffa_id),
          setequal(o2$ffa_id, .optimize_lineup_greedy(cand2, slots)$ffa_id))

# --- 3: a TE is never placed in the RB/WR flex --------------------------
cand3 <- bind_rows(
  mk(1,"QB",18), mk(20,"K",8), mk(30,"DST",7),
  mk(10,"TE",20), mk(11,"TE",15),                      # TE2 = 15, very tempting
  mk(40,"RB",5), mk(41,"RB",4), mk(42,"RB",3),
  mk(50,"WR",5), mk(51,"WR",4))
o3 <- optimize_lineup(cand3, slots)
stopifnot(
  nrow(o3) == 9,
  !"TE" %in% o3$pos[o3$lineup_slot == "RB/WR"],         # flex takes RB 42, not TE2
  o3$sim_mean[o3$lineup_slot == "RB/WR"] == 3,
  !11L %in% o3$ffa_id,                                  # TE2 stays on the bench
  o3$ffa_id[o3$lineup_slot == "TE"] == 10L
)

# --- 4: deterministic regardless of input row order -------------------
stopifnot(identical(optimize_lineup(cand1, slots),
                    optimize_lineup(cand1[sample(nrow(cand1)), ], slots)))

# --- 5: unfillable slot -> warning + partial lineup, never stop --------
cand5 <- cand1 |> filter(pos != "K")                    # no kicker
w5 <- tryCatch(optimize_lineup(cand5, slots), warning = conditionMessage)
stopifnot(grepl("partial lineup", w5))
o5 <- suppressWarnings(optimize_lineup(cand5, slots))
stopifnot(nrow(o5) == 8, !"K" %in% o5$lineup_slot)

cat("PASS test_lineup_optimizer.R\n")
