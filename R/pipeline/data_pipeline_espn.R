# ESPN Fantasy data pipeline - function library
#
# Sourcing this file only DEFINES functions; it runs nothing. The orchestrator
# R/pipeline/data_pipeline.R sources it and calls importEspn() with the week's
# master parameters. Pulls one weekly snapshot of the league from the ESPN
# Fantasy API (via R/api/espn_fantasy_client.R) plus the player pool / stats, and
# upserts everything as a single `dm` (`espn_*` tables) into ./data/espn_db.rds.
#
# Leaves ffa_* / nfl_* pipelines and databases untouched.

library(tidyverse)
library(dm)
library(glue)
library(lubridate)

# NOTE: sourcing the client defines a global `%||%` (null-or-empty semantics).
# Harmless here - no pipeline code uses a bare `%||%`.
source("./R/api/espn_fantasy_client.R")

# ---- inline helpers (mirror data_pipeline.R conventions) ---------------------

# add any column present on one side but not the other (typed NA) so two dm
# snapshots taken under different code versions still upsert cleanly (schema
# drift is routine here - a new field lands every season or two).
.reconcile_dm_cols <- function(a, b) {
  fill <- function(dm_, tbl, col, proto) {
    na1 <- proto[NA_integer_]
    dm_ |> dm_zoom_to(!!tbl) |> mutate(!!col := na1) |> dm_update_zoomed()
  }
  for (t in intersect(names(a), names(b))) {
    ca <- colnames(a[[t]]); cb <- colnames(b[[t]])
    for (col in setdiff(cb, ca)) a <- fill(a, t, col, b[[t]][[col]])
    for (col in setdiff(ca, cb)) b <- fill(b, t, col, a[[t]][[col]])
  }
  list(a = a, b = b)
}

# upsert a dm into an on-disk .rds (update existing rows by PK, insert new ones)
updateDB <- function(db, db_file) {
  if (file.exists(db_file)) {
    rc <- .reconcile_dm_cols(readRDS(db_file), db)
    db <- dm_rows_upsert(rc$a, rc$b, in_place = FALSE)
  }
  saveRDS(db, db_file)
  return(db)
}

# cache a raw API payload so a run can be reprocessed without hitting the network
saveEspnTemp <- function(obj, name, season, week, tag = "NA", timestamp = now()) {
  tsf <- format(timestamp, "%Y%m%d%H%M%S")
  wf  <- formatC(week, width = 2, flag = "0")
  saveRDS(obj, glue::glue("./data/temp/{name}_s{season}w{wf}_{tag}_{tsf}.rds"))
}

# draw a dm ERD to a PNG file. Works around DiagrammeR >= 1.0.11, whose htmlwidget
# renderer fails in the RStudio Viewer with "Layout was not done"; export_svg()
# uses the DOT->SVG path instead. Needs DiagrammeRsvg + rsvg.
dm_draw_png <- function(dm, ..., file, width = 2400) {
  svg <- DiagrammeRsvg::export_svg(dm::dm_draw(dm, ...))
  rsvg::rsvg_png(charToRaw(svg), file, width = width)
  file
}

# fail fast when a client parser returns an empty tibble (e.g. run before the
# draft): an empty parse has no columns and would break dm_add_pk / dm_rows_upsert
.espn_require_rows <- function(df, nm) {
  if (nrow(df) == 0L) {
    stop(
      glue::glue("ESPN parse '{nm}' returned 0 rows - run after the draft / once the week has data."),
      call. = FALSE
    )
  }
  df
}

# ---- getters ---------------------------------------------------------------

# one combined league request (mSettings, mStatus, mTeam, mRoster, mStandings,
# mMatchupScore, mDraftDetail) parsed into league / members / teams /
# roster_slots / scoring_rules / rosters / matchups / draft + the raw JSON
getEspnSnapshot <- function(client, .season, .week, .tag, .timestamp) {
  snap <- espn_snapshot(
    client,
    week = .week,
    include_available = FALSE,
    include_transactions = FALSE
  )
  saveEspnTemp(snap, "espn_snapshot", .season, .week, .tag, .timestamp)
  return(snap)
}

# player master (kona_player_info, all statuses) + expanded per-record stats
# (one row per scoring period / stat_source_id / stat_split_type_id)
getEspnPlayerPool <- function(client, .season, .week, .tag, .timestamp) {
  pool <- list(
    players = espn_all_players(client, week = .week, limit = 5000L),
    stats   = espn_player_stats(client, week = .week, limit = 5000L)
  )
  saveEspnTemp(pool, "espn_player_pool", .season, .week, .tag, .timestamp)
  return(pool)
}

# ---- dm builder ----------------------------------------------------------

buildEspnDB <- function(snap, pool, .season, .week, .tag, .timestamp) {

  .season <- as.integer(.season)
  .week   <- as.integer(.week)

  # -- dimensions -----------------------------------------------------------

  espn_league <- snap$league |>
    mutate(season = as.integer(season), league_id = as.character(league_id)) |>
    select(
      league_id, season, league_name, size,
      current_scoring_period, current_matchup_period, final_scoring_period,
      draft_date, draft_type, draft_time_per_selection, draft_slot_count,
      roster_locktime, waiver_process_days, matchup_period_count
    )

  espn_members <- snap$members |>
    distinct(member_id, .keep_all = TRUE) |>
    select(member_id, display_name, first_name, last_name, is_league_manager)

  espn_teams <- snap$teams |>
    mutate(season = .season) |>
    distinct(season, team_id, .keep_all = TRUE) |>
    select(season, team_id, team_name, abbrev, division_id, owner_ids, owners)

  espn_roster_slots <- snap$roster_slots |>
    mutate(season = .season) |>
    distinct(season, lineup_slot_id, .keep_all = TRUE) |>
    select(season, lineup_slot_id, lineup_slot, count)

  espn_scoring_rules <- snap$scoring_rules |>
    select(-any_of("points_overrides")) |>
    mutate(season = .season) |>
    distinct(season, stat_id, .keep_all = TRUE) |>
    select(season, stat_id, points, is_reverse_item)

  # player master: UNION of every player id referenced anywhere, so downstream
  # FKs (rosters / injury / points / draft -> espn_players) always resolve.
  # bind_rows order = richest source first; distinct() keeps that row.
  espn_players <- bind_rows(
      pool$players |>
        select(player_id, player_name, first_name, last_name,
               pro_team_id, pro_team, default_position_id, position),
      snap$rosters |>
        select(any_of(c("player_id", "player_name", "first_name", "last_name",
                        "pro_team_id", "pro_team", "default_position_id", "position"))),
      pool$stats |>
        select(any_of(c("player_id", "player_name", "position", "pro_team"))),
      snap$draft |>
        select(any_of(c("player_id", "player_name", "position", "pro_team")))
    ) |>
    filter(!is.na(player_id)) |>
    mutate(season = .season) |>
    arrange(player_id) |>
    distinct(season, player_id, .keep_all = TRUE) |>
    select(season, player_id, player_name, first_name, last_name,
           pro_team_id, pro_team, default_position_id, position)

  # -- facts (timestamped snapshots) -------------------------------------

  espn_team_standings <- snap$teams |>
    mutate(season = .season, week = .week, tag = .tag, timestamp = .timestamp) |>
    distinct(season, week, tag, timestamp, team_id, .keep_all = TRUE) |>
    select(season, week, tag, timestamp, team_id,
           current_projected_rank, draft_day_projected_rank, waiver_rank,
           points, points_adjusted, wins, losses, ties, win_pct,
           points_for, points_against, streak_type, streak_length,
           acquisitions, drops, trades)

  espn_player_injury_status <- pool$players |>
    mutate(season = .season, week = .week, tag = .tag, timestamp = .timestamp) |>
    distinct(season, week, tag, timestamp, player_id, .keep_all = TRUE) |>
    select(season, week, tag, timestamp, player_id,
           injury_status, injured, active)

  # both projected (stat_source_id == 1) and actual (== 0) live here; `week` is
  # the per-record scoring period (varies), not the run week. season pinned to
  # the run; the record's own season kept as `stat_season`.
  # scrape-time roster-lock state (ESPN lineupLocked): TRUE once the player's NFL
  # game has kicked off. Sourced from the player pool, per-player. Used by the
  # decision engine to fold realized points in for players who have played.
  pool_locked <- pool$players |>
    select(player_id, any_of("lineup_locked")) |>
    distinct(player_id, .keep_all = TRUE)
  if (!"lineup_locked" %in% names(pool_locked)) pool_locked$lineup_locked <- NA

  espn_players_points <- pool$stats |>
    select(-any_of(c("stats", "applied_stats"))) |>
    mutate(
      season             = .season,
      stat_season        = as.integer(season_id),
      week               = coalesce(as.integer(scoring_period_id), -1L),
      tag                = .tag,
      timestamp          = .timestamp,
      stat_source_id     = coalesce(as.integer(stat_source_id), -1L),
      stat_split_type_id = coalesce(as.integer(stat_split_type_id), -1L)
    ) |>
    left_join(pool_locked, by = "player_id") |>
    distinct(season, week, tag, timestamp, player_id,
             stat_source_id, stat_split_type_id, .keep_all = TRUE) |>
    select(season, week, tag, timestamp, player_id,
           stat_source_id, stat_split_type_id,
           stat_season, pro_team_id, fantasy_points, lineup_locked,
           player_name, position, pro_team)

  espn_rosters <- .espn_require_rows(snap$rosters, "rosters") |>
    select(-any_of("stats_raw")) |>
    mutate(season = .season, week = .week, tag = .tag, timestamp = .timestamp) |>
    distinct(season, week, tag, timestamp, team_id, player_id, .keep_all = TRUE) |>
    select(season, week, tag, timestamp, team_id, team_name, player_id, player_name,
           position, pro_team, lineup_slot, lineup_slot_id,
           is_starter, is_bench, is_ir, any_of("lineup_locked"),
           acquisition_type, acquisition_date, percent_owned, percent_started,
           total_points, applied_stat_total, injury_status, eligible_slot_ids)

  espn_matchups <- .espn_require_rows(snap$matchups, "matchups") |>
    mutate(season = .season, week = .week, tag = .tag, timestamp = .timestamp) |>
    distinct(season, week, tag, timestamp, matchup_id, .keep_all = TRUE) |>
    select(season, week, tag, timestamp, matchup_id, matchup_period_id,
           home_team_id, home_team_name, home_points, home_projected_points,
           away_team_id, away_team_name, away_points, away_projected_points,
           winner, playoff_tier_type)

  espn_draft <- .espn_require_rows(snap$draft, "draft") |>
    mutate(season = .season) |>
    distinct(season, overall_pick, .keep_all = TRUE) |>
    select(season, overall_pick, pick_id, round, round_pick,
           team_id, team_name, player_id,
           bid_amount, auto_draft_type_id, keeper, trade_locked)

  # -- assemble ---------------------------------------------------------

  # ESPN -> ffanalytics id bridge (future, out of scope): join
  # espn_players$player_id to ffa_db$ffa_player_ids$espn_id (D/ST uses the
  # 60000-offset form; see R_old/import/espn_scraper.R for the offset math).
  #
  # per-stat box score (future): s$stats / s$appliedStats were dropped from
  # espn_players_points; add an `espn_player_stat_values` long table if needed.

  dm(
    espn_league, espn_members, espn_teams, espn_roster_slots, espn_scoring_rules,
    espn_players, espn_team_standings, espn_player_injury_status,
    espn_players_points, espn_rosters, espn_matchups, espn_draft
  ) |>
    dm_add_pk(espn_league,               c(league_id, season), check = TRUE) |>
    dm_add_pk(espn_members,              member_id, check = TRUE) |>
    dm_add_pk(espn_teams,                c(season, team_id), check = TRUE) |>
    dm_add_pk(espn_roster_slots,         c(season, lineup_slot_id), check = TRUE) |>
    dm_add_pk(espn_scoring_rules,        c(season, stat_id), check = TRUE) |>
    dm_add_pk(espn_players,              c(season, player_id), check = TRUE) |>
    dm_add_pk(espn_team_standings,       c(season, week, tag, timestamp, team_id), check = TRUE) |>
    dm_add_pk(espn_player_injury_status, c(season, week, tag, timestamp, player_id), check = TRUE) |>
    dm_add_pk(espn_players_points,       c(season, week, tag, timestamp, player_id,
                                          stat_source_id, stat_split_type_id), check = TRUE) |>
    dm_add_pk(espn_rosters,              c(season, week, tag, timestamp, team_id, player_id), check = TRUE) |>
    dm_add_pk(espn_matchups,             c(season, week, tag, timestamp, matchup_id), check = TRUE) |>
    dm_add_pk(espn_draft,                c(season, overall_pick), check = TRUE) |>
    dm_add_fk(espn_team_standings,       c(season, team_id),      espn_teams) |>
    dm_add_fk(espn_rosters,              c(season, team_id),      espn_teams) |>
    dm_add_fk(espn_rosters,              c(season, player_id),    espn_players) |>
    dm_add_fk(espn_player_injury_status, c(season, player_id),    espn_players) |>
    dm_add_fk(espn_players_points,       c(season, player_id),    espn_players) |>
    dm_add_fk(espn_matchups,             c(season, home_team_id), espn_teams) |>
    dm_add_fk(espn_matchups,             c(season, away_team_id), espn_teams) |>
    dm_add_fk(espn_draft,                c(season, team_id),      espn_teams) |>
    dm_add_fk(espn_draft,                c(season, player_id),    espn_players)
}

# ---- orchestrator ------------------------------------------------------

# run the full ESPN pipeline for one week: client -> snapshot + player pool ->
# build dm -> upsert. `config` = yaml::read_yaml("./config/config.yml").
importEspn <- function(config, .season, .week, .tag, .timestamp) {
  client <- espn_client(
    league_id = as.character(config$ESPN_LEAGUEID),
    season    = .season,
    espn_s2   = config$ESPN_S2,   # already URL-encoded in config.yml - pass verbatim
    swid      = config$ESPN_SWID,
    timeout   = 60
  )

  .conn <- espn_test_connection(client)
  if (!isTRUE(.conn$ok)) stop(.conn$error, call. = FALSE)
  
  cli::cli_alert_info(glue("Importing ESPN data s{.season}-w{.week}:{.tag}..."))
  snap    <- getEspnSnapshot(client, .season, .week, .tag, .timestamp)
  pool    <- getEspnPlayerPool(client, .season, .week, .tag, .timestamp)
  cli::cli_alert_success(glue("ESPN data Imported"))
  
  cli::cli_alert_info(glue("Updating ESPN database..."))
  espn_db <- buildEspnDB(snap, pool, .season, .week, .tag, .timestamp)
  espn_db <- updateDB(espn_db, "./data/espn_db.rds")
  print(dm_examine_constraints(espn_db))
  cli::cli_alert_success(glue("ESPN DB updated"))
  

  dm_draw_png(espn_db, view_type = "all", column_types = TRUE, rankdir = "RL",
              file = "./data/temp/espn_db.png")
  espn_db
}
