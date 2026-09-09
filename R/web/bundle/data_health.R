# Web bundle - current/data_health.parquet (contract section 28).
# 1 row = the current run. Pure diagnostic derived from the persisted marts.

library(tidyverse)

.KNOWN_BRIDGE <- c("override", "espn_id", "dst_offset", "name_pos")

build_data_health <- function(src, run) {
  cp <- src$decision_db$current_players |> filter(run_id == run$run_id)
  fc <- src$decision_db$player_forecasts |> filter(run_id == run$run_id)

  n_rostered <- nrow(cp)
  n_starters <- sum(cp$is_starter)
  n_mapped_players  <- sum(!is.na(cp$ffa_id))
  n_mapped_starters <- sum(cp$is_starter & !is.na(cp$ffa_id))
  n_unmapped_players   <- sum(is.na(cp$ffa_id))
  n_unmapped_starters  <- sum(cp$is_starter & is.na(cp$ffa_id))

  bm <- cp$bridge_method
  bm[is.na(bm)] <- "none"
  bridge_counts <- set_names(
    map_int(c(.KNOWN_BRIDGE, "none"), ~ sum(bm == .x)),
    paste0("n_bridge_", c(.KNOWN_BRIDGE, "none"))
  )

  n_forecast <- nrow(fc)
  n_ensemble <- sum(fc$coverage_class == "ensemble")
  n_sparse   <- sum(fc$coverage_class == "sparse")
  n_single   <- sum(fc$coverage_class == "single")
  pct_ensemble <- if (n_forecast) n_ensemble / n_forecast else NA_real_
  pct_sparse   <- if (n_forecast) n_sparse   / n_forecast else NA_real_
  pct_single   <- if (n_forecast) n_single   / n_forecast else NA_real_

  status <- if (n_unmapped_starters > 0L) {
    "error"
  } else if (!is.na(pct_ensemble) && pct_ensemble < 0.4) {
    "warning"
  } else {
    "healthy"
  }

  .iso <- function(x) format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  tibble(
    run_id = run$run_id,
    generated_at = .iso(Sys.time()),
    ffa_timestamp = .iso(run$ffa_timestamp),
    espn_timestamp = .iso(run$espn_timestamp),
    decision_timestamp = .iso(run$created_at),
    n_forecast_players = n_forecast,
    n_rostered_players = n_rostered,
    n_starters = n_starters,
    n_mapped_players = n_mapped_players,
    n_mapped_starters = n_mapped_starters,
    n_unmapped_players = n_unmapped_players,
    n_unmapped_starters = n_unmapped_starters,
    n_ensemble = n_ensemble, n_sparse = n_sparse, n_single = n_single,
    pct_ensemble = pct_ensemble, pct_sparse = pct_sparse, pct_single = pct_single,
    model_version = run$model_version,
    n_sim = run$n_sim,
    status = status
  ) |>
    bind_cols(as_tibble_row(bridge_counts))
}
