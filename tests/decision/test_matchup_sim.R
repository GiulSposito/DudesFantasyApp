# tests/decision/test_matchup_sim.R - simulate_matchup / simulate_matchups (spec 14-15).

suppressMessages({library(tidyverse)})
source("./R/decision/matchup_simulation.R")

d <- list("1" = c(10, 10, 10, 10), "2" = c(5, 20, 5, 20),
          "3" = c(1, 1, 1, 1),     "4" = c(9, 9, 9, 9))
# home totals c(15,30,15,30); away totals c(10,10,10,10)
r <- simulate_matchup(c(1, 2), c(3, 4), d)
stopifnot(
  r$home_win_probability == 1, r$away_win_probability == 0, r$tie_probability == 0,
  r$home_expected == 22.5, r$away_expected == 10, r$home_p50 == 22.5, r$n_sim == 4
)

# perfect tie
rt <- simulate_matchup(1, 1, d)
stopifnot(rt$tie_probability == 1, rt$home_win_probability == 0)

# probabilities partition on a random fixture
set.seed(1)
dr <- set_names(map(1:6, ~ rnorm(500, 10, 4)), as.character(1:6))
rp <- simulate_matchup(c(1, 2, 3), c(4, 5, 6), dr)
stopifnot(abs(rp$home_win_probability + rp$away_win_probability + rp$tie_probability - 1) < 1e-9)

# deterministic - no RNG inside
stopifnot(identical(simulate_matchup(c(1, 2, 3), c(4, 5, 6), dr), rp))

# missing draw vector -> stop
e <- tryCatch(simulate_matchup(c(1, 99), 2, d), error = conditionMessage)
stopifnot(grepl("no draw vector", e))

# simulate_matchups over a 2-matchup fixture
cp <- tibble(
  team_id  = c(10, 10, 20, 20, 30, 30, 40, 40),
  ffa_id   = 1:8L,
  is_starter = TRUE
)
draws <- set_names(map(1:8, ~ rep(.x, 100)), as.character(1:8))
mu <- tibble(matchup_id = c(1L, 2L), home_team_id = c(10L, 30L), away_team_id = c(20L, 40L))
ms <- simulate_matchups(cp, mu, draws, "RUN1", 2026, 1, "preview")
stopifnot(
  nrow(ms) == 2,
  ms$run_id[1] == "RUN1",
  ms$home_expected[1] == 3,   # ffa 1 + 2
  ms$away_expected[1] == 7,   # ffa 3 + 4
  names(ms)[1:7] == c("run_id", "season", "week", "tag", "matchup_id",
                      "home_team_id", "away_team_id")
)

cat("PASS test_matchup_sim.R\n")
