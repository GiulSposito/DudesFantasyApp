# Master weekly pipeline: import -> decision engine -> web bundle -> publish.
#
# One set of master parameters drives the whole journey:
#
#   importFfa()  + importEspn()      scrape + API, upsert data/{ffa,espn}_db.rds
#   run_decision_pipeline()          simulation + recommendations -> data/decision_db.rds
#   build_web_bundle()               Parquet + manifest -> web/data/
#   quarto publish gh-pages          render web/ and push web/_site/ to origin/gh-pages
#
# The legacy NFL Fantasy API pipeline (data_pipeline_nfl.R) is independent and is
# NOT run from here. Detail per stage: docs/PIPELINE_RUNBOOK.md.
#
# Run from the project root:  source("R/pipeline/data_pipeline.R")

source("./R/pipeline/data_pipeline_espn.R")   # defines importEspn() + helpers
source("./R/pipeline/data_pipeline_ffa.R")    # defines importFfa() + helpers
source("./R/decision/decision_pipeline.R")    # defines run_decision_pipeline()
source("./R/web/build_web_bundle.R")          # defines build_web_bundle()

# MASTER PARAMETERS ####
config      <- yaml::read_yaml("./config/config.yml")
.season     <- 2026L
.week       <- 1L            # current week - snapshot pulled from each source
.tag        <- "preTNF"      # ver docs/PIPELINE_RUNBOOK.md "Vocabulário de tag"
.timestamp  <- lubridate::now()
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")
.publish    <- TRUE          # FALSE = build the web bundle but skip the gh-pages push

# 1. imports ####
ffa_db  <- importFfa(.season, .week, .tag, .scoreRules)
espn_db <- importEspn(config, .season, .week, .tag, .timestamp)

# 2. decision engine ####
res <- run_decision_pipeline(.season, .week, .tag)

# 3. web bundle ####
build_web_bundle(result = res, privacy = "public")

# 4. publish cockpit ####
if (isTRUE(.publish)) {
  message("quarto publish gh-pages web ...")
  code <- system2("quarto", c("publish", "gh-pages", "web", "--no-prompt", "--no-browser"))
  if (code != 0L) stop("quarto publish failed (exit ", code, ")", call. = FALSE)
}
