# ESPN Fantasy Football client for R
# League default: 342842788 | Season default: 2026
#
# Dependencies:
#   install.packages(c("httr2", "jsonlite", "dplyr", "purrr", "tibble", "tidyr"))
#
# Private leagues:
#   Sys.setenv(ESPN_S2 = "...")
#   Sys.setenv(ESPN_SWID = "{...}")
#
# Notes:
# - ESPN Fantasy API is unofficial/undocumented and may change.
# - Read endpoint: https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/...

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

.espn_chr <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) return(default)
  as.character(x[[1]])
}

.espn_int <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0L) return(default)
  suppressWarnings(as.integer(x[[1]]))
}

.espn_num <- function(x, default = NA_real_) {
  if (is.null(x) || length(x) == 0L) return(default)
  suppressWarnings(as.numeric(x[[1]]))
}

.espn_lgl <- function(x, default = NA) {
  if (is.null(x) || length(x) == 0L) return(default)
  as.logical(x[[1]])
}

.espn_date_ms <- function(x, tz = "UTC") {
  x <- .espn_num(x)
  if (is.na(x) || x <= 0) return(as.POSIXct(NA, tz = tz))
  as.POSIXct(x / 1000, origin = "1970-01-01", tz = tz)
}

.espn_compact_chr <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  paste(as.character(unlist(x, use.names = FALSE)), collapse = ",")
}

# Common ESPN football IDs.
espn_lineup_slot_map <- function() {
  tibble::tribble(
    ~lineup_slot_id, ~lineup_slot,
     0L, "QB",
     1L, "TQB",
     2L, "RB",
     3L, "RB/WR",
     4L, "WR",
     5L, "WR/TE",
     6L, "TE",
     7L, "OP",
     8L, "DT",
     9L, "DE",
    10L, "LB",
    11L, "DL",
    12L, "CB",
    13L, "S",
    14L, "DB",
    15L, "DP",
    16L, "D/ST",
    17L, "K",
    18L, "P",
    19L, "HC",
    20L, "BE",
    21L, "IR",
    22L, "",
    23L, "FLEX",
    24L, "ER",
    25L, "ROOKIE"
  )
}

espn_default_position_map <- function() {
  tibble::tribble(
    ~default_position_id, ~position,
    1L, "QB",
    2L, "RB",
    3L, "WR",
    4L, "TE",
    5L, "K",
    16L, "D/ST"
  )
}

espn_pro_team_map <- function() {
  tibble::tribble(
    ~pro_team_id, ~pro_team,
     0L, "FA",
     1L, "ATL",
     2L, "BUF",
     3L, "CHI",
     4L, "CIN",
     5L, "CLE",
     6L, "DAL",
     7L, "DEN",
     8L, "DET",
     9L, "GB",
    10L, "TEN",
    11L, "IND",
    12L, "KC",
    13L, "LV",
    14L, "LAR",
    15L, "MIA",
    16L, "MIN",
    17L, "NE",
    18L, "NO",
    19L, "NYG",
    20L, "NYJ",
    21L, "PHI",
    22L, "ARI",
    23L, "PIT",
    24L, "LAC",
    25L, "SF",
    26L, "SEA",
    27L, "TB",
    28L, "WSH",
    29L, "CAR",
    30L, "JAX",
    33L, "BAL",
    34L, "HOU"
  )
}

espn_client <- function(
    league_id = "342842788",
    season = 2026L,
    espn_s2 = Sys.getenv("ESPN_S2", unset = ""),
    swid = Sys.getenv("ESPN_SWID", unset = Sys.getenv("SWID", unset = "")),
    timeout = 30,
    max_tries = 4L,
    cache_dir = NULL) {

  stopifnot(length(league_id) == 1L, length(season) == 1L)

  out <- list(
    league_id = as.character(league_id),
    season = as.integer(season),
    espn_s2 = as.character(espn_s2 %||% ""),
    swid = as.character(swid %||% ""),
    timeout = as.numeric(timeout),
    max_tries = as.integer(max_tries),
    cache_dir = cache_dir,
    host = "https://lm-api-reads.fantasy.espn.com",
    game = "ffl"
  )
  class(out) <- "espn_fantasy_client"
  out
}

print.espn_fantasy_client <- function(x, ...) {
  cat("<espn_fantasy_client>\n")
  cat("  league_id:", x$league_id, "\n")
  cat("  season:   ", x$season, "\n")
  cat("  auth:     ", if (nzchar(x$espn_s2) && nzchar(x$swid)) "cookies configured" else "no cookies", "\n")
  invisible(x)
}

espn_has_auth <- function(client) {
  nzchar(client$espn_s2) && nzchar(client$swid)
}

.espn_league_url <- function(client) {
  sprintf(
    "%s/apis/v3/games/%s/seasons/%d/segments/0/leagues/%s",
    client$host,
    client$game,
    client$season,
    client$league_id
  )
}

.espn_request <- function(
    client,
    url,
    views = NULL,
    query = list(),
    fantasy_filter = NULL) {

  req <- httr2::request(url) |>
    httr2::req_headers(
      Accept = "application/json",
      `User-Agent` = "R espn-fantasy-client/1.0"
    ) |>
    httr2::req_timeout(client$timeout) |>
    httr2::req_retry(
      max_tries = client$max_tries,
      retry_on_failure = TRUE,
      is_transient = function(resp) {
        httr2::resp_status(resp) %in% c(408L, 425L, 429L, 500L, 502L, 503L, 504L)
      }
    )

  if (!is.null(views) && length(views) > 0L) {
    req <- httr2::req_url_query(req, view = views, .multi = "explode")
  }

  if (length(query) > 0L) {
    req <- do.call(httr2::req_url_query, c(list(.req = req), query))
  }

  if (espn_has_auth(client)) {
    req <- httr2::req_headers(
      req,
      Cookie = sprintf("espn_s2=%s; SWID=%s", client$espn_s2, client$swid)
    )
  }

  if (!is.null(fantasy_filter)) {
    filter_json <- jsonlite::toJSON(
      fantasy_filter,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    )
    req <- httr2::req_headers(req, `X-Fantasy-Filter` = filter_json)
  }

  if (!is.null(client$cache_dir) && nzchar(client$cache_dir)) {
    req <- httr2::req_cache(req, path = client$cache_dir, use_on_error = TRUE)
  }

  resp <- tryCatch(
    httr2::req_perform(req),
    httr2_http_401 = function(cnd) {
      stop(
        paste0(
          "ESPN retornou HTTP 401. A liga provavelmente e privada, os cookies expiraram, ",
          "ou a conta autenticada nao tem acesso. Configure ESPN_S2 e ESPN_SWID."
        ),
        call. = FALSE
      )
    },
    httr2_http_403 = function(cnd) {
      stop("ESPN retornou HTTP 403. Verifique autenticacao/cookies e tente novamente.", call. = FALSE)
    },
    httr2_http_404 = function(cnd) {
      stop(
        sprintf(
          "ESPN retornou HTTP 404 para league_id=%s season=%d. Verifique o ano da liga.",
          client$league_id,
          client$season
        ),
        call. = FALSE
      )
    }
  )

  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

# Low-level league getter. Multiple views are sent as repeated query parameters.
espn_raw <- function(
    client,
    views,
    week = NULL,
    matchup_period = NULL,
    fantasy_filter = NULL) {

  query <- list()
  if (!is.null(week)) query$scoringPeriodId <- as.integer(week)
  if (!is.null(matchup_period)) query$matchupPeriodId <- as.integer(matchup_period)

  .espn_request(
    client = client,
    url = .espn_league_url(client),
    views = views,
    query = query,
    fantasy_filter = fantasy_filter
  )
}

# Public ESPN Fantasy metadata, useful for detecting the current season/week.
espn_game_meta <- function(client = espn_client()) {
  url <- sprintf("%s/apis/v3/games/%s", client$host, client$game)
  .espn_request(client, url)
}

espn_season_meta <- function(client = espn_client()) {
  url <- sprintf(
    "%s/apis/v3/games/%s/seasons/%d",
    client$host,
    client$game,
    client$season
  )
  .espn_request(client, url)
}

espn_current_week <- function(client = espn_client()) {
  meta <- espn_season_meta(client)
  .espn_int(meta$currentScoringPeriod$id, default = NA_integer_)
}

.espn_team_name <- function(team) {
  name <- .espn_chr(team$name)
  if (!is.na(name) && nzchar(name)) return(name)

  location <- .espn_chr(team$location, default = "")
  nickname <- .espn_chr(team$nickname, default = "")
  out <- trimws(paste(location, nickname))
  if (nzchar(out)) out else paste0("Team ", .espn_int(team$id))
}

.espn_parse_members <- function(raw) {
  members <- raw$members %||% list()
  if (length(members) == 0L) {
    return(tibble::tibble(
      member_id = character(), display_name = character(),
      first_name = character(), last_name = character(),
      is_league_manager = logical()
    ))
  }

  purrr::map_dfr(members, function(m) {
    tibble::tibble(
      member_id = .espn_chr(m$id),
      display_name = .espn_chr(m$displayName),
      first_name = .espn_chr(m$firstName),
      last_name = .espn_chr(m$lastName),
      is_league_manager = .espn_lgl(m$isLeagueManager, FALSE)
    )
  })
}

.espn_parse_teams <- function(raw) {
  teams <- raw$teams %||% list()
  members <- .espn_parse_members(raw)

  if (length(teams) == 0L) return(tibble::tibble())

  purrr::map_dfr(teams, function(t) {
    owner_ids <- unlist(t$owners %||% list(), use.names = FALSE)
    owner_names <- members$display_name[match(owner_ids, members$member_id)]
    owner_names <- owner_names[!is.na(owner_names)]
    overall <- t$record$overall %||% list()
    tx <- t$transactionCounter %||% list()

    tibble::tibble(
      team_id = .espn_int(t$id),
      team_name = .espn_team_name(t),
      abbrev = .espn_chr(t$abbrev),
      owner_ids = if (length(owner_ids)) paste(owner_ids, collapse = ",") else NA_character_,
      owners = if (length(owner_names)) paste(owner_names, collapse = ", ") else NA_character_,
      division_id = .espn_int(t$divisionId),
      current_projected_rank = .espn_int(t$currentProjectedRank),
      draft_day_projected_rank = .espn_int(t$draftDayProjectedRank),
      waiver_rank = .espn_int(t$waiverRank),
      points = .espn_num(t$points),
      points_adjusted = .espn_num(t$pointsAdjusted),
      wins = .espn_int(overall$wins, 0L),
      losses = .espn_int(overall$losses, 0L),
      ties = .espn_int(overall$ties, 0L),
      win_pct = .espn_num(overall$percentage),
      points_for = .espn_num(overall$pointsFor),
      points_against = .espn_num(overall$pointsAgainst),
      streak_type = .espn_chr(overall$streakType),
      streak_length = .espn_int(overall$streakLength),
      acquisitions = .espn_int(tx$acquisitions, 0L),
      drops = .espn_int(tx$drops, 0L),
      trades = .espn_int(tx$trades, 0L)
    )
  })
}

espn_teams <- function(client = espn_client()) {
  raw <- espn_raw(client, views = c("mTeam", "mStandings"))
  .espn_parse_teams(raw)
}

espn_members <- function(client = espn_client()) {
  raw <- espn_raw(client, views = "mTeam")
  .espn_parse_members(raw)
}

.espn_parse_rosters <- function(raw) {
  teams <- raw$teams %||% list()
  if (length(teams) == 0L) return(tibble::tibble())

  pos_map <- espn_default_position_map()
  slot_map <- espn_lineup_slot_map()
  pro_map <- espn_pro_team_map()

  out <- purrr::map_dfr(teams, function(t) {
    entries <- t$roster$entries %||% list()
    if (length(entries) == 0L) return(tibble::tibble())

    purrr::map_dfr(entries, function(e) {
      pool <- e$playerPoolEntry %||% list()
      p <- pool$player %||% list()

      tibble::tibble(
        team_id = .espn_int(t$id),
        team_name = .espn_team_name(t),
        player_id = .espn_int(e$playerId %||% pool$id %||% p$id),
        player_name = .espn_chr(p$fullName),
        first_name = .espn_chr(p$firstName),
        last_name = .espn_chr(p$lastName),
        pro_team_id = .espn_int(p$proTeamId),
        default_position_id = .espn_int(p$defaultPositionId),
        lineup_slot_id = .espn_int(e$lineupSlotId),
        acquisition_type = .espn_chr(e$acquisitionType %||% pool$acquisitionType),
        acquisition_date = .espn_date_ms(e$acquisitionDate %||% pool$acquisitionDate),
        percent_owned = .espn_num(pool$percentOwned),
        percent_started = .espn_num(pool$percentStarted),
        total_points = .espn_num(pool$totalPoints),
        applied_stat_total = .espn_num(pool$appliedStatTotal),
        injury_status = .espn_chr(e$injuryStatus %||% p$injuryStatus),
        active = .espn_lgl(p$active),
        injured = .espn_lgl(p$injured),
        droppable = .espn_lgl(p$droppable),
        lineup_locked = .espn_lgl(pool$lineupLocked),
        eligible_slot_ids = .espn_compact_chr(p$eligibleSlots),
        stats_raw = list(p$stats %||% list())
      )
    })
  })

  out |>
    dplyr::left_join(pos_map, by = "default_position_id") |>
    dplyr::left_join(slot_map, by = "lineup_slot_id") |>
    dplyr::left_join(pro_map, by = "pro_team_id") |>
    dplyr::mutate(
      is_starter = !lineup_slot_id %in% c(20L, 21L),
      is_bench = lineup_slot_id == 20L,
      is_ir = lineup_slot_id == 21L
    ) |>
    dplyr::relocate(
      team_id, team_name, player_id, player_name, position, pro_team,
      lineup_slot, is_starter
    )
}

espn_rosters <- function(client = espn_client(), week = NULL) {
  if (is.null(week)) week <- espn_current_week(client)
  raw <- espn_raw(client, views = c("mTeam", "mRoster"), week = week)
  .espn_parse_rosters(raw)
}

espn_starters <- function(client = espn_client(), week = NULL) {
  espn_rosters(client, week) |>
    dplyr::filter(is_starter)
}

espn_bench <- function(client = espn_client(), week = NULL) {
  espn_rosters(client, week) |>
    dplyr::filter(is_bench)
}

.espn_parse_schedule <- function(raw) {
  schedule <- raw$schedule %||% list()
  if (length(schedule) == 0L) return(tibble::tibble())

  teams <- .espn_parse_teams(raw) |>
    dplyr::select(team_id, team_name)

  out <- purrr::map_dfr(schedule, function(m) {
    home <- m$home %||% list()
    away <- m$away %||% list()

    tibble::tibble(
      matchup_id = .espn_int(m$id),
      matchup_period_id = .espn_int(m$matchupPeriodId),
      playoff_tier_type = .espn_chr(m$playoffTierType),
      winner = .espn_chr(m$winner),
      home_team_id = .espn_int(home$teamId),
      home_points = .espn_num(home$totalPoints),
      home_projected_points = .espn_num(home$totalProjectedPointsLive),
      away_team_id = .espn_int(away$teamId),
      away_points = .espn_num(away$totalPoints),
      away_projected_points = .espn_num(away$totalProjectedPointsLive)
    )
  })

  out |>
    dplyr::left_join(
      dplyr::rename(teams, home_team_id = team_id, home_team_name = team_name),
      by = "home_team_id"
    ) |>
    dplyr::left_join(
      dplyr::rename(teams, away_team_id = team_id, away_team_name = team_name),
      by = "away_team_id"
    ) |>
    dplyr::relocate(
      matchup_id, matchup_period_id,
      home_team_id, home_team_name, home_points, home_projected_points,
      away_team_id, away_team_name, away_points, away_projected_points,
      winner
    )
}

espn_matchups <- function(client = espn_client(), week = NULL) {
  if (is.null(week)) week <- espn_current_week(client)
  raw <- espn_raw(
    client,
    views = c("mTeam", "mMatchupScore", "mStandings"),
    week = week,
    matchup_period = week
  )
  .espn_parse_schedule(raw)
}

espn_scoreboard <- function(client = espn_client(), week = NULL) {
  if (is.null(week)) week <- espn_current_week(client)
  raw <- espn_raw(
    client,
    views = c("mTeam", "mScoreboard", "mLiveScoring"),
    week = week,
    matchup_period = week
  )
  .espn_parse_schedule(raw)
}

.espn_parse_draft <- function(raw) {
  picks <- raw$draftDetail$picks %||% list()
  if (length(picks) == 0L) return(tibble::tibble())

  teams <- .espn_parse_teams(raw) |>
    dplyr::select(team_id, team_name)

  purrr::map_dfr(picks, function(p) {
    tibble::tibble(
      pick_id = .espn_int(p$id),
      overall_pick = .espn_int(p$overallPickNumber),
      round = .espn_int(p$roundId),
      round_pick = .espn_int(p$roundPickNumber),
      team_id = .espn_int(p$teamId),
      player_id = .espn_int(p$playerId),
      bid_amount = .espn_num(p$bidAmount),
      auto_draft_type_id = .espn_int(p$autoDraftTypeId),
      keeper = .espn_lgl(p$keeper, FALSE),
      trade_locked = .espn_lgl(p$tradeLocked, FALSE)
    )
  }) |>
    dplyr::left_join(teams, by = "team_id") |>
    dplyr::arrange(overall_pick) |>
    dplyr::relocate(overall_pick, round, round_pick, team_id, team_name, player_id)
}

espn_draft <- function(client = espn_client(), resolve_players = TRUE) {
  raw <- espn_raw(client, views = c("mTeam", "mDraftDetail"))
  out <- .espn_parse_draft(raw)

  if (!resolve_players || nrow(out) == 0L) return(out)

  pool <- tryCatch(
    espn_player_pool(
      client,
      status = c("FREEAGENT", "WAIVERS", "ONTEAM"),
      limit = 5000L
    ),
    error = function(e) tibble::tibble()
  )

  if (nrow(pool) == 0L) return(out)

  out |>
    dplyr::left_join(
      pool |>
        dplyr::select(player_id, player_name, position, pro_team) |>
        dplyr::distinct(player_id, .keep_all = TRUE),
      by = "player_id"
    ) |>
    dplyr::relocate(player_name, position, pro_team, .after = player_id)
}

.espn_player_filter <- function(
    status = c("FREEAGENT", "WAIVERS"),
    slot_ids = c(0L, 2L, 4L, 6L, 16L, 17L, 23L),
    limit = 1000L) {

  list(
    players = list(
      filterStatus = list(value = as.list(as.character(status))),
      filterSlotIds = list(value = as.list(as.integer(slot_ids))),
      limit = as.integer(limit),
      sortPercOwned = list(sortPriority = 1L, sortAsc = FALSE)
    )
  )
}

.espn_parse_player_pool <- function(raw) {
  players <- raw$players %||% list()
  if (length(players) == 0L) return(tibble::tibble())

  pos_map <- espn_default_position_map()
  pro_map <- espn_pro_team_map()

  out <- purrr::map_dfr(players, function(pool) {
    p <- pool$player %||% list()

    tibble::tibble(
      player_id = .espn_int(pool$id %||% p$id),
      player_name = .espn_chr(p$fullName),
      first_name = .espn_chr(p$firstName),
      last_name = .espn_chr(p$lastName),
      on_team_id = .espn_int(pool$onTeamId, 0L),
      pro_team_id = .espn_int(p$proTeamId),
      default_position_id = .espn_int(p$defaultPositionId),
      status = .espn_chr(pool$status),
      percent_owned = .espn_num(pool$percentOwned),
      percent_started = .espn_num(pool$percentStarted),
      total_points = .espn_num(pool$totalPoints),
      applied_stat_total = .espn_num(pool$appliedStatTotal),
      injury_status = .espn_chr(p$injuryStatus),
      active = .espn_lgl(p$active),
      injured = .espn_lgl(p$injured),
      droppable = .espn_lgl(p$droppable),
      eligible_slot_ids = .espn_compact_chr(p$eligibleSlots),
      stats_raw = list(p$stats %||% list())
    )
  })

  out |>
    dplyr::left_join(pos_map, by = "default_position_id") |>
    dplyr::left_join(pro_map, by = "pro_team_id") |>
    dplyr::relocate(player_id, player_name, position, pro_team, on_team_id)
}

espn_player_pool <- function(
    client = espn_client(),
    status = c("FREEAGENT", "WAIVERS"),
    week = NULL,
    slot_ids = c(0L, 2L, 4L, 6L, 16L, 17L, 23L),
    limit = 1000L) {

  if (is.null(week)) week <- espn_current_week(client)

  filter <- .espn_player_filter(
    status = status,
    slot_ids = slot_ids,
    limit = limit
  )

  raw <- espn_raw(
    client,
    views = "kona_player_info",
    week = week,
    fantasy_filter = filter
  )

  .espn_parse_player_pool(raw)
}

espn_available_players <- function(
    client = espn_client(),
    week = NULL,
    slot_ids = c(0L, 2L, 4L, 6L, 16L, 17L, 23L),
    limit = 1000L) {

  espn_player_pool(
    client,
    status = c("FREEAGENT", "WAIVERS"),
    week = week,
    slot_ids = slot_ids,
    limit = limit
  )
}

espn_all_players <- function(
    client = espn_client(),
    week = NULL,
    limit = 5000L) {

  espn_player_pool(
    client,
    status = c("FREEAGENT", "WAIVERS", "ONTEAM"),
    week = week,
    slot_ids = c(0L, 2L, 4L, 6L, 16L, 17L, 23L),
    limit = limit
  )
}

# Expand player$stats into one row per ESPN stat record.
# statSourceId: 0 is typically actual, 1 projected.
.espn_expand_stats <- function(player_tbl) {
  if (nrow(player_tbl) == 0L || !"stats_raw" %in% names(player_tbl)) {
    return(tibble::tibble())
  }

  purrr::map_dfr(seq_len(nrow(player_tbl)), function(i) {
    stats <- player_tbl$stats_raw[[i]] %||% list()
    if (length(stats) == 0L) return(tibble::tibble())

    purrr::map_dfr(stats, function(s) {
      tibble::tibble(
        player_id = player_tbl$player_id[[i]],
        player_name = player_tbl$player_name[[i]],
        position = player_tbl$position[[i]],
        pro_team = player_tbl$pro_team[[i]],
        season_id = .espn_int(s$seasonId),
        scoring_period_id = .espn_int(s$scoringPeriodId),
        stat_source_id = .espn_int(s$statSourceId),
        stat_split_type_id = .espn_int(s$statSplitTypeId),
        pro_team_id = .espn_int(s$proTeamId),
        fantasy_points = .espn_num(s$appliedTotal),
        stats = list(s$stats %||% list()),
        applied_stats = list(s$appliedStats %||% list())
      )
    })
  })
}

espn_player_stats <- function(
    client = espn_client(),
    week = NULL,
    status = c("FREEAGENT", "WAIVERS", "ONTEAM"),
    limit = 5000L) {

  pool <- espn_player_pool(
    client = client,
    status = status,
    week = week,
    limit = limit
  )

  .espn_expand_stats(pool)
}

espn_projection_table <- function(client = espn_client(), week = NULL, limit = 5000L) {
  if (is.null(week)) week <- espn_current_week(client)

  espn_player_stats(client, week = week, limit = limit) |>
    dplyr::filter(
      scoring_period_id == as.integer(week),
      stat_source_id == 1L
    ) |>
    dplyr::select(player_id, player_name, position, pro_team, projected_points = fantasy_points)
}

espn_actual_points_table <- function(client = espn_client(), week = NULL, limit = 5000L) {
  if (is.null(week)) week <- espn_current_week(client)

  espn_player_stats(client, week = week, limit = limit) |>
    dplyr::filter(
      scoring_period_id == as.integer(week),
      stat_source_id == 0L
    ) |>
    dplyr::select(player_id, player_name, position, pro_team, actual_points = fantasy_points)
}

.espn_parse_roster_slots <- function(raw) {
  slots <- raw$settings$rosterSettings$lineupSlotCounts %||% list()
  if (length(slots) == 0L) return(tibble::tibble())

  tibble::tibble(
    lineup_slot_id = as.integer(names(slots)),
    count = as.integer(unlist(slots, use.names = FALSE))
  ) |>
    dplyr::left_join(espn_lineup_slot_map(), by = "lineup_slot_id") |>
    dplyr::relocate(lineup_slot_id, lineup_slot, count)
}

espn_roster_slots <- function(client = espn_client()) {
  raw <- espn_raw(client, views = "mSettings")
  .espn_parse_roster_slots(raw)
}

.espn_parse_scoring_rules <- function(raw) {
  items <- raw$settings$scoringSettings$scoringItems %||% list()
  if (length(items) == 0L) return(tibble::tibble())

  purrr::map_dfr(items, function(x) {
    tibble::tibble(
      stat_id = .espn_int(x$statId),
      points = .espn_num(x$points),
      is_reverse_item = .espn_lgl(x$isReverseItem, FALSE),
      points_overrides = list(x$pointsOverrides %||% list())
    )
  })
}

espn_scoring_rules <- function(client = espn_client()) {
  raw <- espn_raw(client, views = "mSettings")
  .espn_parse_scoring_rules(raw)
}

.espn_parse_league_summary <- function(raw) {
  s <- raw$settings %||% list()
  d <- s$draftSettings %||% list()
  r <- s$rosterSettings %||% list()
  a <- s$acquisitionSettings %||% list()
  sc <- s$scheduleSettings %||% list()
  status <- raw$status %||% list()

  tibble::tibble(
    league_id = .espn_chr(raw$id),
    season = .espn_int(raw$seasonId),
    league_name = .espn_chr(s$name),
    size = .espn_int(s$size),
    current_scoring_period = .espn_int(raw$scoringPeriodId %||% status$currentScoringPeriod$id),
    current_matchup_period = .espn_int(status$currentMatchupPeriod),
    final_scoring_period = .espn_int(status$finalScoringPeriod),
    draft_date = .espn_date_ms(d$date),
    draft_type = .espn_int(d$type),
    draft_time_per_selection = .espn_int(d$timePerSelection),
    draft_slot_count = .espn_int(d$slotCount),
    roster_locktime = .espn_int(r$lineupLocktime %||% r$locktime),
    waiver_process_days = .espn_int(a$waiverProcessDays),
    matchup_period_count = .espn_int(sc$matchupPeriodCount)
  )
}

espn_league <- function(client = espn_client()) {
  raw <- espn_raw(client, views = c("mSettings", "mStatus"))
  .espn_parse_league_summary(raw)
}

.espn_parse_transactions <- function(raw) {
  txs <- raw$transactions %||% list()
  if (length(txs) == 0L) return(tibble::tibble())

  teams <- .espn_parse_teams(raw) |>
    dplyr::select(team_id, team_name)

  out <- purrr::map_dfr(txs, function(tx) {
    items <- tx$items %||% list()

    if (length(items) == 0L) {
      items <- list(list())
    }

    purrr::map_dfr(items, function(item) {
      tibble::tibble(
        transaction_id = .espn_chr(tx$id),
        transaction_type = .espn_chr(tx$type),
        execution_type = .espn_chr(tx$executionType),
        status = .espn_chr(tx$status),
        team_id = .espn_int(tx$teamId),
        scoring_period_id = .espn_int(tx$scoringPeriodId),
        process_date = .espn_date_ms(tx$processDate),
        proposed_date = .espn_date_ms(tx$proposedDate),
        bid_amount = .espn_num(tx$bidAmount),
        priority = .espn_int(tx$priority),
        member_id = .espn_chr(tx$memberId),
        item_type = .espn_chr(item$type),
        player_id = .espn_int(item$playerId),
        from_team_id = .espn_int(item$fromTeamId),
        to_team_id = .espn_int(item$toTeamId),
        is_keeper = .espn_lgl(item$isKeeper, FALSE)
      )
    })
  })

  out |>
    dplyr::left_join(teams, by = "team_id") |>
    dplyr::relocate(transaction_id, process_date, transaction_type, status, team_id, team_name)
}

espn_transactions <- function(client = espn_client(), week = NULL, resolve_players = TRUE) {
  if (is.null(week)) week <- espn_current_week(client)

  raw <- espn_raw(
    client,
    views = c("mTeam", "mTransactions2"),
    week = week
  )

  out <- .espn_parse_transactions(raw)
  if (!resolve_players || nrow(out) == 0L) return(out)

  pool <- tryCatch(espn_all_players(client, week = week), error = function(e) tibble::tibble())
  if (nrow(pool) == 0L) return(out)

  out |>
    dplyr::left_join(
      pool |>
        dplyr::select(player_id, player_name, position, pro_team) |>
        dplyr::distinct(player_id, .keep_all = TRUE),
      by = "player_id"
    ) |>
    dplyr::relocate(player_name, position, pro_team, .after = player_id)
}

# Fetches the main league state in one combined request, then parses locally.
espn_snapshot <- function(
    client = espn_client(),
    week = NULL,
    include_available = TRUE,
    available_limit = 1000L,
    include_transactions = TRUE) {

  if (is.null(week)) week <- espn_current_week(client)

  views <- c(
    "mSettings",
    "mStatus",
    "mTeam",
    "mRoster",
    "mStandings",
    "mMatchupScore",
    "mDraftDetail"
  )
  if (include_transactions) views <- c(views, "mTransactions2")

  raw <- espn_raw(
    client,
    views = views,
    week = week,
    matchup_period = week
  )

  rosters <- .espn_parse_rosters(raw)

  result <- list(
    league = .espn_parse_league_summary(raw),
    members = .espn_parse_members(raw),
    teams = .espn_parse_teams(raw),
    roster_slots = .espn_parse_roster_slots(raw),
    scoring_rules = .espn_parse_scoring_rules(raw),
    rosters = rosters,
    starters = dplyr::filter(rosters, is_starter),
    bench = dplyr::filter(rosters, is_bench),
    matchups = .espn_parse_schedule(raw),
    draft = .espn_parse_draft(raw),
    transactions = if (include_transactions) .espn_parse_transactions(raw) else tibble::tibble(),
    raw = raw
  )

  if (include_available) {
    result$available_players <- espn_available_players(
      client,
      week = week,
      limit = available_limit
    )
  } else {
    result$available_players <- tibble::tibble()
  }

  result
}

# Optional ffscrapr adapter. Useful when you prefer its standardized tidy API.
espn_ffscrapr_connect <- function(client = espn_client()) {
  if (!requireNamespace("ffscrapr", quietly = TRUE)) {
    stop(
      "Pacote 'ffscrapr' nao instalado. Use install.packages('ffscrapr') ou a versao ffverse/r-universe.",
      call. = FALSE
    )
  }

  args <- list(
    season = client$season,
    league_id = as.numeric(client$league_id)
  )

  if (espn_has_auth(client)) {
    args$espn_s2 <- client$espn_s2
    args$swid <- client$swid
  }

  do.call(ffscrapr::espn_connect, args)
}

espn_ffscrapr_snapshot <- function(client = espn_client()) {
  conn <- espn_ffscrapr_connect(client)

  safe <- function(expr) {
    tryCatch(expr, error = function(e) {
      warning(conditionMessage(e), call. = FALSE)
      tibble::tibble()
    })
  }

  list(
    connection = conn,
    league = safe(ffscrapr::ff_league(conn)),
    franchises = safe(ffscrapr::ff_franchises(conn)),
    rosters = safe(ffscrapr::ff_rosters(conn)),
    starters = safe(ffscrapr::ff_starters(conn)),
    schedule = safe(ffscrapr::ff_schedule(conn)),
    standings = safe(ffscrapr::ff_standings(conn)),
    draft = safe(ffscrapr::ff_draft(conn)),
    transactions = safe(ffscrapr::ff_transactions(conn))
  )
}

# Convenience health check.
espn_test_connection <- function(client = espn_client()) {
  out <- tryCatch(
    {
      x <- espn_league(client)
      list(ok = TRUE, league = x, error = NULL)
    },
    error = function(e) list(ok = FALSE, league = NULL, error = conditionMessage(e))
  )

  class(out) <- c("espn_connection_test", class(out))
  out
}
