# Decision engine - persistence (spec 30-32).
#
# decision_db.rds is a {dm} that ACCUMULATES runs. Every run gets a unique run_id
# (spec 31), so rows never collide across runs; re-running an identical run_id
# (same second) overwrites only its own rows via dm_rows_upsert.
#
# M1 tables: simulation_runs, player_forecasts. M2 adds matchup_simulations. M3
# adds lineup_evaluations (1 row/team) + lineup_recommendations (0+ rows/team).
# M4 adds free_agent_recommendations (0+ rows, one team). M5 adds
# trade_recommendations (0+ rows/team, ranked per my_team_id). M0.5 adds current_players (the
# rostered player pool, 1 row/team/player) + free_agents (the off-roster pool, 1
# row/player) so the web bundle layer reads one run without re-simulating.
# Draws are never persisted (spec 32).

library(tidyverse)
library(dm)
library(lubridate)

# run_id, e.g. "2026-W01-preview-20260908T153000" (spec 31)
new_run_id <- function(season, week, tag, timestamp = now()) {
  sprintf("%04d-W%02d-%s-%s",
          as.integer(season), as.integer(week), tag,
          format(timestamp, "%Y%m%dT%H%M%S"))
}

# One-row simulation_runs tibble (spec 31).
build_simulation_run <- function(run_id, season, week, tag,
                                 ffa_timestamp, espn_timestamp,
                                 n_sim, seed,
                                 model_version = "player-mc-v2") {
  tibble(
    run_id         = run_id,
    created_at     = now(),
    season         = as.integer(season),
    week           = as.integer(week),
    tag            = tag,
    ffa_timestamp  = as_datetime(ffa_timestamp),
    espn_timestamp = as_datetime(espn_timestamp),
    model_version  = model_version,
    n_sim          = as.integer(n_sim),
    seed           = as.integer(seed)
  )
}

# Assemble the decision dm with keys.
build_decision_db <- function(simulation_run, player_forecasts,
                              matchup_simulations = NULL,
                              lineup_recommendations = NULL,
                              lineup_evaluations = NULL,
                              free_agent_recommendations = NULL,
                              trade_recommendations = NULL,
                              current_players = NULL,
                              free_agents = NULL) {
  db <- dm(
    simulation_runs  = simulation_run,
    player_forecasts = player_forecasts
  ) |>
    dm_add_pk(simulation_runs, run_id, check = TRUE) |>
    dm_add_pk(player_forecasts, c(run_id, ffa_id, pos), check = TRUE) |>
    dm_add_fk(player_forecasts, run_id, simulation_runs, check = TRUE)

  if (!is.null(matchup_simulations)) {
    db <- dm(db, matchup_simulations = matchup_simulations) |>
      dm_add_pk(matchup_simulations, c(run_id, matchup_id), check = TRUE) |>
      dm_add_fk(matchup_simulations, run_id, simulation_runs, check = TRUE)
  }

  if (!is.null(lineup_evaluations)) {
    db <- dm(db, lineup_evaluations = lineup_evaluations) |>
      dm_add_pk(lineup_evaluations, c(run_id, team_id), check = TRUE) |>
      dm_add_fk(lineup_evaluations, run_id, simulation_runs, check = TRUE)
  }

  # PK holds on 0 rows too (a run where every team is already optimal)
  if (!is.null(lineup_recommendations)) {
    db <- dm(db, lineup_recommendations = lineup_recommendations) |>
      dm_add_pk(lineup_recommendations, c(run_id, team_id, player_out), check = TRUE) |>
      dm_add_fk(lineup_recommendations, run_id, simulation_runs, check = TRUE)
  }

  # PK holds on 0 rows too (a week with no beneficial add/drop). drop_player_id is
  # always a concrete espn_id, so the key is valid even when drop_ffa_id is NA.
  if (!is.null(free_agent_recommendations)) {
    db <- dm(db, free_agent_recommendations = free_agent_recommendations) |>
      dm_add_pk(free_agent_recommendations,
                c(run_id, team_id, drop_player_id, add_player_id), check = TRUE) |>
      dm_add_fk(free_agent_recommendations, run_id, simulation_runs, check = TRUE)
  }

  # PK holds on 0 rows too (a week with no beneficial trade). give/receive player
  # ids are always concrete espn_ids, so the key is valid even if a *_ffa_id is NA
  # (they never are for trades - each side must carry a draw vector).
  if (!is.null(trade_recommendations)) {
    db <- dm(db, trade_recommendations = trade_recommendations) |>
      dm_add_pk(trade_recommendations,
                c(run_id, my_team_id, other_team_id, give_player_id, receive_player_id), check = TRUE) |>
      dm_add_fk(trade_recommendations, run_id, simulation_runs, check = TRUE)
  }

  # M0.5: web-bundle inputs. Both always have rows in practice; PK holds on 0 too.
  if (!is.null(current_players)) {
    db <- dm(db, current_players = current_players) |>
      dm_add_pk(current_players, c(run_id, team_id, espn_id), check = TRUE) |>
      dm_add_fk(current_players, run_id, simulation_runs, check = TRUE)
  }

  if (!is.null(free_agents)) {
    db <- dm(db, free_agents = free_agents) |>
      dm_add_pk(free_agents, c(run_id, player_id), check = TRUE) |>
      dm_add_fk(free_agents, run_id, simulation_runs, check = TRUE)
  }
  db
}

# upsert a dm into an on-disk .rds (mirrors R/pipeline/data_pipeline_espn.R:23).
# If the on-disk dm has a different set of tables (schema evolved across
# milestones), overwrite instead of upsert - the older runs carried fewer tables
# and regenerate in seconds.
updateDB <- function(db, db_file) {
  if (file.exists(db_file)) {
    old <- readRDS(db_file)
    if (setequal(names(old), names(db))) {
      db <- old |> dm_rows_upsert(db, in_place = FALSE)
    } else {
      message(glue::glue(
        "decision_db schema changed (now: {paste(names(db), collapse = ', ')}); ",
        "starting fresh run history"
      ))
    }
  }
  saveRDS(db, db_file)
  db
}

# ponytail: unbounded run history, add keep_last_n_runs prune if the rds grows.
persist_decision_db <- function(db, file = "./data/decision_db.rds") {
  updateDB(db, file)
}
