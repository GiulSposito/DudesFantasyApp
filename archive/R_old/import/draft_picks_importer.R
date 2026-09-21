library(rvest)
library(stringr)
library(tidyverse)

# chamada dentro da página de draft recap all rounds
# https://fantasy.nfl.com/league/3940933/draftresults?draftResultsDetail=0&draftResultsTab=round&draftResultsType=results

draft_file <- "./data/draft_picks.html"

read_html(draft_file) %>% 
  html_nodes("a.playerName") %>% 
  html_text() -> playerNames

read_html(draft_file) %>% 
  html_nodes("a.playerName") %>% 
  html_attr("href") %>% 
  str_extract("playerId=.*") %>% 
  str_replace("playerId=","") %>% 
  as.integer() -> playerIds

read_html(draft_file) %>% 
  html_nodes("a.teamName") %>% 
  html_text() -> teamNames

read_html(draft_file) %>% 
  html_nodes("a.teamName") %>% 
  html_attr("href") %>% 
  str_replace("/league/3940933/team/","") %>% 
  as.integer() -> teamIds

draft <- tibble(
  round       = rep(1:15,each=14),
  pick        = 1:210,
  player.id   = playerIds,
  player.name = playerNames,
  team.id     = teamIds,
  team.name   = teamNames
)

saveRDS(draft, "./data/draft_2022_picks.rds")
