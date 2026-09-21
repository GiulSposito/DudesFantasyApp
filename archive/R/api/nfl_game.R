library(glue)
library(tidyverse)
source("./R/api/nfl_api.R")

# return the league statistic codes
nfl_gameStats<- function(){
  
  players <- nfl_api(
    .path = "v2/game/stats",
    .query = list(
      "appKey"    = "internalemailuse",
      "count"     = 3000
    ),
    .auth="")
  
}

nfl_extractStatDict <- function(gameStatResp){
  gameStatResp$content$games[[1]]$stats |> 
    map(discard, is.null) |> 
    map_df(as_tibble) |>
    mutate(id = as.integer(id)) |> 
    #mutate(colName = str_c(str_replace_na(positionCategory), shortName, sep=" ")) |> 
    add_count(shortName) |> 
    mutate(colName = janitor::make_clean_names(
      str_c(shortName, str_replace_na(positionCategory, replacement=""), sep="_") )) |> 
    arrange(id)
}
