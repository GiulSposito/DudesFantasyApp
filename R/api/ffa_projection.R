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

# private function to calc individual data sources player projections
.projections_table_data_sources <- function(.webscrape, .scoring_rules) {
  
  # quais os sites neste scrape?
  site_sources <- unique(.webscrape$QB$data_src)
  
  # separa os scrapes por data source 
  source_scrapes <- site_sources %>% 
    map(function(.src, .scrp){
      
      resp <- .scrp  |>  
        map(~filter(.x, data_src==.src, !is.na(id)))  |>  
        set_names(names(.scrp))  |>  
        keep(~nrow(.x)>0)
      
      # atributos de controle da FFA
      attr(resp, "season") <- attr(.scrp, "season")
      attr(resp, "week") <-  attr(.scrp, "season")
      
      resp |> 
        return() 
      
    }, .scrp = .webscrape)
  
  # cria um tibble com o datasource e os scraps específicos
  tibble(
    data_src = site_sources,
    scrape = source_scrapes
  ) |> 
    # aplica o calculo da projeção para cada jogodor xdatasource
    mutate( proj_table = map(scrape, 
                             projections_table, 
                             scoring_rules = .scoring_rules, 
                             avg_type="average") ) |>  
    unnest(proj_table) |> 
    select(data_src, id, pos, points)  |> 
    distint() |> 
    return()
}



# public function to call the scrap and to wrap it in a DM objetc
scrapeWebData <- function(.tag, .week, .season) {
  scrape_raw <- .scrapeData(.week, .season)

  ffa_scrape <- tibble(
    season = as.integer(.season),
    week = as.integer(.week),
    tag = as.character(.tag),
    timestamp = now(),
    scrapeData = list(scrape_raw)
  )  
  
  scrape_db <- dm(ffa_scrape) |> 
    dm_add_pk(ffa_scrape, c(timestamp, tag, week, season), check=T) 
  
  return(scrape_db)
}

# rum all FFA calculations and build a DB version
calcProjections <- function(.ffa_scrape_db, .scoreRules){
  
  # FFA PLAYER IDS ####
  load("../ffanalytics/R/sysdata.rda")
  ffa_player_ids <- player_ids
  
  # FFA PROJECT TABLE ####
  ffa_raw_projection_table <- 
    projections_table(.ffa_scrape_db$ffa_scrape[1,]$scrapeData[[1]], .scoreRules) |> 
    add_ecr() |> 
    add_uncertainty() |> 
    add_player_info() |> 
    mutate(
      timestamp = .ffa_scrape_db$ffa_scrape[1,]$timestamp,
      tag = .ffa_scrape_db$ffa_scrape[1,]$tag,
      week = .ffa_scrape_db$ffa_scrape[1,]$week,
      season = .ffa_scrape_db$ffa_scrape[1,]$season
    ) 
  
  ffa_projtable <- ffa_raw_projection_table |> 
    select(avg_type:uncertainty, timestamp:season) |> 
    select(season, week, tag, timestamp, avg_type, id, everything()) |> 
    distinct()
  
  # FFA PLAYERS ####
  ffa_players <- ffa_raw_projection_table |> 
    select(id:pos, first_name:exp) |> 
    distinct()
  
  # FFA SITE POINTS ####
  ffa_raw_source_points <-
    .projections_table_data_sources(.ffa_scrape_db$ffa_scrape[1, ]$scrapeData[[1]], .scoreRules)
  
  ffa_proj_source_points <- ffa_raw_source_points |> 
    mutate(
      timestamp = .ffa_scrape_db$ffa_scrape[1,]$timestamp,
      tag = .ffa_scrape_db$ffa_scrape[1,]$tag,
      week = .ffa_scrape_db$ffa_scrape[1,]$week,
      season = .ffa_scrape_db$ffa_scrape[1,]$season
    ) |> 
    select(season, week, tag, timestamp, data_src, id, pos, everything()) |> 
    distinct()
  
  ffa_db <-
    dm(ffa_player_ids,
       ffa_players,
       ffa_projtable,
       ffa_proj_source_points,
       .ffa_scrape_db) |>
    dm_add_pk(ffa_player_ids, id, check = T) |>
    dm_add_pk(ffa_players, c(id, pos), check = T) |>
    dm_add_pk(ffa_projtable,
              c(season, week, tag, timestamp, avg_type, id, pos),
              check = T) |>
    dm_add_fk(ffa_players, id, ffa_player_ids) |>
    dm_add_fk(ffa_projtable, c(id, pos), ffa_players) |>
    dm_add_pk(ffa_proj_source_points,
              c(season, week, tag, timestamp, data_src, id, pos),
              check = T) |>
    dm_add_fk(ffa_proj_source_points, c(id, pos), ffa_players) |> 
    dm_add_fk(ffa_projtable, c(season, week, tag, timestamp), ffa_scrape) |> 
    dm_add_fk(ffa_proj_source_points, c(season, week, tag, timestamp), ffa_scrape)
    
  return(ffa_db)
  
}


