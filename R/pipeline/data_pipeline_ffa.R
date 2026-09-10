# FFA (ffanalytics) projections pipeline - function library
#
# Sourcing this file only DEFINES functions; it runs nothing. The orchestrator
# R/pipeline/data_pipeline.R sources it and calls importFfa() with the week's
# master parameters. Scrapes the multi-site projections via ffanalytics and
# upserts `ffa_db` into ./data/ffa_db.rds. The NFL Fantasy API pipeline lives in
# data_pipeline_nfl.R.

library(tidyverse)
library(dm)
library(glue)
library(ffanalytics)
library(lubridate)

source("./R/api/ffa_projection.R")

# ---- helpers ---------------------------------------------------------------

# add any column present on one side but not the other (typed NA) so two dm
# snapshots taken under different code versions still upsert cleanly (schema
# drift is routine here - a new field lands every season or two).
.reconcile_dm_cols <- function(a, b) {
  fill <- function(dm_, tbl, col, proto) {
    na1 <- proto[NA_integer_]
    dm_ |> dm_zoom_to(!!tbl) |> mutate(!!col := na1) |> dm_update_zoomed()
  }
  for (t in intersect(names(a), names(b))) {
    ca <- colnames(a[[t]]); cb <- colnames(b[[t]])
    for (col in setdiff(cb, ca)) a <- fill(a, t, col, b[[t]][[col]])
    for (col in setdiff(ca, cb)) b <- fill(b, t, col, a[[t]][[col]])
  }
  list(a = a, b = b)
}

# update existing rows by PK, insert new ones, persist to an on-disk .rds
updateDB <- function(db, db_file){
  if(file.exists(db_file)){
    rc <- .reconcile_dm_cols(readRDS(db_file), db)
    db <- dm_rows_upsert(rc$a, rc$b, in_place = F)
  }
  saveRDS(db, db_file)
  return(db)
}

# draw a dm ERD to a PNG file. Works around DiagrammeR >= 1.0.11, whose htmlwidget
# renderer fails in the RStudio Viewer with "Layout was not done"; export_svg()
# uses the DOT->SVG path instead. Needs DiagrammeRsvg + rsvg.
dm_draw_png <- function(dm, ..., file, width = 2400) {
  svg <- DiagrammeRsvg::export_svg(dm::dm_draw(dm, ...))
  rsvg::rsvg_png(charToRaw(svg), file, width = width)
  file
}

# ---- getters -------------------------------------------------------------

getFFAScrapeData <- function(.season, .week, .tag) {
  # scrape the web
  ffa_scrape_db <- scrapeWebData(.season, .week, .tag)

  # cache the scrape
  temp_filename <-
    glue(
      "./data/temp/ffa_scrape_db_s{.season}w{.weeknumber}_{.tag}_{.timestamp}.rds",
      .weeknumber = formatC(.week, width = 2, flag = "0"),
      .timestamp = format(ffa_scrape_db$ffa_scrape[1,]$timestamp, "%Y%m%d%H%M%S")
    )

  # save scrape
  saveRDS(ffa_scrape_db, temp_filename)

  return(ffa_scrape_db)
}

# update projections
getFFAProjections <- function(.ffa_scrape_db, .season, .week, .tag, .scoreRules){

  # calculates the projection
  ffa_db <- calcProjections(.ffa_scrape_db, .scoreRules)

  # cache ffa_db
  temp_filename <-
    glue(
      "./data/temp/ffa_db_s{.season}w{.weeknumber}_{.tag}_{.timestamp}.rds",
      .weeknumber = formatC(.week, width = 2, flag = "0"),
      .timestamp = format(.ffa_scrape_db$ffa_scrape[1,]$timestamp, "%Y%m%d%H%M%S")
    )

  # save scrape
  saveRDS(ffa_db, temp_filename)

  # return value
  return(ffa_db)
}

# ---- orchestrator -------------------------------------------------------

# run the full FFA pipeline for one week: scrape -> projections -> upsert
importFfa <- function(.season, .week, .tag, .scoreRules) {
  
  cli::cli_alert_info(glue("Scrapping FFA data s{.season}-w{.week}:{.tag}..."))
  ffa_scrape_db <- getFFAScrapeData(.season, .week, .tag)
  cli::cli_alert_success(glue("FFA data scrapeted"))
  
  cli::cli_alert_info(glue("Calculating FFA Projections for s{.season}-w{.week}:{.tag}..."))
  ffa_db <- getFFAProjections(ffa_scrape_db, .season, .week, .tag, .scoreRules)
  cli::cli_alert_success(glue("FFA Projections calculated"))
  
  cli::cli_alert_info(glue("Updating FFA database..."))
  ffa_db <- updateDB(ffa_db, "./data/ffa_db.rds")
  print(dm_examine_constraints(ffa_db))
  cli::cli_alert_success(glue("FFA DB updated"))
  
  dm_draw_png(ffa_db, view_type = "all", column_types = TRUE, rankdir = "RL", file = "./export/ffa_db.png")
  ffa_db
  
}
