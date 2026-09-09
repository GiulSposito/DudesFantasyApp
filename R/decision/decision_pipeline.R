# Decision engine - orchestrator (Milestones 1-3).
#
#   snapshot -> current consensus -> player Monte Carlo -> player_forecasts
#                                                       -> league state -> matchup_simulations
#                                                                       -> lineup_evaluations
#                                                                       -> lineup_recommendations
#
# Run from the project root:
#   source("R/decision/decision_pipeline.R")
#   res <- run_decision_pipeline(2026, 1, "preview")
#
# Assumes ffa_db / espn_db / analytical_db are already up to date - this pipeline
# does NO scraping or importing (spec 1). Milestones 4 (free agents) and 5 (1x1
# trades) are wired in.

library(tidyverse)
library(dm)
library(lubridate)

source("./R/decision/snapshot.R")
source("./R/decision/current_consensus.R")
source("./R/decision/player_simulation.R")
source("./R/decision/league_state.R")
source("./R/decision/matchup_simulation.R")
source("./R/decision/lineup_optimizer.R")
source("./R/decision/roster_evaluator.R")
source("./R/decision/free_agents.R")
source("./R/decision/trades.R")
source("./R/decision/decision_db.R")
# validate_model.R is a manual gate, not part of the pipeline - source it yourself.

run_decision_pipeline <- function(season, week, tag,
                                  n_sim = 10000, seed = 1234,
                                  matchups = TRUE, lineups = TRUE,
                                  free_agents = TRUE, fa_team_id = NULL,
                                  fa_max_adds_per_pos = 5L, fa_max_drops = 10L,
                                  fa_top_n = 25L,
                                  trades = TRUE, trade_team_id = NULL,  # NULL = all teams
                                  trade_max_give = 5L, trade_max_receive_per_pos = 5L,
                                  trade_top_n = 25L,
                                  persist_draws = FALSE, persist = TRUE) {

  ffa_db        <- readRDS("./data/ffa_db.rds")
  espn_db       <- readRDS("./data/espn_db.rds")
  analytical_db <- readRDS("./data/analytical_db.rds")
  history       <- analytical_db$consensus_error_history

  # --- Phase 1: snapshots + guards -------------------------------------------
  ffa_snap  <- select_ffa_snapshot(ffa_db, season, week, tag)
  espn_snap <- select_espn_snapshot(espn_db, season, week, tag)
  check_ffa_snapshot_quality(ffa_snap$proj_source)

  # --- Phase 2: current consensus ------------------------------------------
  consensus <- build_current_consensus(ffa_snap)
  check_one_consensus_per_player(consensus)

  xref <- build_current_player_xref(analytical_db)
  report_id_mapping(consensus, xref)
  consensus <- consensus |>
    left_join(distinct(xref, ffa_id, espn_id), by = "ffa_id")

  # --- Phase 3: player Monte Carlo ---------------------------------------
  set.seed(seed)                     # the one and only seed call (spec 10)
  sims <- simulate_players(consensus, history, n_sim = n_sim)
  # ffa_id assumed unique across pos in the FFA snapshot (verified);
  # ponytail: revisit if this ever fires
  stopifnot(!anyDuplicated(sims$ffa_id))
  draws_by_ffa <- set_names(sims$draws, as.character(sims$ffa_id))

  run_id    <- new_run_id(season, week, tag)
  forecasts <- summarise_forecasts(sims, run_id)

  # --- Phase 4: current league state ------------------------------------
  current_players <- build_current_league_state(espn_snap, forecasts,
                                                analytical_db, ffa_db)
  check_starters_have_forecast(current_players)

  # --- Phase 5: matchup simulation -------------------------------------
  matchup_sims <- if (matchups) {
    simulate_matchups(current_players, espn_snap$matchups,
                      draws_by_ffa, run_id, season, week, tag)
  } else NULL

  # --- Phase 6-7: lineup optimizer + roster evaluator ------------------
  lineup_evals <- NULL
  lineup_recs  <- NULL
  if (lineups) {
    le <- recommend_lineups(current_players, espn_snap, draws_by_ffa,
                            run_id, season, week, tag)
    lineup_evals <- le$evaluations
    lineup_recs  <- le$recommendations
  }

  # --- Phase 8: free agent recommendations (spec 19-22) --------------------
  fa_recs         <- NULL
  free_agents_tbl <- NULL
  if (free_agents) {
    if (is.null(fa_team_id)) {
      fa_team_id <- as.integer(yaml::read_yaml("./config/config.yml")$myTeamEspnId)
    }
    free_agents_tbl <- get_free_agents(espn_snap, forecasts, analytical_db, ffa_db)
    fa_recs <- recommend_free_agents(
      current_players, free_agents_tbl, espn_snap, draws_by_ffa,
      run_id, season, week, tag, team_id = fa_team_id,
      max_adds_per_pos = fa_max_adds_per_pos,
      max_drops        = fa_max_drops,
      top_n            = fa_top_n
    )
  }

  # --- Phase 9: trade recommendations (spec 24-28, 43) --------------------
  # trade_team_id = NULL advises every team in the league; pass an id (or vector)
  # to restrict.
  trade_recs <- NULL
  if (trades) {
    trade_recs <- recommend_trades(
      current_players, espn_snap, draws_by_ffa,
      run_id, season, week, tag, team_id = trade_team_id,
      max_give            = trade_max_give,
      max_receive_per_pos = trade_max_receive_per_pos,
      top_n               = trade_top_n
    )
  }

  # --- Phase 10 (partial): persist -------------------------------------------
  sim_run <- build_simulation_run(
    run_id, season, week, tag,
    ffa_timestamp  = ffa_snap$timestamp,
    espn_timestamp = espn_snap$timestamp,
    n_sim = n_sim, seed = seed
  )

  # M0.5: persist the web-bundle inputs so the bundle layer reads one run_id.
  current_players <- current_players |> mutate(run_id = run_id, .before = 1)
  free_agents_tbl <- if (!is.null(free_agents_tbl)) mutate(free_agents_tbl, run_id = run_id, .before = 1) else NULL

  db <- build_decision_db(sim_run, forecasts, matchup_sims,
                          lineup_recommendations     = lineup_recs,
                          lineup_evaluations         = lineup_evals,
                          free_agent_recommendations = fa_recs,
                          trade_recommendations      = trade_recs,
                          current_players            = current_players,
                          free_agents                = free_agents_tbl)
  if (persist) db <- persist_decision_db(db)

  invisible(list(
    run_id                     = run_id,
    consensus                  = consensus,
    player_forecasts           = forecasts,
    current_players            = current_players,
    matchup_simulations        = matchup_sims,
    lineup_evaluations         = lineup_evals,
    lineup_recommendations     = lineup_recs,
    free_agents                = free_agents_tbl,
    free_agent_recommendations = fa_recs,
    trade_recommendations      = trade_recs,
    simulation_runs            = sim_run,
    draws                  = if (persist_draws) select(sims, ffa_id, any_of("espn_id"), pos, draws) else NULL,
    decision_db            = db
  ))
}
