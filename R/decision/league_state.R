# Decision engine - Phase 4: current league state (spec 12) + ESPN->FFA id bridge.
#
# The ESPN roster keys on ESPN player_id; the forecasts key on ffa_id. The bridge
# resolves ESPN player_id -> ffa_id with four strategies, tried in order and
# coalesced (an earlier hit is never overwritten):
#
#   0  manual override file (data/decision_espn_ffa_overrides.rds)
#   1  direct: ESPN player_id == analytical_db$player_ids$espn_id
#   2  D/ST negative-id offset: 44000 - player_id == ffa espn_id (60000-offset)
#      (from R_old/import/espn_scraper.R)
#   3  unique normalised name + position against ffa_db$ffa_players
#
# Computed fresh every run - fast, deterministic, and id mapping drifts every
# season, so a computed cache would only go stale. Only the hand-curated override
# file persists.

library(tidyverse)
library(dm)

.OVERRIDES_FILE <- "./data/decision_espn_ffa_overrides.rds"

# tibble(player_id int, ffa_id int); 0 rows if the file is absent.
load_espn_ffa_overrides <- function(file = .OVERRIDES_FILE) {
  if (!file.exists(file)) {
    return(tibble(player_id = integer(), ffa_id = integer()))
  }
  readRDS(file) |>
    transmute(player_id = as.integer(player_id), ffa_id = as.integer(ffa_id)) |>
    filter(!is.na(player_id), !is.na(ffa_id)) |>
    distinct()
}

.norm_name <- function(x) str_replace_all(str_squish(str_to_lower(x)), "[^a-z ]", "")
.norm_pos  <- function(x) if_else(x %in% c("DEF", "D/ST"), "DST", x)

# rosters: espn_snap$rosters. Returns rosters + ffa_id + bridge_method.
bridge_espn_to_ffa <- function(rosters, analytical_db, ffa_db,
                               overrides = load_espn_ffa_overrides()) {

  out <- rosters |>
    mutate(.rid = row_number(), ffa_id = NA_integer_, bridge_method = NA_character_)

  take <- function(out, hits, method) {
    # hits: tibble(.rid, .cand) - fill ffa_id/bridge_method only where still NA
    out |>
      left_join(hits, by = ".rid") |>
      mutate(
        bridge_method = if_else(is.na(ffa_id) & !is.na(.cand), method, bridge_method),
        ffa_id        = coalesce(ffa_id, .cand)
      ) |>
      select(-.cand)
  }

  # 0 - manual override
  if (nrow(overrides) > 0L) {
    h0 <- out |> select(.rid, player_id) |>
      inner_join(overrides, by = "player_id") |>
      transmute(.rid, .cand = ffa_id)
    out <- take(out, h0, "override")
  }

  # 1 - direct espn_id
  s1 <- analytical_db$player_ids |> distinct(ffa_id, espn_id) |> filter(!is.na(espn_id))
  h1 <- out |> filter(is.na(ffa_id)) |> select(.rid, player_id) |>
    inner_join(s1, by = c("player_id" = "espn_id")) |>
    transmute(.rid, .cand = as.integer(ffa_id))
  out <- take(out, h1, "espn_id")

  # 2 - D/ST negative-id offset
  ffa_espn <- ffa_db$ffa_player_ids |>
    transmute(f = as.integer(id), espn_id = as.integer(espn_id)) |>
    filter(!is.na(espn_id))
  h2 <- out |> filter(is.na(ffa_id), position == "D/ST") |>
    transmute(.rid, espn_id = 44000L - player_id) |>
    inner_join(ffa_espn, by = "espn_id") |>
    transmute(.rid, .cand = f)
  out <- take(out, h2, "dst_offset")

  # 3 - unique normalised name + pos
  ffp <- ffa_db$ffa_players |>
    transmute(f = as.integer(id), nm = .norm_name(paste(first_name, last_name)),
              p = .norm_pos(pos))
  h3 <- out |> filter(is.na(ffa_id)) |>
    transmute(.rid, nm = .norm_name(player_name), p = .norm_pos(position)) |>
    inner_join(ffp, by = c("nm", "p")) |>
    add_count(.rid) |> filter(n == 1L) |>
    transmute(.rid, .cand = f)
  out <- take(out, h3, "name_pos")

  out |> select(-.rid)
}

# --- current league state (spec 12) ------------------------------------------

# espn_snap: from select_espn_snapshot(). player_forecasts: M1 output for the run.
# bridged: optional pre-computed bridge_espn_to_ffa(espn_snap$rosters, ...) to
#   avoid bridging twice in one pipeline run.
# Returns current_players - 1 row per ESPN roster player.
build_current_league_state <- function(espn_snap, player_forecasts,
                                       analytical_db, ffa_db, bridged = NULL) {

  bridged <- bridged %||% bridge_espn_to_ffa(espn_snap$rosters, analytical_db, ffa_db)

  fc <- player_forecasts |>
    select(ffa_id, projection, sim_mean, sim_sd, p10, p50, p90,
           coverage_class, n_sources)

  inj <- espn_snap$injury |>
    select(player_id, inj_status = injury_status, injured, active)

  rlz <- (espn_snap$realized %||% tibble(player_id = integer(), is_locked = logical())) |>
    select(player_id, is_locked)

  bridged |>
    left_join(inj, by = "player_id") |>
    left_join(rlz, by = "player_id") |>
    left_join(fc, by = "ffa_id") |>
    transmute(
      season = as.integer(espn_snap$season),
      week   = as.integer(espn_snap$week),
      tag    = espn_snap$tag,
      team_id,
      espn_id = player_id,
      ffa_id, bridge_method,
      player_name, position,
      pos = .norm_pos(position),
      nfl_team = pro_team,
      lineup_slot, lineup_slot_id, eligible_slot_ids,
      is_starter, is_bench, is_ir,
      injury_status = coalesce(inj_status, injury_status),
      injured, active,
      is_locked = coalesce(is_locked, FALSE),
      projection, sim_mean, sim_sd, p10, p50, p90, coverage_class, n_sources
    )
}

# Guard (spec 35/36): every projected starter must carry a forecast; unmapped
# bench players are only a warning.
check_starters_have_forecast <- function(current_players) {
  bad <- current_players |>
    filter(is_starter, is.na(ffa_id) | is.na(sim_mean))
  if (nrow(bad) > 0L) {
    stop(glue::glue(
      "{nrow(bad)} projected starter(s) without a forecast:\n",
      paste0("  ", bad$player_name, " (", bad$position, ", team ", bad$team_id, ")",
             collapse = "\n")
    ), call. = FALSE)
  }

  n_bench <- current_players |> filter(!is_starter, is.na(ffa_id)) |> nrow()
  if (n_bench > 0L) {
    warning(glue::glue("{n_bench} non-starter roster players unmapped to ffa_id"),
            call. = FALSE)
  }
  invisible(TRUE)
}
