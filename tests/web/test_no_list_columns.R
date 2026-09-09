# tests/web/test_no_list_columns.R - no mart contains a list-column
# (contract section 34).

suppressMessages({library(nanoparquet)})

FIX <- "./tests/fixtures/web_bundle"
rels <- sub(paste0("^", FIX, "/"), "",
            list.files(FIX, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE))

for (rel in rels) {
  d <- as.data.frame(read_parquet(file.path(FIX, rel)))
  bad <- names(d)[vapply(d, is.list, logical(1))]
  if (length(bad)) stop(rel, " has list-column(s): ", paste(bad, collapse = ", "))
}

cat("PASS test_no_list_columns.R\n")
