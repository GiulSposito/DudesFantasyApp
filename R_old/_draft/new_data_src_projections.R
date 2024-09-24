library(tidyverse)
library(lubridate)
library(glue)
library(ffanalytics)
library(flexdashboard)
library(yaml)

# Suppress summarise info
options(dplyr.summarise.inform = FALSE)

# EXECUTION PARAMETERS ####
week <- 3
season <- 2022
config <- read_yaml("./config/config.yml")
prefix <- "preTNF"
destPath <- "static/reports/2022"
sim.version <- 5

webScrape <- readRDS(glue("./data/weekly_webscrapes_{week}.rds"))

site_sources <- unique(webScrape$QB$data_src)

scrp_srcs <- site_sources %>% 
  map(function(.src, .scrp){
    
    resp <- .scrp %>% 
      map(~filter(.x, data_src==.src, !is.na(id))) %>% 
      set_names(names(.scrp)) %>% 
      keep(~nrow(.x)>0)
    
    # atributos de controle da FFA
    attr(resp, "season") <- attr(.scrp, "season")
    attr(resp, "week") <-  attr(.scrp, "season")
        
    resp %>% 
      return() 
    
  }, .scrp = webScrape)

tibble(
  data_src = site_sources,
  src_scrape = scrp_srcs
) %>% 
  mutate( proj_table = map(src_scrape, 
                           projections_table, 
                           scoring_rules = read_yaml("./config/score_settings.yml"), 
                           avg_type="average") ) %>% 
  select(-src_scrape) %>% 
  unnest(proj_table) %>% 
  select(data_src, id, pos, points) %>% 
  count(data_src, pos) %>% 
  pivot_wider(id_cols = data_src, names_from = pos, values_from = n)

