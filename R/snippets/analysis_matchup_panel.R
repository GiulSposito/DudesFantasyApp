# Ad-hoc analysis: player-week panel for the Against Rank and QB studies
# (docs/analysis_against_rank_qb.md). Not part of the pipeline.
#
# One row per season, week, ffa_id, pos with the projection, the realized points,
# the opposing defense's Against Rank and the team's expected QB. Everything a
# model may use before the game comes only from weeks < week.
#
#   2020-2025  analytical_db + nflreadr (team per week, opponent, real starter QB):
#              the historic tables have no opponent or weekly team.
#   2026       web/data/history/player_weeks.parquet + espn_db (ESPN abbreviations).
#
# Run from the project root:
#   source("R/snippets/analysis_matchup_panel.R")
# Leaves `panel` and the shared helpers in the session. The panel is cached in
# data/temp/analysis_matchup_panel.rds; delete it to rebuild (needs network).

library(tidyverse)
library(dm)

options(nflreadr.verbose = FALSE)

.hist_seasons <- 2020:2025
.cur_season   <- 2026L
.panel_file   <- "./data/temp/analysis_matchup_panel.rds"
.nflcom_rank  <- "../DudesFantasyFootball/data/rankAgainstPosition_week%d.rds"

# ESPN / ffanalytics abbreviation -> nflverse abbreviation
.nflverse_team <- function(x) {
  recode(x, LAR = "LA", WSH = "WAS", JAC = "JAX", LVR = "LV", GBP = "GB", KCC = "KC",
         NEP = "NE", NOS = "NO", SFO = "SF", TBB = "TB")
}

# --- Against Rank ---------------------------------------------------------------

# allowed : tibble(season, week, def, pos, allowed), points one defense gave to one
#           position in one game. Returns one row per season, week, def, pos with
#           the season-to-date average over weeks < week only (ESPN "OPRK": rank 1
#           = fewest points allowed, toughest matchup; 32 = easiest).
against_rank <- function(allowed) {
  allowed |>
    distinct(season, week) |>
    filter(week > 1L) |>
    pmap_dfr(function(season, week) {
      allowed |>
        filter(season == !!season, week < !!week) |>
        summarise(opp_avg = mean(allowed), opp_games = n(), .by = c(def, pos)) |>
        mutate(season = season, week = week,
               opp_rank = rank(opp_avg, ties.method = "min"),
               opp_z    = (opp_avg - mean(opp_avg)) / sd(opp_avg),
               .by = pos)
    })
}

# --- expected QB ----------------------------------------------------------------

# proj     : every projected player of a season-week, whether he played or not
#            (a QB ruled out at the last minute has a projection but no points, so
#            picking from players with points would leak the outcome).
#            Columns: season, week, ffa_id, pos, projection, team, gsis_id, actual_points.
# starters : tibble(season, week, team, starter_gsis), the QB who really started.
# Returns one row per season, week, team.
expected_qbs <- function(proj, starters) {
  qbs <- proj |>
    filter(pos == "QB", !is.na(team)) |>
    slice_max(projection, n = 1, with_ties = FALSE, by = c(season, week, team)) |>
    transmute(season, week, team, qb_ffa_id = ffa_id, qb_gsis = gsis_id,
              qb_proj = projection, qb_actual = actual_points) |>
    mutate(qb_rank_week = rank(-qb_proj, ties.method = "min"), .by = c(season, week))

  played <- proj |>
    filter(pos == "QB", !is.na(actual_points)) |>
    select(season, week, ffa_id, actual_points)
  qb_ppg <- qbs |>
    select(season, week, qb_ffa_id) |>
    left_join(played, by = c("season", "qb_ffa_id" = "ffa_id"),
              suffix = c("", ".past"), relationship = "many-to-many") |>
    filter(week.past < week) |>
    summarise(qb_ppg_std = mean(actual_points), .by = c(season, week, qb_ffa_id))

  # the team's usual starter: most games started in weeks < week
  usual <- qbs |>
    select(season, week, team) |>
    left_join(starters, by = c("season", "team"),
              suffix = c("", ".past"), relationship = "many-to-many") |>
    filter(week.past < week, !is.na(starter_gsis)) |>
    count(season, week, team, starter_gsis) |>
    slice_max(n, n = 1, with_ties = FALSE, by = c(season, week, team)) |>
    select(season, week, team, usual_gsis = starter_gsis)

  qbs |>
    left_join(qb_ppg, by = c("season", "week", "qb_ffa_id")) |>
    left_join(usual, by = c("season", "week", "team")) |>
    left_join(starters, by = c("season", "week", "team")) |>
    mutate(qb_is_backup  = starter_gsis != usual_gsis,   # known by kickoff
           qb_is_starter = qb_gsis == starter_gsis,
           qb_residual   = qb_actual - qb_proj) |>
    select(-usual_gsis, -starter_gsis, -qb_gsis)
}

# role inside the team, by projection: WR1, WR2, WR3+, RB1, RB2+, TE1, TE2+, K1
team_roles <- function(proj) {
  proj |>
    filter(pos %in% c("WR", "RB", "TE", "K"), !is.na(team)) |>
    mutate(depth = rank(-projection, ties.method = "first"),
           .by = c(season, week, team, pos)) |>
    transmute(season, week, ffa_id, pos,
              role = case_when(pos == "WR" & depth >= 3 ~ "WR3+",
                               pos == "RB" & depth >= 2 ~ "RB2+",
                               pos == "TE" & depth >= 2 ~ "TE2+",
                               pos == "K"               ~ "K1",
                               TRUE ~ paste0(pos, depth)))
}

# --- shared inputs --------------------------------------------------------------

load_games <- function() {
  sched <- nflreadr::load_schedules(c(.hist_seasons, .cur_season)) |>
    filter(game_type == "REG")
  bind_rows(
    sched |> transmute(season, week, team = home_team, opp = away_team, starter_gsis = home_qb_id),
    sched |> transmute(season, week, team = away_team, opp = home_team, starter_gsis = away_qb_id)
  ) |>
    mutate(season = as.integer(season), week = as.integer(week))
}

load_ff_ids <- function() {
  nflreadr::load_ff_playerids() |>
    transmute(ffa_id = suppressWarnings(as.integer(mfl_id)), gsis_id) |>
    filter(!is.na(ffa_id), !is.na(gsis_id)) |>
    distinct(ffa_id, .keep_all = TRUE)
}

# --- 2020-2025 ------------------------------------------------------------------

build_hist_panel <- function(a, ffa_players, ff_ids, games) {
  rosters <- nflreadr::load_rosters_weekly(.hist_seasons) |>
    filter(game_type == "REG", !is.na(gsis_id)) |>
    transmute(season = as.integer(season), week = as.integer(week), gsis_id, team,
              ros_pos = if_else(position == "FB", "RB", position)) |>
    distinct(season, week, gsis_id, .keep_all = TRUE)

  dst_team <- ffa_players |>
    filter(pos == "DST") |>
    transmute(ffa_id = as.integer(id), dst_team = .nflverse_team(team)) |>
    distinct(ffa_id, .keep_all = TRUE)

  # projections keep the players with no realized points (expected QB, roles)
  actual <- a$consensus_error_history |>
    transmute(season, week, ffa_id = as.integer(ffa_id), pos, actual_points)
  proj <- a$consensus_projections |>
    transmute(season, week, ffa_id = as.integer(ffa_id), pos, projection) |>
    left_join(ff_ids, by = "ffa_id") |>
    left_join(rosters |> select(-ros_pos), by = c("season", "week", "gsis_id")) |>
    left_join(dst_team, by = "ffa_id") |>
    mutate(team = coalesce(team, if_else(pos == "DST", dst_team, NA_character_))) |>
    select(-dst_team) |>
    left_join(actual, by = c("season", "week", "ffa_id", "pos"))

  # points allowed use every player with points, projected or not
  id_map <- a$player_ids |>
    transmute(nfl_id = as.integer(nfl_id), ffa_id = as.integer(ffa_id)) |>
    filter(!is.na(nfl_id), !is.na(ffa_id)) |>
    distinct(nfl_id, .keep_all = TRUE)
  scored <- a$nfl_player_points |>
    filter(season %in% .hist_seasons, week > 0L) |>
    transmute(season = as.integer(season), week = as.integer(week),
              nfl_id = as.integer(nfl_id), points) |>
    inner_join(id_map, by = "nfl_id") |>
    left_join(ff_ids, by = "ffa_id") |>
    left_join(rosters, by = c("season", "week", "gsis_id")) |>
    left_join(dst_team, by = "ffa_id") |>
    mutate(pos  = if_else(!is.na(dst_team), "DST", ros_pos),
           team = coalesce(team, dst_team)) |>
    filter(pos %in% c("QB", "RB", "WR", "TE", "K", "DST"))
  allowed <- scored |>
    inner_join(games |> select(season, week, team, def = opp), by = c("season", "week", "team")) |>
    summarise(allowed = sum(points), .by = c(season, week, def, pos))

  list(proj = proj, allowed = allowed, games = games |> filter(season %in% .hist_seasons),
       base = a$consensus_error_history |>
         transmute(season, week, ffa_id = as.integer(ffa_id), pos, coverage_class,
                   n_sources, projection, actual_points, residual))
}

# --- 2026 -----------------------------------------------------------------------

build_cur_panel <- function(espn, dec, ff_ids, games) {
  pw <- nanoparquet::read_parquet("./web/data/history/player_weeks.parquet") |>
    as_tibble() |>
    transmute(season = as.integer(season), week = as.integer(week),
              ffa_id = as.integer(ffa_id), espn_id = as.integer(espn_id),
              pos = position, run_id, projection, actual_points) |>
    left_join(dec$player_forecasts |>
                transmute(run_id, ffa_id = as.integer(ffa_id), pos, coverage_class, n_sources),
              by = c("run_id", "ffa_id", "pos")) |>
    filter(n_sources > 0L)                     # drops the forecast-0 rows of 3c

  newest <- espn$espn_players_points |>
    filter(season == .cur_season, week > 0L) |>
    collect()
  team_week <- newest |>
    slice_max(timestamp, n = 1, with_ties = FALSE, by = c(week, player_id)) |>
    transmute(week = as.integer(week), espn_id = as.integer(player_id), team = pro_team)
  scored <- newest |>
    filter(stat_source_id == 0L, stat_split_type_id == 1L) |>
    slice_max(timestamp, n = 1, with_ties = FALSE, by = c(week, player_id)) |>
    transmute(season = as.integer(season), week = as.integer(week), team = pro_team,
              pos = if_else(position == "D/ST", "DST", position), points = fantasy_points)

  g <- espn$espn_pro_games |> filter(season == .cur_season)
  sched <- bind_rows(
    g |> transmute(season = as.integer(season), week = as.integer(week),
                   team = home_pro_team, opp = away_pro_team),
    g |> transmute(season = as.integer(season), week = as.integer(week),
                   team = away_pro_team, opp = home_pro_team)
  )
  allowed <- scored |>
    inner_join(sched |> rename(def = opp), by = c("season", "week", "team")) |>
    summarise(allowed = sum(points, na.rm = TRUE), .by = c(season, week, def, pos))

  proj <- pw |>
    left_join(team_week, by = c("week", "espn_id")) |>
    left_join(ff_ids, by = "ffa_id") |>
    select(season, week, ffa_id, pos, projection, team, gsis_id, actual_points)

  starters <- games |>
    filter(season == .cur_season) |>
    transmute(season, week, nv = team, starter_gsis) |>
    inner_join(sched |> distinct(team) |> mutate(nv = .nflverse_team(team)), by = "nv") |>
    select(season, week, team, starter_gsis)

  list(proj = proj, allowed = allowed, starters = starters, sched = sched,
       base = pw |>
         filter(!is.na(actual_points)) |>
         transmute(season, week, ffa_id, pos, coverage_class, n_sources, projection,
                   actual_points, residual = actual_points - projection))
}

# ESPN OPRK as it stood before the week's first kickoff. Snapshots taken after it
# (W1 "final" was captured on 2026-10-21) would leak the games they rate.
espn_pregame_rank <- function(espn) {
  first_kick <- espn$espn_pro_games |>
    filter(season == .cur_season) |>
    summarise(kick = min(game_date), .by = week) |>
    transmute(week = as.integer(week), kick)
  pv <- espn$espn_pos_vs_opponent |> filter(season == .cur_season) |> collect()

  first_kick |>
    pmap_dfr(function(week, kick) {
      before <- pv |> filter(timestamp < kick)
      if (nrow(before) == 0L) return(NULL)
      before |>
        filter(timestamp == max(timestamp)) |>
        transmute(season = .cur_season, week = week, def = pro_team,
                  pos = if_else(position == "D/ST", "DST", position),
                  espn_rank = as.integer(rank), espn_avg = as.double(average))
    })
}

# NFL.com rankAgainstPosition captured week by week in 2025, one row per player.
# File "week k" was captured on the Tuesday after week k's games and rates the
# player's NEXT opponent: against the reconstructed rank Spearman is 0.98 at +1
# week and ~0 at the file's own week.
nflcom_rank <- function() {
  files <- sprintf(.nflcom_rank, 1:18)
  files <- files[file.exists(files)]
  if (length(files) == 0L) return(NULL)
  map_dfr(files, readRDS) |>
    transmute(season = 2025L, week = as.integer(week) + 1L, nfl_id = as.integer(playerId),
              nflcom_rank = as.integer(rankAgainstPosition)) |>
    distinct(season, week, nfl_id, .keep_all = TRUE)
}

# --- panel ----------------------------------------------------------------------

assemble <- function(part, sched, starters) {
  ranks <- against_rank(part$allowed)
  qbs   <- expected_qbs(part$proj, starters)
  roles <- team_roles(part$proj)
  teams <- part$proj |> distinct(season, week, ffa_id, pos, .keep_all = TRUE) |>
    select(season, week, ffa_id, pos, team)

  part$base |>
    left_join(teams, by = c("season", "week", "ffa_id", "pos")) |>
    left_join(sched |> select(season, week, team, opp), by = c("season", "week", "team")) |>
    left_join(ranks, by = c("season", "week", "opp" = "def", "pos")) |>
    left_join(qbs, by = c("season", "week", "team")) |>
    left_join(roles, by = c("season", "week", "ffa_id", "pos"))
}

build_matchup_panel <- function() {
  a    <- readRDS("./data/analytical_db.rds")
  espn <- readRDS("./data/espn_db.rds")
  dec  <- readRDS("./data/decision_db.rds")
  ffa_players <- readRDS("./data/ffa_db.rds")$ffa_players

  ff_ids <- load_ff_ids()
  games  <- load_games()

  hist <- build_hist_panel(a, ffa_players, ff_ids, games)
  cur  <- build_cur_panel(espn, dec, ff_ids, games)

  panel <- bind_rows(
    assemble(hist, hist$games, hist$games |> select(season, week, team, starter_gsis)),
    assemble(cur, cur$sched, cur$starters)
  ) |>
    left_join(espn_pregame_rank(espn), by = c("season", "week", "opp" = "def", "pos")) |>
    mutate(team_game = paste(season, week, team))

  nflcom <- nflcom_rank()
  if (!is.null(nflcom)) {
    xref <- a$consensus_error_history |>
      transmute(nfl_id = as.integer(nfl_id), season, week, ffa_id = as.integer(ffa_id), pos)
    panel <- panel |>
      left_join(xref |> inner_join(nflcom, by = c("season", "week", "nfl_id")) |> select(-nfl_id),
                by = c("season", "week", "ffa_id", "pos"))
  }

  panel
}

# --- checks ---------------------------------------------------------------------

check_panel <- function(panel) {
  # the rank of a week sees only earlier weeks
  toy <- tibble(season = 1L, week = rep(1:3, each = 2), def = rep(c("A", "B"), 3),
                pos = "WR", allowed = c(10, 20, 100, 0, 5, 5))
  r <- against_rank(toy) |> filter(def == "A")
  stopifnot(r$opp_avg == c(10, 55), r$opp_rank == c(1, 2), r$opp_games == 1:2)

  hist <- panel |> filter(season <= 2025L)
  link <- function(d, x) mean(!is.na(d[[x]]))
  skill <- hist |> filter(pos %in% c("WR", "RB", "TE", "K"))

  stopifnot(
    !anyDuplicated(select(panel, season, week, ffa_id, pos)),
    link(filter(hist, pos != "DST"), "team") >= 0.99,
    link(hist, "opp") >= 0.99,
    link(skill, "qb_proj") >= 0.99,
    all(between(panel$opp_rank[!is.na(panel$opp_rank)], 1, 32)),
    all(panel$opp_games[!is.na(panel$opp_games)] < panel$week[!is.na(panel$opp_games)])
  )
  invisible(panel)
}

# --- shared analysis helpers ----------------------------------------------------

proj_bin <- function(x) cut(x, c(-Inf, 3, 6, 10, 15, 20, Inf))

# team_game blocks: players of one team in one game share the same opponent, QB
# and game script, so they are not independent observations.

# Block bootstrap of one lm coefficient.
boot_slope <- function(d, formula, term, B = 1000L) {
  d <- drop_na(d, all_of(all.vars(formula)))
  # a control with one level in this subset carries no information
  rhs <- labels(terms(formula))
  rhs <- rhs[map_lgl(rhs, \(t) n_distinct(eval(str2lang(t), d)) > 1L)]
  y <- d[[all.vars(formula)[1]]]
  X <- model.matrix(reformulate(rhs), d)
  j <- match(term, colnames(X))
  est    <- lm.fit(X, y)$coefficients[[j]]
  blocks <- unname(split(seq_len(nrow(d)), d$team_game))
  bs <- replicate(B, {
    rows <- unlist(blocks[sample.int(length(blocks), replace = TRUE)], use.names = FALSE)
    lm.fit(X[rows, , drop = FALSE], y[rows])$coefficients[[j]]
  })
  tibble(term = term, est = est, se = sd(bs, na.rm = TRUE),
         lo = quantile(bs, .025, names = FALSE, na.rm = TRUE),
         hi = quantile(bs, .975, names = FALSE, na.rm = TRUE),
         p = 2 * pnorm(-abs(est / sd(bs, na.rm = TRUE))),
         n = nrow(d), blocks = length(blocks))
}

slope_by_pos <- function(data, f, term, positions = c("QB", "RB", "WR", "TE", "K", "DST")) {
  map_dfr(intersect(positions, unique(data$pos)),
          \(x) boot_slope(filter(data, pos == x), f, term) |> mutate(pos = x, .before = 1))
}

# Permutation placebo: x shuffled between teams inside each week, each team's rows
# kept together, slope refit B times. A single shuffle can land anywhere.
perm_placebo <- function(data, x, positions, B = 300L) {
  map_dfr(intersect(positions, unique(data$pos)), function(.p) {
    g  <- data |> filter(pos == .p, !is.na(.data[[x]]))
    X0 <- model.matrix(~ bin + factor(season), g)
    slope <- function(v) lm.fit(cbind(v, X0), g$residual)$coefficients[[1]]
    key <- g |> distinct(team_game, season, week, value = .data[[x]])
    row <- match(g$team_game, key$team_game)
    real <- slope(g[[x]])
    perm <- replicate(B, {
      shuffled <- key |> mutate(value = sample(value), .by = c(season, week))
      slope(shuffled$value[row])
    })
    tibble(pos = .p, real = real, perm_mean = mean(perm), perm_sd = sd(perm),
           perm_lo = quantile(perm, .025, names = FALSE),
           perm_hi = quantile(perm, .975, names = FALSE),
           p_perm = mean(abs(perm) >= abs(real)))
  })
}

# Block bootstrap of sum(num) / sum(den): a mean when den = 1.
boot_ratio <- function(num, den, block, B = 2000L) {
  sn <- rowsum(num, block)[, 1]
  sd_ <- rowsum(den, block)[, 1]
  bs <- replicate(B, {
    i <- sample.int(length(sn), replace = TRUE)
    sum(sn[i]) / sum(sd_[i])
  })
  tibble(est = sum(sn) / sum(sd_),
         lo = quantile(bs, .025, names = FALSE), hi = quantile(bs, .975, names = FALSE))
}

# Expanding window: the slope of `x` comes from seasons < s and is scored on s.
# Candidate = projection + beta * x, one beta per position.
oos_rows <- function(d, x, test_seasons = c(2022:2025, 2026L)) {
  map_dfr(test_seasons, function(s) {
    map_dfr(unique(d$pos), function(p) {
      train <- d |> filter(season < s, pos == p, !is.na(.data[[x]]))
      test  <- d |> filter(season == s, pos == p, !is.na(.data[[x]]))
      if (nrow(test) == 0L || nrow(train) < 30L) return(NULL)
      f <- reformulate(c(x, "bin", if (n_distinct(train$season) > 1L) "factor(season)"),
                       "residual")
      beta <- coef(lm(f, train))[[x]]
      test |> mutate(beta = beta, shift = beta * .data[[x]])
    })
  })
}

# Adoption rule fixed in the plan, per position: dMAE CI below 0 in 2022-2025,
# same sign in >= 3 of 4 seasons, 2026 not worse, gain >= 0.05 pt per player.
oos_verdict <- function(rows, by = "pos") {
  rows |>
    mutate(d_abs = abs(actual_points - projection - shift) - abs(actual_points - projection),
           d_sq  = (actual_points - projection - shift)^2 - (actual_points - projection)^2) |>
    group_by(across(all_of(by))) |>
    group_modify(function(g, ...) {
      h <- g |> filter(season <= 2025L)
      b <- boot_ratio(h$d_abs, rep(1, nrow(h)), h$team_game)
      by_season <- h |> summarise(m = mean(d_abs), .by = season)
      cur <- g |> filter(season == 2026L)
      cur_d <- if (nrow(cur) > 0L) mean(cur$d_abs) else NA_real_
      tibble(n = nrow(h), beta_last = last(g$beta), mae_base = mean(abs(h$residual)),
             d_mae = b$est, lo = b$lo, hi = b$hi,
             rmse_base = sqrt(mean(h$residual^2)),
             d_rmse = sqrt(mean(h$residual^2 + h$d_sq)) - sqrt(mean(h$residual^2)),
             seasons_better = sum(by_season$m < 0), n_seasons = nrow(by_season),
             n_2026 = nrow(cur), d_mae_2026 = cur_d,
             adopt = b$hi < 0 & sum(by_season$m < 0) >= 3L &
               coalesce(cur_d <= 0, FALSE) & b$est <= -0.05)
    }) |>
    ungroup()
}

# Production predictive distribution of one player as a plain vector: the centred
# residual pool around the projection, floored (simulate_players()). Sampling
# 10k draws from it only adds noise, so scores use the pool itself.
pool_center <- function(train) {
  list(history = train |> select(pos, projection, coverage_class, residual),
       floor   = tapply(train$projection + train$residual, train$pos, min))
}
dist_of <- function(pos, projection, coverage_class, pc, shift = 0) {
  pool <- get_residual_pool(pos, projection, coverage_class, pc$history)
  pmax(projection + shift + as.numeric(pool) - mean(pool), min(pc$floor[[pos]], projection))
}

# dist_of() has to be the same distribution simulate_players() samples
check_baseline <- function(n = 150L) {
  train <- panel |> filter(season <= 2025L, !is.na(residual), !is.na(projection))
  pc <- pool_center(train)
  s  <- panel |> filter(season == 2026L) |> slice_sample(n = n)
  draws <- simulate_players(select(s, pos, projection, coverage_class), train, n_sim = 20000L)$draws
  gap <- map2_dfr(draws, seq_len(n), function(v, i) {
    p <- dist_of(s$pos[i], s$projection[i], s$coverage_class[i], pc)
    tibble(mean = abs(mean(v) - mean(p)),
           q = max(abs(quantile(v, c(.1, .5, .9)) - quantile(p, c(.1, .5, .9)))))
  })
  # single quantiles jump between far-apart values of a discrete pool, so a rare
  # player can sit ~1 pt off; the typical one cannot
  stopifnot(max(gap$mean) < 0.2, median(gap$q) < 0.1)
  invisible(gap)
}

# Pinball p10/p50/p90, CRPS and interval hits of a sample `v` against outcome `y`.
score_dist <- function(v, y) {
  q <- quantile(v, c(.1, .25, .5, .75, .9), names = FALSE)
  tau <- c(.1, .5, .9)
  qq <- q[c(1, 3, 5)]
  v <- sort(v)
  n <- length(v)
  tibble(pinball = mean(pmax(tau * (y - qq), (tau - 1) * (y - qq))),
         crps = mean(abs(v - y)) - sum((2 * seq_len(n) - n - 1) * v) / n^2,
         in80 = y >= q[1] & y <= q[5],
         in50 = y >= q[2] & y <= q[4])
}

# --- report figures -------------------------------------------------------------

.fig_dir <- "./docs/analysis_against_rank_qb_fig"
.col_a <- "#2a78d6"
.col_b <- "#eb6834"
num_br <- scales::label_number(decimal.mark = ",", accuracy = 0.1)

theme_report <- function() {
  theme_minimal(base_size = 12) +
    theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
          text = element_text(colour = "#0b0b0b"),
          axis.text = element_text(colour = "#52514e"),
          axis.title = element_text(colour = "#52514e"),
          panel.grid.minor = element_blank(),
          panel.grid.major = element_line(colour = "#e8e7e3", linewidth = 0.3),
          strip.text = element_text(face = "bold", hjust = 0),
          legend.position = "top", legend.justification = "left",
          legend.title = element_blank(),
          plot.margin = margin(6, 18, 6, 6))
}

save_fig <- function(plot, name, width = 8, height = 5) {
  dir.create(.fig_dir, showWarnings = FALSE)
  ggsave(file.path(.fig_dir, name), plot, width = width, height = height, dpi = 150,
         bg = "#fcfcfb")
}

if (!exists("get_residual_pool")) source("./R/decision/player_simulation.R")

panel <- if (file.exists(.panel_file)) {
  readRDS(.panel_file)
} else {
  p <- check_panel(build_matchup_panel())
  saveRDS(p, .panel_file)
  message("panel: ", nrow(p), " rows -> ", .panel_file)
  p
}
panel <- panel |> mutate(bin = proj_bin(projection))
