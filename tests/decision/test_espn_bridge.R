# tests/decision/test_espn_bridge.R - ESPN->FFA id bridge + starter forecast guard.

suppressMessages({library(tidyverse); library(dm)})
source("./R/decision/league_state.R")

# --- fixtures ---------------------------------------------------------------
analytical_db <- dm(player_ids = tibble(
  ffa_id  = c(1L, 2L),
  espn_id = c(100L, 101L),     # direct-match ids
  nfl_id  = NA_integer_, numfire_id = NA_character_
))

ffa_db <- dm(
  ffa_player_ids = tibble(
    id      = c("50", "51"),
    espn_id = c("60005", "60033")   # D/ST, 60000-offset scheme
  ),
  ffa_players = tibble(
    id         = c("7", "8", "9"),
    first_name = c("Chris", "Dup", "Dup"),
    last_name  = c("Test", "Name", "Name"),
    pos        = c("WR", "RB", "RB")   # id 8 & 9 collide on name+pos
  )
)

rosters <- tibble(
  player_id   = c(100L, -16005L, 200L,  300L,       400L,      500L),
  player_name = c("A A", "Browns D/ST", "Chris Test", "Nobody Here", "Over Ride", "Dup Name"),
  position    = c("RB",  "D/ST",        "WR",         "TE",          "QB",        "RB"),
  is_starter  = TRUE
)
overrides <- tibble(player_id = 400L, ffa_id = 99L)

b <- bridge_espn_to_ffa(rosters, analytical_db, ffa_db, overrides = overrides)

expect <- c(`100` = "espn_id", `-16005` = "dst_offset", `200` = "name_pos",
            `300` = NA, `400` = "override", `500` = NA)
got <- set_names(b$bridge_method, b$player_id)
stopifnot(identical(got[names(expect)], expect))
stopifnot(
  b$ffa_id[b$player_id == 100]    == 1L,
  b$ffa_id[b$player_id == -16005] == 50L,
  b$ffa_id[b$player_id == 200]    == 7L,
  is.na(b$ffa_id[b$player_id == 300]),
  b$ffa_id[b$player_id == 400]    == 99L,
  is.na(b$ffa_id[b$player_id == 500])   # ambiguous name -> unmapped
)

# --- check_starters_have_forecast -----------------------------------------
cp_ok <- tibble(is_starter = c(TRUE, TRUE, FALSE), ffa_id = c(1L, 2L, NA),
                sim_mean = c(10, 12, NA), player_name = c("x", "y", "z"),
                position = "RB", team_id = 1L)
w <- tryCatch(check_starters_have_forecast(cp_ok), warning = conditionMessage)
stopifnot(isTRUE(w) || grepl("non-starter", w))   # bench unmapped -> warning only

cp_bad <- tibble(is_starter = TRUE, ffa_id = c(1L, NA), sim_mean = c(10, NA),
                 player_name = c("Good Guy", "Lost Starter"), position = "WR", team_id = 3L)
e <- tryCatch(check_starters_have_forecast(cp_bad), error = conditionMessage)
stopifnot(grepl("Lost Starter", e), grepl("without a forecast", e))

cat("PASS test_espn_bridge.R\n")
