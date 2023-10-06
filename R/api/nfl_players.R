library(glue)
library(tidyverse)
library(dm)
source("./R/api/nfl_api.R")



# return the league players
nfl_players <- function(.authToken, .leagueId){
  
  players <- nfl_api(
    .path = "v2/league/players",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "count"     = 3000
    ),
    .auth=.authToken)
  
}

# return the league player with stats
nfl_players_stats <- function(.authToken, .leagueId, .season, .weeks){

  # # stats reference
  # 
  # [
  #   {"type":"researchStats","season":"2015","week":"1"},
  #   {"type":"ranks","season":"2015","week":"1"},
  #   {"type":"stats","season":"2015","week":"1"},
  #   {"type":"stats","season":"2015"},
  #   {"type":"projectedStats","season":"2015","week":"1"},
  #   {"type":"nflGames","season":"2015","week":"1"}
  # ]

  
  # define estatísticas para retorno
  stats_str <- .weeks %>% 
    map_chr(~glue('{"type":"stats","season":"<<.season>>","week":"<<.x>>"},{"type":"rankAgainstPosition","season":"<<.season>>","week":"<<.x>>"},{"type":"advanced","season":"<<.season>>","week":"<<.x>>"},{"type":"researchStats","season":"<<.season>>","week":"<<.x>>"}', .open = "<<", .close = ">>")) %>% 
    c(.,glue('{"type":"stats","season":"<<.season>>"}', .open = "<<", .close = ">>")) %>% 
    paste(collapse = ",") %>% 
    paste0("[",.,"]")
  
    
  pstats <- nfl_api(
    .path = "v2/league/players",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "stats"     = stats_str,
      "count"     = 3000
    ),
    .auth=.authToken)
  
  return(pstats)
  
}

# return the league player with stats
nfl_players_stats_adv <- function(.authToken, .leagueId, .season, .weeks, .stats){
  
  # # stats reference
  # 
  # [
  #   {"type":"researchStats","season":"2015","week":"1"},
  #   {"type":"ranks","season":"2015","week":"1"},
  #   {"type":"stats","season":"2015","week":"1"},
  #   {"type":"stats","season":"2015"},
  #   {"type":"projectedStats","season":"2015","week":"1"},
  #   {"type":"nflGames","season":"2015","week":"1"}
  # ]
  
  # The possible types are: 'stats', 'twoWeekStats', 'fourWeekStats',
  # 'projectedStats', 'restOfSeasonProjectedStats', 'researchStats',
  # 'ranks', 'nflGames', 'advanced', 'rankAgainstPosition'.
  
  
  # define estatísticas para retorno
  stats_str <- .weeks %>% 
    map_chr(~glue('{"type":"<<.stats>>","season":"<<.season>>","week":"<<.x>>"}', .open = "<<", .close = ">>")) %>% 
    c(.,glue('{"type":"<<.stats>>","season":"<<.season>>"}', .open = "<<", .close = ">>")) %>% 
    paste(collapse = ",") %>% 
    paste0("[",.,"]")
  
  
  players <- nfl_api(
    .path = "v2/league/players",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "stats"     = stats_str,
      "count"     = 3000
    ),
    .auth=.authToken)
  
}


# return the league player with stats
nfl_players_advanced <- function(.authToken, .leagueId, .season, .weeks, .playerId){
  
  player_adv <- nfl_api(
    .path = "v2/player/advanced",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "playerId"  = .playerId,
      "week"      = .week,
      "season"    = .season
    ),
    .auth=.authToken)
  
  return(player_adv)
  
}


.enframeWeekStats <- function(stat){
  stat$week |> 
    unlist() |>
    enframe() |> 
    separate(name, into = c( "season", "week", "statId"), sep = "\\.",
             convert = F)
}

.enframeSeasonStats <- function(stat){
  stat$season |> 
    unlist() |>
    enframe() |> 
    separate(name, into = c( "season", "statId"), sep = "\\.",
             convert = F)
}  

.unnestStats <- function (dt, statName){
  dt_filtered <- dt |> 
    select(playerId, {{statName}}) |> 
    filter(map_int({{statName}}, nrow)>0)
  
  if (nrow(dt_filtered)==0) return(NULL)
  
  dt_filtered |> 
    unnest({{statName}}) |> 
    mutate(
      across(c(-statId,-value), as.integer),
      value=parse_number(value)
    )  
}

# convert uma resposta em um dataframe
nfl_extractPlayersStats <- function(playersStatsResp, statsDict){
  
  # limpa o json mantendo so o id do jogador e as info de statisticas
  players_stats_nested <-  playersStatsResp$content$games[[1]]$players |>
    tibble(players = _) |>
    unnest_wider(players) |>
    select(
      playerId,
      stats_raw = stats,
      advanced_raw = advanced,
      researchStats_raw = researchStats
    ) |> 
    # converte as listas de estatisticas em DFs aninhados
    mutate(
      statsWeek = map(stats_raw, .enframeWeekStats),
      statsSeason = map(stats_raw, .enframeSeasonStats),
      advStatsWeek = map(advanced_raw, .enframeWeekStats),
      researchStatsWeek = map(researchStats_raw, .enframeWeekStats),
      researchStatsSeason = map(researchStats_raw, .enframeSeasonStats)
    )
  
  # weekly stats
  stats_data <- players_stats_nested |> 
    .unnestStats(statsSeason) |> 
    mutate(week=0L) |> 
    bind_rows(.unnestStats(players_stats_nested, statsWeek))
  
  nfl_players_points <- stats_data  |> 
    filter(statId=="pts") |> 
    select(-statId) |> 
    rename(pts=value) |> 
    select(playerId, season, week, pts)
  
  nfl_players_stats <- stats_data |> 
    filter(statId!="pts") |> 
    mutate(statId=as.integer(statId)) |> 
    select(playerId,season, week, everything())
  
  nfl_players_adv_stats <- players_stats_nested |> 
    .unnestStats(researchStatsSeason) |> 
    mutate(week=0L) |> 
    bind_rows(
      .unnestStats(players_stats_nested, researchStatsWeek),
      .unnestStats(players_stats_nested, advStatsWeek)
    ) |> 
    pivot_wider(id_cols=c(playerId, season, week),
                names_from = statId,
                values_from = value)
  
  nfl_stat_dictionary <- statsDict |> 
    rename(statId=id)
  
  
  nfl_stats_db <- dm(nfl_stat_dictionary,
                     nfl_players_points,
                     nfl_players_stats,
                     nfl_players_adv_stats) |> 
    dm_add_pk(nfl_stat_dictionary, statId) |> 
    dm_add_pk(nfl_players_points, c(playerId, season, week)) |> 
    dm_add_pk(nfl_players_stats, c(playerId, season, week, statId)) |> 
    dm_add_pk(nfl_players_adv_stats, c(playerId, season, week)) |> 
    dm_add_fk(nfl_players_stats, statId, nfl_stat_dictionary)
  
  return(nfl_stats_db)
}

# convert uma resposta em um dataframe
nfl_extractPlayers <- function(playersResp){
  
  playersResp$content$games[[1]]$players %>% 
    tibble(players=.) %>% 
    unnest_wider(players) %>% 
    mutate(across(c(playerId, nflTeamId, byeWeek), as.integer)) %>% 
    return()
  
}


