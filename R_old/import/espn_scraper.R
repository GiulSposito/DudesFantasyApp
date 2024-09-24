library(tidyverse)
library(httr2)
library(jsonlite)

# faz um mapeamento de/para ids entre o FFA e o Scrape da ESPN passando
# pela tabela de jogadores da NFLVERSE
espn_getEspn2FfaIds <- function(ffa_player_ids){
  
  #### TRATA IDS DOS JOGADORES ENTRE FFA NFLVERSE E ESPN
  
  # vamos fazer o bind da NFLVERSE e ESPN via "STATS_ID"
  pid_ffa <- ffa_player_ids %>% 
    select(id, stats_id, numfire_id) %>% # usa o stats_id como ponte
    filter(!is.na(stats_id)) %>% 
    distinct()
  
  # Tabela de jogadores da NFLVERSE
  pid_nflv <- nflreadr::load_rosters(2022) %>% 
    select(espn_id, yahoo_id, full_name) %>%  # usa o yahoo_id como ponte
    filter(!is.na(yahoo_id)) %>% 
    distinct() %>% 
    mutate(espn_id = as.integer(espn_id))
  
  # ja a defesa será via espn_id da tabela da FFA
  pid_dst <- player_ids %>% 
    select(id, espn_id) %>% 
    filter(as.integer(id)<=532) %>% 
    mutate(espn_id=as.integer(espn_id))  # usa o espn_id direto
  
  # nova ligação de/para
  pid_ffa %>% 
    inner_join(pid_nflv, by=c("stats_id"="yahoo_id")) %>% 
    select(-stats_id,-numfire_id, -full_name) %>% 
    bind_rows(pid_dst) %>% 
    return()
}

espn_srapeCurrWeekProj <- function(.season) {
  
  ##### ESPN SCRAPPING (só tem um jeito de pedir: current week all players)
  resp <- request(
      glue("https://fantasy.espn.com/apis/v3/games/ffl/seasons/{.season}/segments/0/leaguedefaults/3?scoringPeriodId=0&view=kona_player_info")
    ) %>%
    req_method("GET") %>% 
    # for pagging set: 'limit' and 'offset'
    req_headers("x-fantasy-filter"='{"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":2000,"offset":0,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}') %>% 
    req_perform()
  
  # trata o json de resposta
  data <- resp %>% 
    resp_body_json(simplifyDataFrame=T) 
  
  # Id das Posicoes na ESPN
  espn_positions <- tibble(
    defaultPositionId = c(1,2,3,4,16,5),
    pos = c("QB","RB","WR","TE","DST","K")
  )
  
  # id das estatísticas na ESPN
  stat_ids <- readRDS("./data/espn_stat_id.rds")
  
  # FINAL DATAFRAME
  data$players$player %>% 
    as_tibble() %>% 
    select(id, defaultPositionId, fullName,  active, injured, injuryStatus, stats) %>% 
    inner_join(espn_positions, by = "defaultPositionId") %>% 
    # aninha as estatisticas
    mutate( stats = map(stats, function(.st){
      .st$stats %>% 
        as_tibble() 
    })) %>% 
    # deixa em formato tidy e resove o stat_id (espn) para colName (ffa)
    mutate( stats = map(stats, function(.st,.cols){
      if(ncol(.st)<1) {return(tibble())}
      pivot_longer(.st, cols=everything(), names_to = "statId", values_to = "value") %>% 
        inner_join(.cols, by="statId") %>% 
        return()
    }, .cols=stat_ids) ) %>% 
    rename(src_id=id) %>% 
    # corrige os ids das defesas (vem negativo e com 16000 de ofsse enquando no
    # ffa é positivo e com 60000 de offset)
    mutate(src_id=if_else(pos=="DST", -(src_id+16000L)+60000L, src_id)) %>% 
    return()
  
}

# converte o formato do scraping da ESPN para o formato de scraping da FFA
espn_rawToFfaScrap <- function(.espn_raw, .espn2ffa_ids, .week, .season){

  espn_scrape <- .espn_raw %>% 
    # integra os ids de de/para ao scrape da ESPN, formata e renomeia colunas
    left_join(.espn2ffa_ids, by=c("src_id"="espn_id")) %>%
    mutate(data_src="ESPN" ) %>% 
    mutate(position=pos) %>% 
    select(position, id, src_id, data_src, player=fullName, pos, stats) %>% 
    # desaninha estatisticas
    unnest(stats) %>% 
    select(-statId, -shortName, -janName, -group, -header) %>% 
    filter(!is.na(id)) %>% 
    mutate(src_id=as.character(src_id)) %>% 
    # agrupa e aninha por posicao para pivotar para long format posicao a posicao
    group_by(position) %>% 
    nest() %>% 
    mutate(data_wider = map(data, 
                            ~pivot_wider(.x, 
                                         id_cols = c(id, src_id, data_src, player, pos), 
                                         names_from = colName, values_from = value, values_fill = 0)
    ))
  
  # recria em formato de lista por posicao como e no FFA
  espnWebScrape <- espn_scrape$data_wider
  names(espnWebScrape) <- espn_scrape$position
  
  # atribui temporada e semana como e no FFA
  attr(espnWebScrape, "season") <- .season
  attr(espnWebScrape, "week") <-  .week
  
  return(espnWebScrape)
  
}

# funcao que funde a webScrapes (FFA) com a espnScraps (espn) numa 
# unica lista de scrpas
espn_InjectScrap <- function(.espnScrp, .ffaScrp){
  # juntas os scrapes num tible por posicao
  allScrapes <- left_join(
    tibble( pos = names(.ffaScrp), ffa=.ffaScrp),
    tibble( pos = names(.espnScrp), espn=.espnScrp),
    by="pos") %>% 
    # posicao a posicao, adiciona uma lista na outra
    mutate( joinScrape = map2(ffa, espn, function(.w, .e){
      if(is.null(.e)) return(.w)
      bind_rows(.w, .e)
    })) %>% 
    # devolve somente a nova lista
    select(-ffa, -espn)
  
  # recompoe de tibble para lista
  newScrape <- allScrapes$joinScrape
  names(newScrape) <- allScrapes$pos
  
  # atributos de controle da FFA
  attr(newScrape, "season") <- attr(.ffaScrp, "season")
  attr(newScrape, "week") <-  attr(.ffaScrp, "season")
  
  return(newScrape)
}


