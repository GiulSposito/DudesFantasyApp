# Web presentation layer - bundle validation gate (contract section 32).
#
# Reads the written bundle back from disk and stop()s on the first violation.
# Run automatically at the end of build_web_bundle() unless validate = FALSE.

library(nanoparquet)
library(jsonlite)

.PK_MAP <- list(
  "runs.parquet"                            = "run_id",
  "dimensions/teams.parquet"                = c("season", "team_id"),
  "dimensions/players.parquet"              = c("season", "player_id"),
  "dimensions/roster_slots.parquet"         = c("season", "lineup_slot_id"),
  "current/standings.parquet"               = c("run_id", "team_id"),
  "current/rosters.parquet"                 = c("run_id", "team_id", "player_id"),
  "current/forecasts.parquet"               = c("run_id", "ffa_id", "position"),
  "current/matchups.parquet"                = c("run_id", "matchup_id"),
  "current/lineup_evaluations.parquet"      = c("run_id", "team_id"),
  "current/lineup_recommendations.parquet"  = c("run_id", "team_id", "player_out_id"),
  "current/free_agents.parquet"             = c("run_id", "player_id"),
  "current/waiver_recommendations.parquet"  = c("run_id", "team_id", "drop_player_id", "add_player_id"),
  "current/trade_recommendations.parquet"   = c("run_id", "my_team_id", "other_team_id", "give_player_id", "receive_player_id"),
  "current/data_health.parquet"             = "run_id",
  "projections/source_projections.parquet"  = c("run_id", "ffa_id", "position", "data_src"),
  "projections/source_accuracy.parquet"     = c("season", "data_src", "position")
)

.stop <- function(...) stop("validate_web_bundle: ", ..., call. = FALSE)

validate_web_bundle <- function(output_dir = "web/data") {
  man_path <- file.path(output_dir, "manifest.json")
  if (!file.exists(man_path)) .stop("manifest.json missing")
  man <- jsonlite::read_json(man_path)

  # --- 32.1 manifest -------------------------------------------------------
  if (is.null(man$schema_version)) .stop("manifest schema_version missing")
  major <- sub("\\..*$", "", man$schema_version)
  if (major != "1") .stop("unsupported schema_version major: ", man$schema_version)
  if (is.null(man$current$run_id)) .stop("manifest current.run_id missing")
  run_id <- man$current$run_id

  if (length(man$datasets) == 0L) .stop("manifest datasets empty")
  rel_paths <- unlist(man$datasets, use.names = FALSE)
  for (p in rel_paths) {
    if (!file.exists(file.path(output_dir, p))) .stop("dataset file missing: ", p)
  }

  rd <- function(rel) as.data.frame(nanoparquet::read_parquet(file.path(output_dir, rel)))
  by_rel <- setNames(as.list(rel_paths), rel_paths)
  data <- lapply(by_rel, rd)

  # --- current.run_id present in runs ------------------------------------
  runs <- data[["runs.parquet"]]
  if (is.null(runs) || !"run_id" %in% names(runs)) .stop("runs.parquet has no run_id column")
  if (!run_id %in% runs$run_id) .stop("current.run_id not in runs.parquet: ", run_id)

  # --- 32.4 unique grains ----------------------------------------------
  for (rel in names(data)) {
    pk <- .PK_MAP[[rel]]
    if (is.null(pk)) next
    d <- data[[rel]]
    miss <- setdiff(pk, names(d))
    if (length(miss)) .stop(rel, ": PK column(s) missing: ", paste(miss, collapse = ", "))
    if (anyDuplicated(d[pk])) .stop(rel, ": duplicate PK rows on (", paste(pk, collapse = ", "), ")")
  }

  # --- 32.2 referential integrity ------------------------------------
  teams <- data[["dimensions/teams.parquet"]]
  players <- data[["dimensions/players.parquet"]]
  rosters <- data[["current/rosters.parquet"]]
  matchups <- data[["current/matchups.parquet"]]

  chk_in <- function(vals, universe, what) {
    bad <- setdiff(unique(stats::na.omit(vals)), unique(universe))
    if (length(bad)) .stop(what, ": ", length(bad), " value(s) not found (e.g. ", bad[1], ")")
  }
  if (!is.null(rosters)) {
    chk_in(rosters$team_id, teams$team_id, "rosters.team_id in teams")
    chk_in(rosters$player_id, players$player_id, "rosters.player_id in players")
  }
  if (!is.null(matchups)) {
    chk_in(matchups$home_team_id, teams$team_id, "matchups.home_team_id in teams")
    chk_in(matchups$away_team_id, teams$team_id, "matchups.away_team_id in teams")
  }

  # --- 32.3 run consistency (current/* marts + projections) --------------
  for (rel in names(data)) {
    if (!grepl("^(current|projections)/", rel)) next
    d <- data[[rel]]
    if (!"run_id" %in% names(d) || nrow(d) == 0L) next
    if (any(d$run_id != run_id)) .stop(rel, ": rows with foreign run_id")
  }

  # --- 32.5 probability checks ------------------------------------------
  for (rel in names(data)) {
    d <- data[[rel]]
    # deltas of probabilities are signed differences, not probabilities
    prob_cols <- names(d)[grepl("probability$|^prob_gt_", names(d)) &
                            !grepl("delta", names(d))]
    for (cc in prob_cols) {
      v <- d[[cc]]; v <- v[!is.na(v)]
      if (length(v) && (min(v) < -1e-9 || max(v) > 1 + 1e-9)) {
        .stop(rel, ".", cc, ": probability outside [0,1]")
      }
    }
  }
  if (!is.null(matchups) && nrow(matchups)) {
    s <- matchups$home_win_probability + matchups$away_win_probability + matchups$tie_probability
    if (any(abs(s - 1) > 1e-6)) .stop("matchups: home+away+tie win probability != 1")
  }

  # --- 32.6 forecast quantile monotonicity ---------------------------
  fc <- data[["current/forecasts.parquet"]]
  if (!is.null(fc) && nrow(fc)) {
    q <- c("p05", "p10", "p25", "p50", "p75", "p90", "p95")
    m <- as.matrix(fc[q])
    if (any(apply(m, 1, function(r) any(diff(r) < -1e-9, na.rm = TRUE)))) {
      .stop("forecasts: quantiles not monotone p05<=..<=p95")
    }
  }

  # --- 32.7 coverage class ------------------------------------------
  ok_cov <- c("single", "sparse", "ensemble")
  for (rel in names(data)) {
    d <- data[[rel]]
    if (!"coverage_class" %in% names(d)) next
    v <- unique(stats::na.omit(d$coverage_class))
    bad <- setdiff(v, ok_cov)
    if (length(bad)) .stop(rel, ": coverage_class not in {single,sparse,ensemble}: ", bad[1])
  }

  message("validate_web_bundle: OK (", length(data), " datasets)")
  invisible(TRUE)
}
