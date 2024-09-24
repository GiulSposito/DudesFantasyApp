library(tidyverse)
library(glue)

### DATA SET PREPARATION

sim <- readRDS("./data/simulation_v5_week1_final.rds")

teams <- sim$teams %>% 
  select(teamId, name) %>% 
  mutate(nickname=str_trim(str_extract(name, "\\b(\\w+)$"))) %>% 
  mutate(nickname=janitor::make_clean_names(nickname)) %>% 
  select(id=teamId, name=nickname)

h2h <- 1:14 %>% 
  map_df(function(.w){
    
    sim <- glue("./data/simulation_v5_week{.w}_final.rds") %T>% 
      print() %>% 
      readRDS()
    
    match_result <- sim$matchups %>% 
      select(week, awayTeam.teamId, awayTeam.outcome, homeTeam.teamId, homeTeam.outcome) %>% 
      set_names(c("week", "away.id","away.win","home.id","home.win"))
    
    match_points <- sim$matchup_sim %>%
      select(week, homeTeam.teamId, awayTeam.teamId, homeTeam.totalPts, awayTeam.totalPts) %>% 
      set_names(c("week","home.id","away.id", "home.pts", "away.pts"))
    
    inner_join(match_result, match_points, by = c("week", "away.id", "home.id"))
  }) 

h2h_raw <- h2h %>% 
  inner_join(teams, by=c("away.id"="id")) %>% 
  rename(away.nm=name) %>% 
  inner_join(teams, by=c("home.id"="id")) %>% 
  rename(home.nm=name) %>% 
  mutate( home.win = if_else(home.win=="win",1L,0L),
          away.win = if_else(away.win=="win",1L,0L),
          home.los = if_else(home.win==1L,0L,1L),
          away.los = if_else(away.win==1L,0L,1L))

a <- bind_cols(
  h2h_raw %>% 
    select(week)
  ,
  h2h_raw %>% 
    select(starts_with("home")) %>% 
    set_names(str_replace(names(.), "home","team"))
  ,
  h2h_raw %>% 
    select(starts_with("away")) %>% 
    set_names(str_replace(names(.), "away","opp"))
)

b <- bind_cols(
  h2h_raw %>% 
    select(week)
  ,
  h2h_raw %>% 
    select(starts_with("away")) %>% 
    set_names(str_replace(names(.), "away","team"))
  ,
  h2h_raw %>% 
    select(starts_with("home")) %>% 
    set_names(str_replace(names(.), "home","opp"))
)

# FULL RESULT DATASET
h2h_full <- bind_rows(a,b) 


h2h_full

computeRank <- . %>% 
  group_by(team.id) %>% 
  arrange(week) %>% 
  mutate(
    wins = cumsum(team.win),
    losses = cumsum(team.los),
    pro.pts = cumsum(team.pts),
    agt.pts = cumsum(opp.pts),
    balance = cumsum(pro.pts-agt.pts),
    bal.cum = cumsum(balance)
  ) %>% 
  ungroup() %>% 
  mutate( win.pct = wins/(losses+wins))


rankH2H <- function(tieGroup, fullScore) {
  
  print("rank input")
  print(tieGroup)
  
  # base case #A: one team in the group
  # return itself
  if(nrow(tieGroup)==1){
    resp <- tieGroup$team.id
    print(glue("base case #A: {resp}"))
    return(resp)
  }
  
  # subset do fullscore
  pts.group <- fullScore %>% 
    filter( team.id %in% tieGroup$team.id)
  
  # split the new groups
  newGroups <- pts.group %>% 
    computeRank() %>% 
    filter(week==max(week)) %>% 
    arrange(desc(wins), pro.pts) %>% 
    mutate(win.pct = wins/week) %>%
    arrange(desc(win.pct)) %>% 
    group_split(desc(win.pct), .keep = FALSE)

  # base case #B: não tem mais do que um subgrupo de win.pct
  if(length(newGroups)==1){
    # confrontos diretos
    pts.group %>% 
      mutate(hasH2H = opp.id %in% pts.group$team.id) %>% 
      computeRank() %>% 
      # filter(week==max(week)) %>% 
      arrange(desc(wins), pro.pts) %>% 
      mutate(win.pct = wins/week) %>%
      arrange(desc(win.pct)) %>% 
      filter(week==max(week)) %>% 
      group_split(desc(win.pct), .keep = FALSE)
    
    
    resp <- newGroups[[1]] %>% 
      arrange(desc(pro.pts), agt.pts) %>% 
      pull(team.id)
    print(glue("base case #B: {resp}"))
    return(resp)
  }  
  
  # # base case #3: no match between the group
  # if (nrow(filter(pts.group,opp.id %in% team.id))==0){
  #   resp <- pts.group %>% 
  #     computeRank() %>% 
  #     filter(week==max(week)) %>% 
  #     arrange(desc(pro.pts), agt.pts) %>% 
  #     pull(team.id)
  # 
  #   print(glue("base case #3: {resp}"))
  #   return(resp)
  # }

  
  # recursion case
  print(glue("recursion groups: {len}", len=length(newGroups)))
  map(newGroups, rankH2H, fullScore=fullScore) %>% 
    return()
  
}

tieGroup <- newGroups[[2]]
fullScore <- h2h_full

team_rank <- unlist(rankH2H(h2h_full, h2h_full))

tibble(
  rank = 1:length(team_rank),
  team.id = team_rank
) %>% 
  inner_join(
    filter(computeRank(h2h_full), week==max(week)),
    by="team.id"
  )
