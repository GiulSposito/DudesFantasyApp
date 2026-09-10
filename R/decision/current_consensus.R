# Decision engine - Phase 2: current consensus.
#
# Collapse the current FFA source-projection snapshot to one consensus row per
# player. This is the live-week analogue of analytical_db$consensus_projections;
# the summarise() block is copied from R/analysis/build_historic_datasets.R:169-217
# so the historical residual pool and the current projection share a definition.
#
# source_sd / source_mad measure disagreement BETWEEN sources - never the spread of
# fantasy outcomes (spec 46). They ride onto player_forecasts as descriptors only.

library(tidyverse)

# ffa_snapshot: the list returned by select_ffa_snapshot().
# Returns a tibble, one row per season x week x tag x ffa_id x pos (spec 7).
build_current_consensus <- function(ffa_snapshot) {
  ffa_snapshot$proj_source |>
    summarise(
      n_sources = n_distinct(data_src),
      sources   = paste(sort(unique(data_src)), collapse = ", "),

      projection = mean(proj_points, na.rm = TRUE),

      source_median = median(proj_points, na.rm = TRUE),
      source_sd  = if (n_distinct(data_src) >= 2) sd(proj_points,  na.rm = TRUE) else NA_real_,
      source_mad = if (n_distinct(data_src) >= 2) mad(proj_points, na.rm = TRUE) else NA_real_,
      source_min = min(proj_points, na.rm = TRUE),
      source_max = max(proj_points, na.rm = TRUE),

      .by = c(ffa_id, pos)
    ) |>
    # A player can be scraped under two positions in the same snapshot (e.g. one
    # source lists a FB as RB, another as TE). Downstream keys on ffa_id alone
    # (player_simulation, draws_by_ffa), so collapse to the dominant position:
    # most sources, then highest projection.
    # ponytail: naive tie-break, revisit if a real dual-eligible player regresses
    slice_max(order_by = tibble(n_sources, projection), n = 1, by = ffa_id,
              with_ties = FALSE) |>
    mutate(
      source_range = if_else(n_sources >= 2, source_max - source_min, NA_real_),
      coverage_class = case_when(
        n_sources == 1 ~ "single",
        n_sources <= 3 ~ "sparse",
        TRUE           ~ "ensemble"
      ),
      season = as.integer(ffa_snapshot$season),
      week   = as.integer(ffa_snapshot$week),
      tag    = ffa_snapshot$tag
    ) |>
    select(season, week, tag, ffa_id, pos, n_sources, sources, projection,
           source_median, source_sd, source_mad, source_min, source_max,
           source_range, coverage_class)
}

# One consensus row per player (spec 36). Stops on violation.
check_one_consensus_per_player <- function(consensus) {
  dups <- consensus |> count(ffa_id) |> filter(n > 1)
  if (nrow(dups) > 0L) {
    stop(glue::glue("consensus has {nrow(dups)} duplicated ffa_id rows"),
         call. = FALSE)
  }
  invisible(TRUE)
}
