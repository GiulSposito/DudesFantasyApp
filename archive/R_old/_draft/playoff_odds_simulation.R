library(tidyverse)

# create a matchup schedule
matchups <- tribble(
  ~week, ~aTeam, ~hTeam, 
  1, "A", "B",
  1, "C", "D",
  2, "A", "C",
  2, "B", "D",
  3, "A", "D",
  3, "B", "C",
) %>% 
  mutate(
    aWin = NA
  )
# run a score sumulation over the schedule
simulateGames <- function(.mats, .numSim=100){

  rep(list(.mats),.numSim) %>% # 100 is # of simulations
    map_df(function(.mtall){
      
      .mtFinished  <- filter(.mtall, !is.na(aScore))
      .mtScheduled <- filter(.mtall, is.na(aScore))
      
      n <- dim(.mtScheduled)[1]
      .mtScheduled %>% 
        mutate(
          # score simulation
          aScore = rnorm(n, mean = 113.4947, sd = 22.22987), # values from season 2020
          hScore = rnorm(n, mean = 113.4947, sd = 22.22987), # values from season 2020
          aWin   = aScore > hScore, # who win?
          hWin   = !aWin            # who win?
        ) %>% 
        bind_rows(.mtFinished) %>% 
        return()
      
    }, .id="simId") %>% # simulation id

    mutate( simId = as.integer(simId) ) %>% 
    return()
}

# convert schedule format to team match formats
scheduleToTeamMatchs <- function(.schedule){
  bind_rows(
    select(.schedule, week, team=aTeam, opTeam=hTeam, 
           proScore=aScore, agstScore=hScore, win=aWin),
    select(.schedule, week, team=hTeam, opTeam=aTeam, 
           proScore=hScore, agstScore=aScore, win=hWin)
  ) %>% 
    return()
}

# calculate cumulative rank parameters
calcRankParameters <- function(.teamMatchs){
  
  .teamMatchs%>% 
    arrange(week, team) %>% 
    mutate(wBalance=if_else(win,1,-1)) %>% 
    mutate(scrBallance = proScore-agstScore) %>% 
    mutate(loss=!win) %>% 
    mutate(across(c(win, loss), as.integer)) %>% 
    group_by(team) %>% 
    mutate(wins=cumsum(win),
           losses=cumsum(loss),
           pctWin=wins/(wins+losses),
           acProScore = cumsum(proScore),
           acAgstScore = cumsum(agstScore),
           acScrBallance = cumsum(scrBallance)) %>% 
    ungroup() %>% 
    return()
  
}

# rank by win pct
rankByWinPct <- function(.rankPar){
  .rankPar %>% 
    group_by(week) %>% 
    mutate( rankPos = rank(-pctWin) ) %>% 
    add_count( rankPos, name="rankCount") %>% 
    ungroup() %>% 
    select(week, team, rankPos, rankCount) %>% 
    return()
} 

# simulate games
simGames <- simulateGames(matchups, 1)

# change schedule format
teamMatchs <- simGames %>% 
  filter(simId==1) %>% 
  select(-simId) %>% 
  scheduleToTeamMatchs()

teamMatchs <- matchups %>%
  scheduleToTeamMatchs()

# initial global rank
teamRankPar <- teamMatchs %>% 
  calcRankParameters()  

rank <- teamRankPar %>% 
  rankByWinPct() %>% 
  arrange(week, team) 

printRank <- function(.tm, .rk){
  .tm %>% 
    inner_join(.rk, by=c("week", "team")) %>% 
    arrange(week, rankPos) %>% 
    select(week, team, acProScore, wins, losses, pctWin, rankPos, rankCount) %>% 
    print()
}

# h2h detieing

oldRankFingerPrint <- vector("numeric", nrow(rank))

while(any(rank$rankPos!=oldRankFingerPrint)){
  
  # printRank(teamRankPar, rank) %>% 
  #   filter(week==14)
  
  oldRankFingerPrint <- rank$rankPos
  rank <- rank %>% 
    mutate(tweek=week) %>% 
    group_by(week, rankPos) %>% 
    nest() %>% 
    mutate( tieRank = map(data, function(.tied, .allTM){
      print(.tied)

      if(nrow(.tied)<2){
        .tied %>% 
          mutate(tieRankPos=1,
                 tieRankCount=1) %>% 
          select(team, tieRankPos, tieRankCount) %>%
          return()
      }
      
      # get h2h historic
      tiedTeamMatchs <- .allTM %>% 
        filter(week<=.tied$tweek[1]) %>% 
        filter( team %in% .tied$team, opTeam %in% .tied$team )
      
      # there is no h2h data
      # we must consider proPoints
      if(nrow(tiedTeamMatchs)==0) {
        resp <- .allTM %>% 
          filter(week<=.tied$tweek[1]) %>% 
          calcRankParameters() %>% 
          filter(week==.tied$tweek[1], team %in% .tied$team ) %>% 
          mutate(tieRankPos=rank(-acProScore)) %>% 
          add_count(tieRankPos, name="tieRankCount") %>% 
          select(team, tieRankPos, tieRankCount)
        
        return(resp)
      }
      
      # there is h2h data calc h2h rank
      deTiedMatchs <- tiedTeamMatchs %>% 
        calcRankParameters() %>%  
        group_by(team) %>% 
        filter( week == max(week) ) %>% 
        ungroup() %>% 
        mutate( week = .tied$tweek[1] )
      
      resp <- deTiedMatchs %>% 
        rankByWinPct()
        
      if (all(nrow(resp)==resp$rankCount)) {
        # tied cannot be splited 
        resp <- .allTM %>% 
          filter(week<=.tied$tweek[1]) %>% 
          calcRankParameters() %>% 
          filter(week==.tied$tweek[1], team %in% .tied$team ) %>% 
          mutate(rankPos=rank(-acProScore)) %>% 
          add_count(rankPos, name="rankCount")
      }
      
      resp %>% 
        select(team, tieRankPos=rankPos, tieRankCount=rankCount) %>%
        return()
    }, .allTM = teamMatchs)) %>% 
    unnest(tieRank, keep_empty = T) %>% 
    group_by(week) %>% 
    mutate(detiedRank = rank(100*rankPos+tieRankPos)) %>% 
    ungroup() %>% 
    select(week, team, rankPos=detiedRank) %>% 
    add_count(week, rankPos, name="rankCount") %>% 
    arrange(week, team)
  
   
}

teams <- readRDS("./data/simulation_v5_week14_final.rds")$teams 
teams %>% 
  select(teamId, name)


teamMatchs %>% 
  filter(week <= 14) %>% 
  mutate(win=as.integer(win)) %>% 
  #inner_join(select(teams, team=teamId, name)) %>% 
  pivot_wider(id_cols = c(team), names_from = opTeam, values_from = win, values_fn = sum) %>% 
  filter(team %in% c(1,4,6)) %>% 
  select(team, `1`,`4`,`6`)


teamMatchs %>% 
  calcRankParameters() %>% 
  select(week, team, pctWin, acProScore) %>% 
  inner_join(rank, by=c("week","team")) %>% 
  inner_join(select(teams, team=teamId, name)) %>% 
  arrange(week, rankPos) %>% 
  filter(week==max(week)) %>% 
  View()
  


# x
# .tied <- x[1,]$data[[1]]
# .allTM <- teamMatchs 
# 
# tiedTeamMatchs <- .allTM %>% 
#   filter(week<=.tied$tweek[1]) %>% 
#   filter( team %in% .tied$team, opTeam %in% .tied$team )
# 
# 
# {
#   .allTM %>% 
#     filter(week<=.tied$tweek[1], team %in% .tied$team ) %>% 
#     calcRankParameters() %>% 
#     filter( week == max(week) ) %>% 
#     mutate(tieRankPos=rank(-acProScore))  %>% 
#     add_count(tieRankPos, name="tieRankCount") %>% 
#     select(team, tieRankPos, tieRankCount) %>% 
#     return()
#   }
# 
# 
# %>% 
#   mutate(dltScore=proScore-agstScore) %>% 
#   pivot_wider(id_cols=c(week, team, proScore, agstScore, dltScore), 
#               names_from = opTeam, values_from = win) %>% 
#   arrange(week, team)
# 
# # get a schedule and rank teams by victory
# h2hWinRanker <- function(subMatchs){
#   # transform aTeam vs hTeam layout to one team
#   bind_rows(
#     select(subMatchs, week, team=aTeam, win=aWin, loss=hWin, pts=aScore),
#     select(subMatchs, week, team=hTeam, win=hWin, loss=aWin, pts=hScore)
#   ) %>% 
#     # compute cumulated victories and season points
#     group_by(team) %>% 
#     arrange(team, week) %>% 
#     mutate(
#       wins = cumsum(win),
#       losses = cumsum(loss),
#       seasonPts = cumsum(pts)
#     ) %>% 
#     group_by(week) %>% 
#     # compute win performance
#     mutate(winPct = wins/week) %>% 
#     arrange(week, team) %>% 
#     # rank against win performace
#     mutate( rank = rank(-winPct) ) %>% 
#     add_count(rank) %>% 
#     ungroup() %>% 
#     return()
# }
# 
# # funcao que rankquei um schedule
# calcRank <- function(games){
#   
#   # 1) make level 1
#   rankL1 <- h2hWinRanker(games) %>% 
#     arrange(week, rank)
#   
#   # 3) apply rank again for each rankgroup
#   rankL2 <- rankL1 %>% 
#     group_by(week, rank) %>% 
#     group_split() %>% 
#     map_df(function(.sm, .games){
#       srank <- .games %>%
#         filter(week <= .sm$week[1]) %>% 
#         filter( (aTeam %in% .sm$team & hTeam %in% .sm$team)|
#                 (aTeam %in% .sm$team & hTeam %in% .sm$team) ) %>% 
#         h2hWinRanker() %>%
#         select(-winPct, -rank, -n, -seasonPts) %>% 
#         group_by(team) %>% 
#         filter (week==max(week)) %>%
#         ungroup() %>% 
#         mutate( winPct = wins/(wins+losses), 
#                 rank = rank(-winPct) ) %>% 
#         add_count(rank) %>%         
#         select(team, rank, n) 
#       
#       .sm %>% 
#         left_join(srank, by=c("team")) %>% 
#         return()
#     }, .games = games) %>% 
#     arrange(week, rank.x, rank.y)
#   
#   # 4) compute a rank for season points
#   rankL3 <- rankL2 %>% 
#     group_by(week) %>% 
#     mutate( rankPts = rank(-seasonPts) ) %>% 
#     ungroup() %>% 
#     arrange(week, rank.x, rank.y, rankPts)
#   
#   # 5) compute a final ranking
#   rankFinal <- rankL3 %>% 
#     arrange(week, rank.x, rank.y, rankPts) %>% 
#     group_by(week) %>% 
#     mutate( rank = 1:n() )
# 
#   return(rankFinal)
# }
# 
# # # get one simulation case
# # games <- simulations %>% 
# #   filter(simId==42) %>% 
# #   select(-simId)
# # 
# # calcRank(games)
# # games
# 
# nsim <- max(simulations$simId)
# 
# simulations %>% 
#   filter(simId<=nsim) %>% 
#   nest(-simId) %>% 
#   mutate( ranking = map(data, calcRank) ) %>% 
#   select(-data) %>% 
#   unnest(ranking) %>% 
#   select(simId, week, team, rank ) %>% 
#   count( week, team, rank ) %>% 
#   mutate( prob = n/nsim ) %>% 
#   pivot_wider(id_cols = c(week, rank), names_from = team, values_from = prob, values_fill = 0)
# 
# 
# 
# 
# 
# 
# 
# 
# 
