# tests/web/test_probabilities.R - probabilities in [0,1], matchup win probs
# sum to 1, forecast quantiles monotone (contract sections 32.5, 32.6).

suppressMessages({library(nanoparquet)})

FIX <- "./tests/fixtures/web_bundle"
rp  <- function(x) as.data.frame(read_parquet(file.path(FIX, x)))

rels <- sub(paste0("^", FIX, "/"), "",
            list.files(FIX, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE))

for (rel in rels) {
  d <- rp(rel)
  pc <- names(d)[grepl("probability$|^prob_gt_", names(d)) & !grepl("delta", names(d))]
  for (cc in pc) {
    v <- d[[cc]]; v <- v[!is.na(v)]
    if (length(v)) stopifnot(min(v) >= -1e-9, max(v) <= 1 + 1e-9)
  }
}

m <- rp("current/matchups.parquet")
s <- m$home_win_probability + m$away_win_probability + m$tie_probability
stopifnot(all(abs(s - 1) < 1e-6))

fc <- rp("current/forecasts.parquet")
q  <- as.matrix(fc[c("p05", "p10", "p25", "p50", "p75", "p90", "p95")])
stopifnot(all(apply(q, 1, function(r) all(diff(r) >= -1e-9))))

cat("PASS test_probabilities.R\n")
