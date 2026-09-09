# Web bundle - manifest.json (contract section 9).
# Small bootstrap file. Written LAST, after every Parquet exists.

library(jsonlite)

.iso8601 <- function(x) {
  format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# run     : 1-row list from resolve_run()
# paths   : named list  dataset name -> relative parquet path
# privacy : "private" | "public"
write_manifest <- function(run, paths, privacy, output_dir) {
  manifest <- list(
    schema_version = "1.0.0",
    generated_at   = .iso8601(Sys.time()),
    current = list(
      run_id         = run$run_id,
      season         = as.integer(run$season),
      week           = as.integer(run$week),
      tag            = run$tag,
      model_version  = run$model_version,
      n_sim          = as.integer(run$n_sim),
      created_at     = .iso8601(run$created_at),
      ffa_timestamp  = .iso8601(run$ffa_timestamp),
      espn_timestamp = .iso8601(run$espn_timestamp)
    ),
    datasets = paths,
    privacy  = privacy
  )
  jsonlite::write_json(manifest, file.path(output_dir, "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  invisible(manifest)
}
