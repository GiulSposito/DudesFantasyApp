# tests/decision/test_pipeline_integration.R - end-to-end against the live .rds
# files. Skips (does not fail) when the databases are absent.

suppressMessages({library(tidyverse); library(dm)})

need <- c("./data/ffa_db.rds", "./data/espn_db.rds", "./data/analytical_db.rds")
if (!all(file.exists(need))) {
  cat("SKIP test_pipeline_integration.R (missing data/*.rds)\n")
} else {
  source("./R/decision/decision_pipeline.R")

  res <- suppressWarnings(
    run_decision_pipeline(2026, 1, "preview", n_sim = 2000, persist = FALSE)
  )
  fc <- res$player_forecasts

  stopifnot(
    nrow(fc) == 561,
    identical(sort(as.integer(table(fc$coverage_class))), c(99L, 149L, 313L)),
    all(with(fc, p05 <= p10 & p10 <= p25 & p25 <= p50 &
                 p50 <= p75 & p75 <= p90 & p90 <= p95)),
    all(fc$residual_pool_n >= 100),
    grepl("^\\d{4}-W\\d{2}-preview-\\d{8}T\\d{6}$", res$run_id),
    nrow(res$simulation_runs) == 1,
    # keys hold
    inherits(res$decision_db, "dm")
  )

  # --- Milestone 2: league state + matchups --------------------------------
  cp <- res$current_players
  ms <- res$matchup_simulations
  stopifnot(
    nrow(cp) == 210,
    sum(cp$is_starter) == 126,
    all(!is.na(cp$ffa_id[cp$is_starter])),
    all(!is.na(cp$sim_mean[cp$is_starter])),
    nrow(ms) == 7,
    all(ms$home_win_probability >= 0 & ms$home_win_probability <= 1),
    all(abs(ms$home_win_probability + ms$away_win_probability +
            ms$tie_probability - 1) < 1e-9),
    all(ms$home_p10 <= ms$home_p50 & ms$home_p50 <= ms$home_p90),
    all(ms$home_expected > 70 & ms$home_expected < 160),
    all(ms$away_expected > 70 & ms$away_expected < 160),
    length(res$decision_db) == 9
  )

  # --- Milestone 3: lineup optimizer + roster evaluator -------------------
  le <- res$lineup_evaluations
  lr <- res$lineup_recommendations
  stopifnot(
    nrow(le) == 14,                                   # 1 row per team
    all(le$optimal_expected >= le$current_expected - 1e-9),
    all(le$current_win_probability >= 0 & le$current_win_probability <= 1),
    all(le$optimal_win_probability >= 0 & le$optimal_win_probability <= 1),
    all(le$n_substitutions >= 0),
    # a team with no substitution has optimal == current
    all(with(le[le$n_substitutions == 0, ],
             abs(optimal_expected - current_expected) < 1e-9)),
    all(lr$delta_expected >= -1e-9),
    nrow(lr) == 0 || all(lr$player_out %in% cp$espn_id[cp$is_starter]),
    nrow(lr) == 0 || all(!lr$player_in %in% cp$espn_id[cp$is_starter]),
    inherits(res$decision_db$lineup_evaluations, "data.frame"),
    inherits(res$decision_db$lineup_recommendations, "data.frame")
  )
  # NOTE: do NOT assert optimal_win_probability >= current_win_probability -
  # the max-EV lineup can match up worse against a specific opponent.

  # --- Milestone 4: free agent add/drop (spec 22, 42) -------------------
  fa     <- res$free_agents
  far    <- res$free_agent_recommendations
  my_tid <- as.integer(yaml::read_yaml("./config/config.yml")$myTeamEspnId)
  stopifnot(
    nrow(fa) > 100, nrow(fa) < nrow(fc),
    all(!is.na(fa$ffa_id)), all(!is.na(fa$sim_mean)),
    all(nzchar(fa$eligible_slot_ids) & !is.na(fa$eligible_slot_ids)),
    !any(fa$ffa_id %in% cp$ffa_id[cp$team_id == my_tid]),   # FA pool is off-roster
    identical(names(far), names(.empty_fa_recs())),
    is.data.frame(far),
    nrow(far) <= 25,
    nrow(far) == 0 || all(far$team_id == my_tid),
    all(far$delta_expected > 0),
    all(abs(far$delta_expected - (far$after_expected - far$before_expected)) < 1e-9),
    nrow(far) == 0 || identical(far$recommendation_rank, seq_len(nrow(far))),
    nrow(far) <= 1 || all(diff(far$delta_expected) <= 1e-9),   # ranked desc
    nrow(far) == 0 || all(far$drop_player_id %in% cp$espn_id[cp$team_id == my_tid]),
    !any(far$add_player_id %in% cp$espn_id),                   # adds are off-roster
    inherits(res$decision_db$free_agent_recommendations, "data.frame"),
    length(res$decision_db) == 9
  )

  # --- Milestone 5: 1x1 trade recommender, every team (spec 24-28, 43) -------
  tr <- res$trade_recommendations
  on_roster <- function(pid, t) as.logical(mapply(
    function(p, tt) p %in% cp$espn_id[cp$team_id == tt], pid, t, SIMPLIFY = TRUE))
  give_ok  <- nrow(tr) == 0 || all(on_roster(tr$give_player_id, tr$my_team_id))
  recv_off <- nrow(tr) == 0 || !any(on_roster(tr$receive_player_id, tr$my_team_id))
  stopifnot(
    identical(names(tr), names(.empty_trade_recs())),
    is.data.frame(tr),
    nrow(tr) == 0 || all(table(tr$my_team_id) <= 25),         # <= top_n per team
    nrow(tr) == 0 || all(tr$my_team_id %in% cp$team_id),
    nrow(tr) == 0 || my_tid %in% tr$my_team_id,               # my team still advised
    nrow(tr) == 0 || length(unique(tr$my_team_id)) >= 2,      # and so are others
    all(tr$my_team_id != tr$other_team_id),
    all(tr$my_delta_expected > 0),
    nrow(tr) == 0 || all(tr$their_delta_expected >= 0),
    all(abs(tr$my_delta_expected - (tr$my_after_expected - tr$my_before_expected)) < 1e-9),
    all(abs(tr$their_delta_expected - (tr$their_after_expected - tr$their_before_expected)) < 1e-9),
    all(abs(tr$trade_score -
            (tr$my_delta_expected + pmin(tr$my_delta_expected, tr$their_delta_expected))) < 1e-9),
    all(abs(tr$fairness + abs(tr$my_delta_expected - tr$their_delta_expected)) < 1e-9),
    # recommendation_rank restarts at 1 per my_team_id, trade_score desc within team
    nrow(tr) == 0 || all(tapply(tr$recommendation_rank, tr$my_team_id,
                                function(r) identical(r, seq_along(r)))),
    nrow(tr) == 0 || all(tapply(tr$trade_score, tr$my_team_id,
                                function(s) all(diff(s) <= 1e-9))),
    give_ok,                                                  # give is on the advised roster
    recv_off,                                                 # receive is not
    inherits(res$decision_db$trade_recommendations, "data.frame")
  )

  cat("PASS test_pipeline_integration.R\n")
}
