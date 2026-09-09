# Decision engine - Phase 1: snapshot selection + input guards.
#
# Sourcing this file only DEFINES functions. It is sourced by
# R/pipeline/../R/decision/decision_pipeline.R. All paths relative to project root.
#
# A "snapshot" is one FFA/ESPN scrape identified by season + week + tag + timestamp.
# Re-runs of the pipeline accumulate timestamps for the same season/week/tag, so we
# always take max(timestamp) and use EVERY row of that timestamp (spec 5.1) - never
# the latest timestamp per player/source.

library(tidyverse)
library(dm)

# expected fantasy positions in the current league (mirrors build_historic_datasets.R
# which drops "FB" and stray junk values)
.decision_expected_pos <- c("QB", "RB", "WR", "TE", "K", "DST")

# --- FFA -------------------------------------------------------------------------

# Select the current FFA source-projection snapshot.
# Returns a list: proj_source (tibble), timestamp, season, week, tag.
select_ffa_snapshot <- function(ffa_db, season, week, tag) {
  rows <- ffa_db$ffa_proj_source_points |>
    filter(season == !!season, week == !!week, tag == !!tag)

  if (nrow(rows) == 0L) {
    stop(glue::glue("season/week/tag not found in ffa_db: {season}/{week}/{tag}"),
         call. = FALSE)
  }

  ts <- max(rows$timestamp)

  proj_source <- rows |>
    filter(timestamp == ts) |>
    mutate(ffa_id = as.integer(id), proj_points = points) |>
    filter(!is.na(proj_points))

  list(proj_source = proj_source, timestamp = ts,
       season = season, week = week, tag = tag)
}

# --- ESPN ----------------------------------------------------------------------

# Select the current ESPN league snapshot: rosters (starter/bench/ir), the week's
# head-to-head matchups, injury status, plus the roster-slot definition and team
# list. Same snapshot rule as FFA: season + week + tag + max(timestamp).
select_espn_snapshot <- function(espn_db, season, week, tag) {
  rosters <- espn_db$espn_rosters |>
    filter(season == !!season, week == !!week, tag == !!tag)

  if (nrow(rosters) == 0L) {
    stop(glue::glue("season/week/tag not found in espn_db: {season}/{week}/{tag}"),
         call. = FALSE)
  }

  ts <- max(rosters$timestamp)
  rosters <- rosters |>
    filter(timestamp == ts) |>
    mutate(player_id = as.integer(player_id))

  # the snapshot carries the whole-season schedule; keep only this week's games
  matchups <- espn_db$espn_matchups |>
    filter(season == !!season, week == !!week, tag == !!tag) |>
    filter(timestamp == max(timestamp), matchup_period_id == !!week)

  injury <- espn_db$espn_player_injury_status |>
    filter(season == !!season, week == !!week, tag == !!tag)
  if (nrow(injury) > 0L) {
    injury <- injury |>
      filter(timestamp == max(timestamp)) |>
      mutate(player_id = as.integer(player_id))
  }

  list(
    rosters      = rosters,
    matchups     = matchups,
    injury       = injury,
    roster_slots = espn_db$espn_roster_slots |> filter(season == !!season),
    teams        = espn_db$espn_teams |> filter(season == !!season),
    # the fantasy-relevant player universe (free agents = players - rosters), spec 13.
    # No week/tag on this table, so season-only like roster_slots/teams.
    players      = espn_db$espn_players |> filter(season == !!season),
    timestamp    = ts,
    season = season, week = week, tag = tag
  )
}

# --- player identity ----------------------------------------------------------

# Current player crosswalk. analytical_db$player_ids is already the curated recut
# of ffa_db$ffa_player_ids (ffa_id / nfl_id / espn_id / numfire_id), so this is a
# thin accessor, not a rebuild (spec 6).
build_current_player_xref <- function(analytical_db) {
  analytical_db$player_ids |>
    select(ffa_id, espn_id, nfl_id, numfire_id) |>
    distinct()
}

# --- data-quality guards (spec 36) ------------------------------------------------

# One row per source/player/pos in the FFA snapshot; snapshot non-empty; projections
# not all NA; positions within the expected set. Stops on violation.
check_ffa_snapshot_quality <- function(proj_source) {
  if (nrow(proj_source) == 0L) {
    stop("FFA snapshot is empty after filtering", call. = FALSE)
  }

  dups <- proj_source |> count(data_src, ffa_id, pos) |> filter(n > 1)
  if (nrow(dups) > 0L) {
    stop(glue::glue("FFA snapshot has {nrow(dups)} duplicated data_src/ffa_id/pos rows"),
         call. = FALSE)
  }

  if (all(is.na(proj_source$proj_points))) {
    stop("FFA snapshot has no non-NA projections", call. = FALSE)
  }

  unexpected <- setdiff(unique(proj_source$pos), .decision_expected_pos)
  if (length(unexpected) > 0L) {
    warning(glue::glue("FFA snapshot has unexpected pos values: ",
                       "{paste(unexpected, collapse = ', ')}"), call. = FALSE)
  }

  invisible(TRUE)
}

# --- id-mapping report (spec 35) ------------------------------------------------

# Warn (never stop in M1 - no "relevant starter" concept yet) about consensus
# players missing an ESPN or NFL id in the crosswalk.
report_id_mapping <- function(consensus, xref) {
  mapped <- consensus |> left_join(xref, by = "ffa_id")

  n_no_espn <- sum(is.na(mapped$espn_id))
  n_no_nfl  <- sum(is.na(mapped$nfl_id))
  n_no_xref <- consensus |> anti_join(xref, by = "ffa_id") |> nrow()

  if (n_no_xref > 0L) {
    warning(glue::glue("{n_no_xref} consensus players absent from player crosswalk"),
            call. = FALSE)
  }
  if (n_no_espn > 0L) {
    warning(glue::glue("{n_no_espn} consensus players without espn_id mapping"),
            call. = FALSE)
  }
  if (n_no_nfl > 0L) {
    message(glue::glue("{n_no_nfl} consensus players without nfl_id mapping"))
  }

  invisible(list(n_no_espn = n_no_espn, n_no_nfl = n_no_nfl, n_no_xref = n_no_xref))
}
