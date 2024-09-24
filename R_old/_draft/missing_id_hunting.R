evan <- 15368
chase <- 14717

yahooScrap %>% 
  filter(position=="K") %>%
  filter(id==evan)

webScraps[["K"]] %>% 
  filter(id==evan)

scraps[["K"]] %>% 
  filter(str_detect(player, "Evan") | str_detect(player, "McLaughlin")) %>%
  projections_table()

player_ids %>% 
  filter(id %in% c(evan, chase))


proj_table %>% 
  filter(id==evan)

players_stats %>% 
  filter(firstName=="Chase")

evanId <- 2565953

teams_rosters %>% 
  filter(teamId==6) %>% 
  unnest(rosters) %>% 
  select(playerId, rosterSlotId) %>% 
  filter(playerId == evanId)

player_ids %>% 
  filter(id==evan) %>% 
  glimpse()

player_ids %>% 
  filter(id==evan) %>% 
  glimpse()

team_allocation %>% 
  filter(playerId == evanId)

players_stats %>% 
  filter(playerId==evanId)

players_projs %>% 
  filter(id==evan) %>% 
  glimpse()

allscraps 

scraps <- list("K"=allscraps$K)
attr(scraps, "season") <- 2021
attr(scraps, "week") <- 5

allscraps$K %>% class()

proj_table %>% 
  filter(first_name %in% c("Chase","Evan"))

ptsproj %>% 
  filter(pos=="K", id==chase)
