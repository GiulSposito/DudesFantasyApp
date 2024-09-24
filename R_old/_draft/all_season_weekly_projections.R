library(tidyverse)
library(ffanalytics)
library(progressr)
library(furrr)

# recupera scraps (uma lista de semana, posicao, fonte)
scrapes <- readRDS("./data/season_simulation_weekly_scrape.rds")

# pega so o retorno e limpa requisicoes com erro
wscrap <- scrapes %>% 
  map(pluck, "result") %>% 
  compact()

# recuperador da semana (atributo da lista do scrape) e projecao resistente a falha de info
which_week <- attr_getter("week")
safety_proj_table <- possibly(projections_table, otherwise = NULL)

# prepara chamada em paralelo
with_progress({
  pbar <- progressor(steps = length(wscrap))
  plan(multisession, workers=5)
  # gera um df com as projecoes calculadas
  season_raw_wproj <- tibble(
      week     = map_int(wscrap, which_week),
      pos      = map_chr(wscrap, names),
      raw_data = map(wscrap, pluck, 1),
      prj_data = future_map(wscrap, function(.x,sc,avgt){
        pbar()
        safety_proj_table(.x, scoring_rules=sc, avg_type=avgt)      
      }, sc=yaml::read_yaml("./config/score_settings.yml"), avgt="average")
    )
  plan(sequential)
})

# trata as projecoes que foram calculadas
season_wproj <- season_raw_wproj %>% 
  mutate(has_data = !map_lgl(prj_data, is.null)) %>% 
  filter(has_data) %>% 
  select(week, prj_data) %>% 
  unnest(prj_data) %>% 
  arrange(week, id)

# checa completude
season_wproj %>% 
  count(week, pos, sort=T) %>% 
  pivot_wider(id_cols=c(pos), names_from="week", values_from = "n")

# salva
saveRDS(season_wproj, "./data/season_weekly_proj.rds")
