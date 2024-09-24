library(tidyverse)
library(ffanalytics)

projections_table_data_sources <- function(.webscrape, .scoring_rules) {
  
  # quais os sites neste scrape?
  site_sources <- unique(.webscrape$QB$data_src)
  
  # separa os scrapes por data source 
  source_scrapes <- site_sources %>% 
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
      
    }, .scrp = .webscrape)
  
  # cria um tibble com o datasource e os scraps específicos
  tibble(
    data_src = site_sources,
    scrape = source_scrapes
  ) %>% 
    # aplica o calculo da projeção para cada jogodor xdatasource
    mutate( proj_table = map(scrape, 
                             projections_table, 
                             scoring_rules = .scoring_rules, 
                             avg_type="average") ) %>% 
    unnest(proj_table) %>% 
    select(data_src, id, pos, points) %>% 
    return()
}


projections_table_data_sources2 <- function(.webscrape, .scoring_rules) {
  
  # quais os sites neste scrape?
  site_sources <- unique(.webscrape$QB$data_src)
  
  # separa os scrapes por data source 
  source_scrapes <- site_sources %>% 
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
      
    }, .scrp = .webscrape)
  
  # cria um tibble com o datasource e os scraps específicos
  tibble(
    data_src = site_sources,
    scrape = source_scrapes
  ) %>% 
    # aplica o calculo da projeção para cada jogodor xdatasource
    mutate( proj_table = map(scrape, 
                             projections_table, 
                             scoring_rules = .scoring_rules,
                             avg_type=c("average","robust")) ) %>% 
    unnest(proj_table) %>% 
    select(data_src, avg_type, id, pos, points, dropoff, points_vor, rank, pos_rank) %>% 
    return()
}

