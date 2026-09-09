# tests/decision/test_free_agents.R - get_free_agents / recommend_free_agents
# (spec 13, 19-22, 42).

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/lineup_optimizer.R")
source("./R/decision/roster_evaluator.R")
source("./R/decision/free_agents.R")
source("./R/decision/decision_db.R")

# ===========================================================================
# Fixture A - get_free_agents()
# ===========================================================================

# unrostered ESPN players: a WR with a forecast, an RB with no forecast, a D/ST
# with a forecast, a WR flagged OUT, an RB flagged inactive.
players <- tribble(
  ~player_id, ~position, ~player_name,      ~first_name, ~last_name,
  601L,       "WR",      "Wide Open",       "Wide",      "Open",
  602L,       "RB",      "No Forecast",     "No",        "Forecast",
  -16050L,    "D/ST",    "Bears D/ST",      "Bears",     "D/ST",
  603L,       "WR",      "Hurt Guy",        "Hurt",      "Guy",
  604L,       "RB",      "Benched Bye",     "Benched",   "Bye"
) |> mutate(season = 2026L)

rosters <- tribble(
  ~player_id, ~position, ~eligible_slot_ids,
  501L,       "WR",      "3,4,5,23,7,20,21",
  502L,       "RB",      "2,3,23,7,20,21",
  500L,       "D/ST",    "16,20,21"
)

injury <- tribble(
  ~player_id, ~injury_status, ~injured, ~active,
  603L,       "OUT",          TRUE,     TRUE,
  604L,       "ACTIVE",       FALSE,    FALSE
)

forecasts <- tribble(
  ~ffa_id, ~pos,  ~projection, ~sim_mean, ~p10, ~p50, ~p90, ~coverage_class,
  6001L,   "WR",  12,          12.3,      4,    12,   22,   "ensemble",
  6003L,   "DST", 7,           6.8,       2,    7,    12,   "sparse",
  6004L,   "WR",  9,           9.1,       3,    9,    16,   "ensemble",
  6005L,   "RB",  8,           7.7,       2,    7,    15,   "sparse"
)

an_stub <- list(player_ids = tribble(
  ~ffa_id, ~espn_id, ~nfl_id, ~numfire_id,
  6001L,   601L,     NA_integer_, NA_integer_,
  6002L,   602L,     NA_integer_, NA_integer_,
  6004L,   603L,     NA_integer_, NA_integer_,
  6005L,   604L,     NA_integer_, NA_integer_
))
ffa_stub <- list(
  ffa_player_ids = tibble(id = "6003", espn_id = "60050"),   # 44000 - (-16050)
  ffa_players    = tibble(id = "9999", first_name = "x", last_name = "y", pos = "WR")
)

espn_snap_a <- list(players = players, rosters = rosters, injury = injury,
                    season = 2026, week = 1, tag = "preview")

fa <- suppressWarnings(get_free_agents(espn_snap_a, forecasts, an_stub, ffa_stub))

stopifnot(
  setequal(fa$player_id, c(601L, -16050L)),           # no-forecast / OUT / inactive dropped
  all(!is.na(fa$ffa_id)), all(!is.na(fa$sim_mean)),
  fa$eligible_slot_ids[fa$position == "WR"]   == "3,4,5,23,7,20,21",
  fa$eligible_slot_ids[fa$position == "D/ST"] == "16,20,21",
  fa$pos[fa$position == "D/ST"] == "DST",
  fa$ffa_id[fa$position == "D/ST"] == 6003L,          # dst_offset bridge
  identical(fa, suppressWarnings(get_free_agents(espn_snap_a, forecasts, an_stub, ffa_stub))),
  nrow(suppressWarnings(get_free_agents(espn_snap_a, forecasts, an_stub, ffa_stub,
                                        min_sim_mean = 1e6))) == 0
)

# ===========================================================================
# Fixture B - recommend_free_agents()  (self-contained, mini league)
# ===========================================================================

# slots: QB1, RB2, WR1, BE2
slots <- tibble(
  season = 2026L,
  lineup_slot_id = c(0L, 2L, 4L, 20L),
  lineup_slot    = c("QB", "RB", "WR", "BE"),
  count          = c(1L, 2L, 1L, 2L)
)
E <- c(QB = "0,20", RB = "2,3,20", WR = "3,4,20")

pl <- function(team, id, pos, sm, starter, ffa = id) tibble(
  season = 2026L, week = 1L, tag = "preview",
  team_id = as.integer(team), espn_id = as.integer(id * 10),
  ffa_id = if (is.na(ffa)) NA_integer_ else as.integer(ffa),
  player_name = paste0(pos, id), position = pos, pos = pos,
  eligible_slot_ids = E[[pos]],
  lineup_slot = if (starter) pos else "BE", lineup_slot_id = if (starter) 1L else 20L,
  is_starter = starter, is_bench = !starter, is_ir = FALSE,
  injury_status = "ACTIVE", sim_mean = sm
)

# team 10 (mine): 4 starters + one dead-weight bench row (unmapped, no forecast)
# team 20 (opp): 4 starters, total 51
cp <- bind_rows(
  pl(10, 1, "QB", 10, TRUE),  pl(10, 2, "RB", 15, TRUE),
  pl(10, 3, "RB", 8,  TRUE),  pl(10, 4, "WR", 12, TRUE),
  pl(10, 8, "RB", NA, FALSE, ffa = NA),
  pl(20, 11, "QB", 10, TRUE), pl(20, 12, "RB", 15, TRUE),
  pl(20, 13, "RB", 14, TRUE), pl(20, 14, "WR", 12, TRUE)
)

fa_pool <- tribble(
  ~ffa_id, ~pos,  ~position, ~sim_mean, ~eligible_slot_ids, ~player_name, ~player_id,
  100L,    "RB",  "RB",      25,        E[["RB"]],          "RB100",      1000L,
  101L,    "WR",  "WR",      4,         E[["WR"]],          "WR101",      1010L,
  102L,    "QB",  "QB",      5,         E[["QB"]],          "QB102",      1020L
)

# fixed draws: mean(draws) == sim_mean for every player, so expected-point deltas
# are exact.
sm_lookup <- c(
  set_names(cp$sim_mean[!is.na(cp$ffa_id)], cp$ffa_id[!is.na(cp$ffa_id)]),
  set_names(fa_pool$sim_mean, fa_pool$ffa_id)
)
draws <- map(sm_lookup, ~ rep(.x, 200))

espn_snap_b <- list(roster_slots = slots,
                    matchups = tibble(home_team_id = 10L, away_team_id = 20L))

out <- recommend_free_agents(cp, fa_pool, espn_snap_b, draws, "TESTRUN",
                             2026, 1, "preview", team_id = 10L,
                             max_adds_per_pos = 5L, max_drops = 5L, top_n = 10L)

stopifnot(
  identical(names(out), names(.empty_fa_recs())),        # exact spec-22 schema
  nrow(out) >= 1,
  out$drop_ffa_id[1] == 3L, out$add_ffa_id[1] == 100L,   # drop weakest RB, add best RB
  out$drop_position[1] == "RB", out$add_position[1] == "RB",
  out$drop_player_id[1] == 30L, out$add_player_id[1] == 1000L,
  abs(out$delta_expected[1] - 17) < 1e-9,                # 25 - 8 in the RB2 slot
  length(unique(out$before_expected)) == 1L,             # before constant across rows
  abs(unique(out$before_expected) - 45) < 1e-9,
  all(abs((out$after_expected - out$before_expected) - out$delta_expected) < 1e-9),
  !(101L %in% out$add_ffa_id),                           # worse WR never recommended
  !(102L %in% out$add_ffa_id),                           # worse QB never recommended
  all(out$delta_expected > 0),
  identical(out$recommendation_rank, seq_len(nrow(out))),
  identical(out, recommend_free_agents(cp, fa_pool, espn_snap_b, draws, "TESTRUN",
                                       2026, 1, "preview", team_id = 10L,
                                       max_adds_per_pos = 5L, max_drops = 5L, top_n = 10L))
)

# no unique opponent -> empty, no error
snap_bad <- modifyList(espn_snap_b,
  list(matchups = tibble(home_team_id = 99L, away_team_id = 98L)))
stopifnot(nrow(suppressWarnings(
  recommend_free_agents(cp, fa_pool, snap_bad, draws, "R", 2026, 1, "preview",
                        team_id = 10L))) == 0)

# nothing beneficial -> 0 rows (every FA is worse than what it would replace)
fa_weak    <- fa_pool |> mutate(sim_mean = 1)
draws_weak <- modifyList(draws, list("100" = rep(1, 200), "101" = rep(1, 200),
                                     "102" = rep(1, 200)))
stopifnot(nrow(recommend_free_agents(cp, fa_weak, espn_snap_b, draws_weak, "R",
                                     2026, 1, "preview", team_id = 10L)) == 0)

# ===========================================================================
# DB key check - PK holds on the 0-row template
# ===========================================================================

sr <- build_simulation_run("R", 2026, 1, "preview", Sys.time(), Sys.time(), 10L, 1L)
tiny_fc <- tibble(run_id = "R", season = 2026L, week = 1L, tag = "preview",
                  ffa_id = 1L, pos = "QB")
db <- build_decision_db(sr, tiny_fc, free_agent_recommendations = .empty_fa_recs())
stopifnot("free_agent_recommendations" %in% names(db), inherits(db, "dm"))

cat("PASS test_free_agents.R\n")
