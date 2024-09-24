library(tidyverse)
library(dm)
library(ffanalytics)
library(lubridate)
library(glue)

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
    # src = sources,
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
      
      resp
      
    }, .scrp = .webscrape)
  
  # cria um tibble com o datasource e os scraps específicos
  tibble(
    data_src = site_sources,
    scrape = source_scrapes
  ) |> 
    filter(!is.na(data_src)) |> 
    # aplica o calculo da projeção para cada jogodor xdatasource
    mutate( proj_table = map(scrape, 
                             projections_table, 
                             scoring_rules = .scoring_rules, 
                             avg_type="average") ) |>  
    unnest(proj_table) |> 
    select(data_src, id, pos, points)  |> 
    distinct()
}



# public function to call the scrap and to wrap it in a DM objetc
scrapeWebData <- function(.season, .week, .tag) {
  scrape_raw <- .scrapeData(.week, .season)

  ffa_scrape <- tibble(
    season = as.integer(.season),
    week = as.integer(.week),
    tag = as.character(.tag),
    timestamp = now(),
    scrapeData = list(scrape_raw)
  )  
  
  scrape_db <- dm(ffa_scrape) |> 
    dm_add_pk(ffa_scrape, c(season, week, tag, timestamp), check=T) 
  
  return(scrape_db)
}

# rum all FFA calculations and build a DB version
calcProjections <- function(.ffa_data, .scoreRules){
  
  if("dm" %in% class(.ffa_data)){
    ffa_scrape <- .ffa_data$ffa_scrape[1,]
  } else {
    ffa_scrape <- .ffa_data
  }
  
  # FFA PLAYER IDS: ORIGINAL ####
  # ffa_player_ids <- ffanalytics:::player_ids

  # FFA PLAYER IDS: TRATANDO IDS NAO MAPEADOS ####
  # mis_player_ids <- readRDS("./data/missing_player_ids.rds")
  
  ffa_player_ids <- ffanalytics:::player_ids # |> 
    # anti_join(mis_player_ids, by=join_by(id)) |> 
    # bind_rows(mis_player_ids)
  
  # FFA PROJECT TABLE ####
  ffa_raw_projection_table <- 
    projections_table(ffa_scrape$scrapeData[[1]], .scoreRules) |> 
    # add_ecr() |>
    # add_adp() |> 
    # add_aav() |> 
    # dd_uncertainty() |> 
    add_player_info() |> 
    mutate(
      timestamp = ffa_scrape$timestamp,
      tag = ffa_scrape$tag,
      week = ffa_scrape$week,
      season = ffa_scrape$season
    ) 
  
  ffa_projtable <- ffa_raw_projection_table |> 
    #select(avg_type:uncertainty, timestamp:season) |> 
    select(season, week, tag, timestamp, avg_type, id, everything()) |> 
    distinct()
  
  # FFA PLAYERS ####
  ffa_players <- ffa_raw_projection_table |> 
    select(id:pos, first_name:exp) |> 
    distinct()
  
  # FFA SITE POINTS ####
  ffa_raw_source_points <-
    .projections_table_data_sources(ffa_scrape$scrapeData[[1]], .scoreRules)
  
  ffa_proj_source_points <- ffa_raw_source_points |> 
    mutate(
      timestamp = ffa_scrape$timestamp,
      tag = ffa_scrape$tag,
      week = ffa_scrape$week,
      season = ffa_scrape$season
    ) |> 
    select(season, week, tag, timestamp, data_src, id, pos, everything()) |> 
    distinct()
  
  ffa_db <-
    dm(ffa_player_ids,
       ffa_players,
       ffa_projtable,
       ffa_proj_source_points,
       ffa_scrape) |>
    dm_add_pk(ffa_player_ids, id, check = T) |>
    dm_add_pk(ffa_players, c(id, pos), check = T) |>
    dm_add_pk(ffa_projtable,
              c(season, week, tag, timestamp, avg_type, id, pos),
              check = T) |>
    dm_add_pk(ffa_proj_source_points,
              c(season, week, tag, timestamp, data_src, id, pos),
              check = T) |>
    dm_add_pk(ffa_scrape, c(season, week, tag, timestamp), check=T) |> 
    dm_add_fk(ffa_players, id, ffa_player_ids) |>
    dm_add_fk(ffa_projtable, c(id, pos), ffa_players) |>
    dm_add_fk(ffa_proj_source_points, c(id, pos), ffa_players) |> 
    dm_add_fk(ffa_projtable, c(season, week, tag, timestamp), ffa_scrape) |> 
    dm_add_fk(ffa_proj_source_points, c(season, week, tag, timestamp), ffa_scrape)
    
  return(ffa_db)
  
}


