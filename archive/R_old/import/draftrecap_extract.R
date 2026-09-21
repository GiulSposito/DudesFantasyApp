library(jsonlite)
library(httr)
library(tidyverse)
library(glue)

# busca a informação dos times
source("./R/api/ffa_league.R")
config <- yaml::read_yaml("./config/config.yml")
teams_resp <- ffa_league_teams(config$authToken,config$leagueId)
year <- 2023

# transforma a resposta de lista para dataframe
teams <- teams_resp$content$games[[1]]$leagues[[1]]$teams %>% 
  map_df(function(x){
    tibble(
      teamId = as.integer(x$teamId),
      teamName = x$name,
      imageUrl = x$imageUrl
    )
  })

team_ids <- teams$teamId

# extrai o conteúdo do site com o json comentando o draft grade
recap_list <- team_ids %>% 
  map(function(x){
    # URL do json do draft recap eh fixa muda so o ano.
    GET(glue("https://nfl-fantasy.automatedinsights.com/content-prod/{year}/draftrecap/eb70/3940933/{x}.json.gzip")) %>% 
      content(as="text") %>% 
      # na verdade é uma chamada js passando o conteúdo json, removo o entorno da chamaa
      str_remove("YUI.Env.onDraftRecapLoaded\\(  ") %>% 
      str_remove("  \\);") %>% 
      # converte o conteúdo json
      fromJSON(flatten = T, simplifyDataFrame = T)
  })

# format o json e concatena num data.frame
recap <- recap_list %>% 
  map_df(function(x){
    tibble(
      grade = x$draft_grade,
      title = x$title,
      text = x$paragraphs$text,
      probs = list(as_tibble(x$probabilities)),
      proj  = list(as_tibble(x$projected_outcomes))
    )
  }) %>% 
  unnest(c(probs, proj)) %>% 
  mutate( teamId = team_ids ) %>% 
  select( teamId, everything())

# join como o time
draft_recap <- teams %>% 
  inner_join(recap, by = "teamId") %>% 
  arrange(desc(champ))

# exposta para uma planilha
# library(googlesheets4)
# googlesheets4::gs4_create("Draft Ranking", sheets = list(draft_grades=draft_recap))

# salva os grades em rds
saveRDS(draft_recap,"./data/draft_recap_rank.rds")
saveRDS(recap_list, "./data/draft_recap_data.rds")

