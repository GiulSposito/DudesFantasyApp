library(tidyverse)

# create a matchup schedule
schedule <- tribble(
  ~week, ~aTeam, ~hTeam, 
  1, "A", "B",
  1, "C", "D",
  2, "A", "C",
  2, "B", "D",
  3, "A", "D",
  3, "B", "C",
  4, "A", "B",
  4, "C", "D",
  # 5, "A", "C",
  # 5, "B", "D",
  # 6, "A", "D",
  # 7, "B", "C"
) %>% 
  mutate(
    aWin = NA
  )

# run a score sumulation over the schedule
simulateGames <- function(.mats, .numSim=100){
  
  rep(list(.mats),.numSim) %>% # 100 is # of simulations
    map_df(function(.mtall){
      
      .mtFinished  <- filter(.mtall, !is.na(aWin))
      .mtScheduled <- filter(.mtall, is.na(aWin))
      
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

games <- schedule %>% 
  simulateGames(1) %>% 
  select(-simId)

bind_rows(
  select(games, week, team=aTeam, win=aWin, los=hWin, score=aScore),
  select(games, week, team=hTeam, win=hWin, los=aWin, score=hScore)
) %>% 
  arrange(week, team) %>% 
  group_by(team) %>% 
  mutate( acScore = cumsum(score),
          across(c(win,los), as.integer),
          wins   =cumsum(win),
          losses = cumsum(los),
          winPct = wins/(wins+losses))
