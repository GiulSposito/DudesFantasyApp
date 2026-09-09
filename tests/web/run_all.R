# tests/web/run_all.R - source() from the project root to run every web check.

tests <- list.files("./tests/web", pattern = "^test_.*\\.R$", full.names = TRUE)
for (t in tests) {
  cat("---", basename(t), "---\n")
  source(t)
}
cat("\nALL WEB TESTS DONE (", length(tests), "files )\n")
