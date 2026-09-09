# Master data pipeline (ESPN + FFA)
#
# Loads the two function-only pipelines and runs the current week's imports with
# a single set of master parameters. The legacy NFL Fantasy API pipeline
# (data_pipeline_nfl.R) is independent and is NOT run from here.
#
# Run from the project root:  source("R/pipeline/data_pipeline.R")

source("./R/pipeline/data_pipeline_espn.R")   # defines importEspn() + helpers
source("./R/pipeline/data_pipeline_ffa.R")    # defines importFfa() + helpers

# MASTER PARAMETERS ####
config      <- yaml::read_yaml("./config/config.yml")
.season     <- 2026L
.week       <- 1L            # current week - snapshot pulled from each source
.tag        <- "preKickoff"  # "preview" | "final" | "season" | "preKickoff" (snapshot pré-jogos)
.timestamp  <- lubridate::now()
.scoreRules <- yaml::read_yaml("./config/score_settings.yml")

# imports ####
ffa_db  <- importFfa(.season, .week, .tag, .scoreRules)
espn_db <- importEspn(config, .season, .week, .tag, .timestamp)
