# Web bundle - schema helpers (contract sections 5, 34).
#
# Three pure transforms every mart passes through before it is written:
#   stringify_ids()  - every identifier column -> character (NA stays NA)
#   assert_no_list_cols() - stop() if any list-column survived
#   coerce_types()   - recognised count columns -> integer, measures -> double
#
# Deliberately conservative: coerce_types only touches columns it recognises by
# name, everything else is left as the build function produced it.

library(tidyverse)

# Columns that are identifiers even though they do not end in _id / _ids.
.ID_COLS_EXTRA <- c("player_out", "player_in")

# regex: <something>_id or <something>_ids at end of the column name
.ID_COL_RE <- "(_id|_ids)$"

# every identifier -> string. NA_integer_ -> NA_character_ automatically.
stringify_ids <- function(df) {
  df |>
    mutate(across(matches(.ID_COL_RE), as.character)) |>
    mutate(across(any_of(.ID_COLS_EXTRA), as.character))
}

assert_no_list_cols <- function(df, name = "<mart>") {
  bad <- names(df)[vapply(df, is.list, logical(1))]
  if (length(bad) > 0L) {
    stop(sprintf("assert_no_list_cols: %s has list-column(s): %s",
                 name, paste(bad, collapse = ", ")),
         call. = FALSE)
  }
  invisible(df)
}

# integer columns (exact names) - counts, ranks, seasons/weeks, W-L-T, txns
.INT_COLS <- c(
  "season", "week", "rank", "recommendation_rank",
  "current_projected_rank", "draft_day_projected_rank", "waiver_rank",
  "streak_length", "n_sim", "n_substitutions", "n_sources",
  "residual_pool_n", "residual_pool_level", "seed",
  "wins", "losses", "ties", "acquisitions", "drops", "trades",
  "slot_count", "count",
  "n_forecast_players", "n_rostered_players", "n_starters",
  "n_mapped_players", "n_mapped_starters", "n_unmapped_players",
  "n_ensemble", "n_sparse", "n_single"
)

# double columns: matched by name fragment (probability / quantile / measure)
.DBL_COL_RE <- paste(
  "prob", "probability", "expected$", "_expected$", "delta", "fairness",
  "trade_score", "bench_value", "win_pct", "projection", "projected_points",
  "sim_mean", "sim_sd", "source_sd", "source_mad", "historical_bias",
  "points_for", "points_against", "^points$", "points_adjusted",
  "^bias$", "^mae$", "^rmse$", "percent_owned", "percent_started",
  "^p05$", "^p10$", "^p25$", "^p50$", "^p75$", "^p90$", "^p95$",
  "^pct_", "^points$",
  sep = "|"
)

coerce_types <- function(df) {
  # lineup_slot_id / *_id stay identifiers (stringified later), never coerced here.
  df |>
    mutate(across(any_of(.INT_COLS) & where(is.numeric),
                  ~ as.integer(round(.x)))) |>
    mutate(across(matches(.DBL_COL_RE) & where(is.numeric), as.double))
}
