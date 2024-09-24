library(tidyverse)
library(dm)
library(glue)
library(ffanalytics)
library(lubridate)

# script wrapping ffanalytics package

# wrapper to control which POS and SOURCES to scrap
.scrapeData <- function(.week, .season) {
  # # faz o scraping de projeção dos sites
  
  # defaults 
  sources <- c("CBS", "ESPN", "FantasyPros", "FantasySharks", "FFToday", "FleaFlicker",
               "NumberFire", "FantasyFootballNerd", "NFL", "RTSports", "Walterfootball")
  
  # CBS is projecting the season
  # sources <- sources[-1]
  
  scrap <- scrape_data(
    src = sources,
    pos = c("QB", "RB", "WR", "TE", "K", "DST"),
    season = .season,
    week = .week
  )
  
  return(scrap)
}


# public function to call the scrap and to wrap it in a DM objetc
scrapeWebData <- function(.tag, .week, .season) {
  scrape_raw <- .scrapeData(.week, .season)

  ffa_scrape <- tibble(
    timestamp = now(),
    tag = as.character(.tag),
    week = as.integer(.week),
    season = as.integer(.season),
    scrape = list(scrape_raw)
  )  
  
  scrape_db <- dm(ffa_scrape) |> 
    dm_add_pk(ffa_scrape, c(timestamp, tag, week, season), check=T) 
  
  return(scrape_db)
}




