# tests/decision/run_all.R - source() from the project root to run every check.

tests <- list.files("./tests/decision", pattern = "^test_.*\\.R$", full.names = TRUE)
for (t in tests) {
  cat("---", basename(t), "---\n")
  source(t)
}
cat("\nALL DECISION TESTS DONE (", length(tests), "files )\n")
