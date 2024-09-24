# MATCHUPS
source("./R/api/ffa_api.R")

config <- yaml::read_yaml("./config/config.yml")

ffa_players_timestats <- function(.authToken, .season=2021, .week=17){
  ffa_api(
    .path = "/v2/players/weektimestats",
    .query = list(
      "appKey" = "internalemailuse",
      "season" = .season,
      "week"   = .week
    ),
    .auth=.authToken)
}

resp <- ffa_players_timestats(config$authToken)

resp$content %>% View()

xaxis <- resp$content$games$`102021`$xaxis %>% 
  as_tibble() %>% 
  mutate(across(c(start, end), lubridate::as_datetime))

all_times <- bind_rows(
  select(xaxis, dttm = start),
  select(xaxis, dttm = end)
) %>% 
  distinct() %>% 
  arrange(dttm)

all_teams <- sim$teams %>% 
  select(teamId)

dttmTeamComb <- expand_grid(dttm=all_times$dttm, teamId=all_teams$teamId)


playerSchedule <- resp$content$games$`102021`$playerProjectedTimeStats %>% 
  map_df(~tibble( nfl_id = as.integer(names(.x)) ), .id="end") %>% 
  mutate(end = lubridate::as_datetime(end))

playerProjPoints <- sim$ptsproj %>% 
  filter(week==17) %>% 
  add_count(id) %>% 
  filter(n>=3) %>% 
  group_by(id) %>% 
  nest() %>% 
  mutate( stat = map(data, function(.dt){
    broom::tidy(t.test(.dt$pts.proj))
  })) %>% 
  unnest(stat) %>% 
  select(id, estimate, conf.low, conf.high) %>% 
  ungroup()

id_map <- player_ids %>% 
  select(id, nfl_id) %>% 
  mutate_all(as.integer)

ptsTimeTable <- sim$teams %>% 
  unnest(rosters) %>% 
  select(teamId, name, rosterSlotId, playerId) %>% 
  inner_join(id_map, by=c("playerId"="nfl_id")) %>% 
  inner_join(playerProjPoints, by="id") %>% 
  filter(rosterSlotId < 20) %>% 
  inner_join(playerSchedule, by=c("playerId"="nfl_id")) %>% 
  group_by(teamId, name, end) %>% 
  summarise(
    estimate = sum(estimate), 
    conf.low = sum(conf.low), 
    conf.high = sum(conf.high)
  ) %>% 
  ungroup() %>% 
  arrange(teamId, end) %>% 
  rename(dttm=end)

dttmTeamComb %>% 
  inner_join(select(sim$teams, teamId, name), by="teamId") %>% 
  left_join(ptsTimeTable, by=c("dttm","teamId","name")) %>%  
  replace_na(list(estimate=0, conf.low=0, conf.high=0)) %>% 
  arrange(teamId, dttm) %>% 
  group_by(teamId) %>% 
  mutate(
    points=cumsum(estimate),
    conf.low = cumsum(conf.low),
    conf.high = cumsum(conf.high)) %>% 
  ungroup() %>% 
  mutate( dttm = fct_reorder(as.factor(dttm), dttm)) %>% 
  filter(teamId %in% c(1,14)) %>% 
  ggplot(aes(x=dttm, y=points, group=teamId, color=name)) +
  geom_line(size=1, linetype="dashed") +
  geom_line(aes(y=conf.low), linetype="dotted", size=.5) +
  geom_line(aes(y=conf.high), linetype="dotted", size=.5) +
  theme_minimal() +
  theme( axis.text.x = element_text(angle=45))
