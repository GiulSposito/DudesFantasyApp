# Web bundle - Parquet writer (contract sections 4, 5, 34).
#
# write_mart() is the single choke point every mart passes through:
#   assert_no_list_cols -> stringify_ids -> coerce_types -> write_parquet
#
# The output directory is a build-time option so the build functions stay pure
# (no file I/O) and the orchestrator controls where the bundle lands.

library(nanoparquet)

if (!exists("stringify_ids")) source("./R/web/utils/schema.R")

.bundle_output_dir <- function() {
  d <- getOption("cockpit.output_dir")
  if (is.null(d)) stop("write_mart: options(cockpit.output_dir=) is not set", call. = FALSE)
  d
}

# df       : a tibble from a build_*() function.
# rel_path : path under the bundle root, e.g. "current/forecasts.parquet".
# Returns rel_path (for the manifest datasets map).
write_mart <- function(df, rel_path) {
  name <- tools::file_path_sans_ext(basename(rel_path))
  df <- df |>
    assert_no_list_cols(name) |>
    stringify_ids() |>
    coerce_types()

  out <- file.path(.bundle_output_dir(), rel_path)
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  nanoparquet::write_parquet(as.data.frame(df), out)
  rel_path
}
