# private function to calc individual data sources player projections
.data_sources_stats <- function(.webscrape, .scoring_rules) {
  
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
                             avg_type="average",
                             return_raw_stats=T) ) |>  
    unnest(proj_table) |> 
    select(-scrape)  |> 
    distinct()
}


ffaDB <- readRDS("./data/ffa_db.rds")
ffaDB

scraps <- ffaDB$ffa_scrape |> 
  group_by(season, week) |> 
  filter(timestamp==max(timestamp)) |> 
  arrange(season, week)

.webscrape <- scraps[1,]$scrapeData[[1]]
.scoring_rules <- .scoreRules
  

.webscrape |> projections_table(return_raw_stats = T)
.webscrape |> .data_sources_stats(.scoreRules)

