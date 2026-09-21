library(dm)
library(tidyverse)

rnd <- readRDS("./data/nfl_round_db.rds")
sim <- readRDS("./data/dudes_simulation.rds")

#dm_draw(rnd, view_type = "all", column_types = T)

seeds <- sim$dudes_simSeeds

SEASON <- 2023
WEEK <- 10

# PLAYERS SIMULATIONS ####
sim_players <- sim$dudes_simSeeds |> 
  filter( season==SEASON, week==WEEK) |> 
  mutate( seedSize = map_int(seeds, length)) |> 
  filter( seedSize>1 ) |> 
  mutate( simulation = map(seeds, sample, size=1000, replace=T) ) |> 
  mutate( sim_summary = map(simulation, summary) ) |> 
  mutate( sim_summary = map(sim_summary, broom::tidy)) |> 
  unnest( sim_summary ) |> 
  select(-seeds, -seedSize)

rnd$matchups_games |> 
  filter(season==SEASON, week==WEEK) 

rst <- rnd$nfl_teams_rosters |>
  filter(season==SEASON, week==7) |> 
  filter(timestamp==max(timestamp))

a <- rst |>
  inner_join(sim_players, by = join_by(season, week, playerId)) |> 
  mutate(sim = map(seeds, sample, size=1000, replace=T)) |>
  filter(rosterSlotId<20) |> 
  nest(simTeam = sim, .by=c(season, week, teamId, simType)) |> 
  mutate(simTeam = map(simTeam, \(df){
    reduce(df$sim, `+`)
  })) |> 
  filter(teamId==3) |> 
  unnest(simTeam) |> 
  ggplot(aes(x=simTeam, fill=simType)) +
  geom_density(alpha=.5) +
  theme_minimal()

plotly::ggplotly(a)

reduce( x[20,]$simTeam[[1]]$sim , `+`)

x[20,]$simTeam[[1]] |> str()
list(a,b) |> str()

x[20,]$simTeam[[1]] |> 
  unlist()

a <- c(1,2)
b <- c(3,4)

reduce(list(a,b),`+`)

x$sim |> reduce(sum)

nfl <- readRDS("./data/nfl_players_db.rds")

nfl$nfl_players

sds |> 
  filter(is.na(playerId)) |> 
  distinct(id, playerId, pos) |> 
  inner_join(ffa$ffa_players)

ffa <- readRDS("./data/ffa_db.rds")
ffa$ffa_players |> filter(id=="15987")
