library(tidyverse)
library(dm)

rnd <- readRDS("./data/nfl_round_db.rds") # composicao dos times
stt <- readRDS("./data/nfl_stats_db.rds") # pontuacao
ply <- readRDS("./data/nfl_players_db.rds") # players info
sim <- readRDS("./data/dudes_simulation_db.rds") # simulation data
ffa <- readRDS()

# Fixed slots especification
SLOTS <- tibble(
  pos = c("QB", "WR", "RB", "TE", "K", "DEF"),
  n = c(1,2,2,1,1,1)
)

# aux funciont to select best player by rnk & score
selectPlayers <- function(playerSet, slots=SLOTS){
  fixedSlots <- split(slots, 1:nrow(slots)) |> 
    map_df(function(slot, p_set){
      p_set |> 
        filter( pos==slot$pos ) |> 
        slice_max(tibble(rank, projScore), n=slot$n)
    }, p_set=playerSet)
  
  flexSlot <- playerSet |> 
    anti_join(fixedSlots, by=join_by(playerId)) |> 
    filter(pos%in%c("WR", "RB")) |> 
    slice_max(tibble(rank, projScore), n=1)
  
  return(bind_rows(fixedSlots, flexSlot))
}

# aux funciont to select best player by rnk & score
selectBestPlayers <- function(playerSet, slots=SLOTS){
  fixedSlots <- split(slots, 1:nrow(slots)) |> 
    map_df(function(slot, p_set){
      p_set |> 
        filter( pos==slot$pos ) |> 
        slice_max(pts, n=slot$n)
    }, p_set=playerSet)
  
  flexSlot <- playerSet |> 
    anti_join(fixedSlots, by=join_by(playerId)) |> 
    filter(pos%in%c("WR", "RB")) |> 
    slice_max(pts, n=1)
  
  return(bind_rows(fixedSlots, flexSlot))
}

# player pos
player_pos <- ply$nfl_players |> 
  select(playerId, pos=position)

# rosters
rosters <- rnd$nfl_teams_rosters |> 
  filter(timestamp==max(timestamp), .by = c(season, week, teamId)) |> 
  select(-tag, -timestamp, -slotPosition, -isEditable, -isReserveStatus) |> 
  arrange(season, week, teamId)

# rosters with points
rosters_perf <- rosters |> 
  left_join(stt$nfl_players_points, by = join_by(season, week, playerId))

# team points (starters only)
team_perf <- rosters_perf |> 
  filter(rosterSlotId<20) |> 
  summarise(totalPts=sum(pts, na.rm=T), .by=c(season, week, teamId))

bestRoster <- rosters_perf |> 
  mutate( pts = if_else(is.na(pts), 0, pts)) |> 
  left_join(player_pos, by = join_by(playerId)) |> 
  nest( playersSet = c(playerId, pos, pts), .by=c(season, week, teamId) ) |> 
  mutate( bestRoster = map(playersSet, selectBestPlayers, .progress="Selecting Best Players") )

team_potencial <- bestRoster |> 
  select(-playersSet) |> 
  unnest(bestRoster) |> 
  summarise(potencialPts = sum(pts, na.rm = T), .by=c(season, week, teamId))
  

# select best starters
bestStarters <- rosters |> 
  nest(data=playerId, .by=c(season, week, teamId)) |> 
  mutate( data = map(data, function(.dt, .p_pos){
    .dt |> 
      select(playerId1 = playerId) |>
      expand_grid(playerId2 = playerId1) |> 
      inner_join(select(.p_pos, playerId1 = playerId, pos1 = pos),
                 by = join_by(playerId1)) |>
      inner_join(select(.p_pos, playerId2 = playerId, pos2 = pos),
                 by = join_by(playerId2)) |> 
      filter(pos1 == pos2, playerId1 <= playerId2)
  }, .p_pos=player_pos, .progress="Comparation Scenarios")) |> 
  unnest(data) |> 
  inner_join(
    select(sim$dudes_players_simulations, season, week, playerId1=playerId, simType, sim1=simulation),
    by = join_by(season, week, playerId1), relationship = "many-to-many") |> 
  inner_join(
    select(sim$dudes_players_simulations, season, week, playerId2=playerId, simType, sim2=simulation),
    by = join_by(season, week, playerId2, simType)
  ) |> 
  mutate( p1_over_p2 = map2_dbl(sim1, sim2, function(s1,s2) mean(s1>=s2) ) ) |> 
  mutate( bestPlayer = if_else(p1_over_p2>.5, playerId1, playerId2) ) |>
  mutate( bestSim =  if_else(p1_over_p2>.5, sim1, sim2) ) |> 
  select( season, week, teamId, simType, playerId=bestPlayer, pos=pos1, sim=bestSim ) |> 
  mutate( projScore = map_dbl(sim, median, .progress = "Projecting Score")) |> 
  count(season, week, teamId, simType, playerId, pos, projScore, name = "rank", sort = T) |> 
  nest( playerSet=c(playerId, pos, projScore, rank), .by=c(season, week, teamId, simType)) |> 
  mutate( starters = map(playerSet, selectPlayers, .progress="Defining Best Starters" ) )


projTeamScore <- bestStarters |> 
  select(season, week, teamId, simType, starters) |> 
  arrange(season, week, teamId) |> 
  unnest(starters) |> 
  left_join(stt$nfl_players_points, by = join_by(season, week, playerId)) |> 
  summarise( totalProjPts = sum(pts, na.rm = T), .by=c(season, week, teamId, simType))

projTeamScore |> 
  inner_join(team_perf, by = join_by(season, week, teamId)) |> 
  mutate( modelIsBest = totalProjPts>totalPts) |> 
  count(simType, modelIsBest, sort=T)

projTeamScore |> 
  inner_join(team_perf, by = join_by(season, week, teamId)) |> 
  inner_join(team_potencial, by = join_by(season, week, teamId)) |> 
  filter(teamId==3) |> 
  pivot_longer(cols = c(starts_with("total"), potencialPts)) |> 
  ggplot(aes(x=week, y=value, linetype=name, color=simType)) +
  geom_line() +
  facet_wrap(simType~.)  +
  theme_minimal()


projTeamScore |> 
  inner_join(team_perf, by = join_by(season, week, teamId)) |> 
  inner_join(team_potencial, by = join_by(season, week, teamId)) |> 
  mutate(modelGain=totalProjPts-totalPts) |> 
  filter(teamId==3) |> 
  ggplot(aes(x=week, y=modelGain, color=simType, fill=simType)) +
  geom_point(size=2) +
  geom_bar(stat="identity", position="dodge", width=.2) +
  facet_wrap(simType~.)  +
  theme_minimal()


projTeamScore |> 
  inner_join(team_perf, by = join_by(season, week, teamId)) |> 
  ggplot(aes(totalPts, totalProjPts, color=simType)) +
  geom_point(alpha=.5) +
  stat_smooth(se=F, method="lm") +

  theme_minimal()


projTeamScore |> 
  inner_join(team_perf, by = join_by(season, week, teamId)) |> 
  nest(data=c(totalProjPts, totalPts), .by=c(simType)) |> 
  mutate( lm = map(data, function(.x){
    lm(totalProjPts ~ totalPts, data=.x)
  })) |> 
  mutate( factors = map(lm, broom::tidy)) |> 
  unnest(factors) |> 
  filter(term=="totalPts") |> 
  arrange(desc(estimate))











