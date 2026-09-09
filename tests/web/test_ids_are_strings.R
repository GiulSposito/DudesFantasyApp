# tests/web/test_ids_are_strings.R - every identifier column reads back as
# character (contract section 5).

suppressMessages({library(nanoparquet)})

FIX <- "./tests/fixtures/web_bundle"
rels <- sub(paste0("^", FIX, "/"), "",
            list.files(FIX, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE))

is_id <- function(nm) grepl("(_id|_ids)$", nm) | nm %in% c("player_out", "player_in")

for (rel in rels) {
  d <- as.data.frame(read_parquet(file.path(FIX, rel)))
  id_cols <- names(d)[is_id(names(d))]
  for (cc in id_cols) {
    if (!is.character(d[[cc]])) {
      stop(rel, ".", cc, " is ", class(d[[cc]])[1], ", expected character")
    }
  }
}

# sanity: season / week must stay integer, not stringified
runs <- as.data.frame(read_parquet(file.path(FIX, "runs.parquet")))
stopifnot(is.integer(runs$season), is.integer(runs$week))

cat("PASS test_ids_are_strings.R\n")
