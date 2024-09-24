library(tidyverse)
library(glue)
library(broom)
library(ggrepel)

draft <- readRDS("./data/draft_2022_picks.rds")

proj <- readRDS("./data/season_proj_stats.rds") %>% 
  filter( avg_type == "average" ) %>% 
  mutate( id = as.integer(id) )

# carregando tabelas de "de para" de IDs de Jogadores
load("../ffanalytics/R/sysdata.rda") # <<- Players IDs !!!
my_player_ids <- player_ids %>%
  mutate( id = as.integer(id), nfl_id = as.integer(nfl_id)) %>% 
  select( id, nfl_id )

draft_data <- draft %>% 
  rename( nfl_id = player.id ) %>% 
  inner_join(my_player_ids, by = "nfl_id") %>% 
  inner_join(proj, by = "id") %>% 
  select( round, pick, team.id, team.name, pos, first_name, last_name, team, 
          adp, floor, points, ceiling, everything())

# total de pontos por time
draftResult <- draft_data %>% 
  group_by(team.id, team.name) %>% 
  summarise(
    floor = sum(floor), 
    points = sum(points),
    ceiling = sum(ceiling),
    .groups = "drop"
  )

# sequencia dos picks
pickPosSeq <- draft_data %>% 
  select(round, team.id, team.name, pick, pos) %>% 
  group_by(team.id, team.name) %>% 
  nest() %>% 
  mutate( pickSeq = map_chr(data, function(picks){
    picks %>% 
      arrange(pick) %>% 
      pull(pos) %>% 
      str_c(collapse = ".") %>% 
      return()
  })) %>% 
  select(-data) %>% 
  ungroup()

# draft performace
sumPickPerf <- pickPosSeq %>% 
  select(-team.name) %>% 
  inner_join(draftResult, by="team.id") %>% 
  arrange(desc(points))

# força das posições de ataque
strengh_RBWR <- draft_data %>% 
  filter(pos %in% c("RB","WR")) %>% 
  group_by(team.id, team.name, pos) %>% 
  slice_max(points, n=2) %>% 
  summarise(
    pts = sum(points),
    flr = sum(floor),
    clg = sum(ceiling),
    .groups = "drop"
    # sumPts = sum(points),
    # sumFlr = sum(floor),
    # sumClg = sum(ceiling),
    # avgPts = mean(points),
    # avgFlr = mean(floor),
    # avgClg = mean(ceiling)
  ) %>% 
  arrange(pos) %>% 
  pivot_wider(id_cols = c(team.id, team.name),
              names_from = pos,
#              values_from=c(sumPts, sumFlr, sumClg, avgPts, avgFlr, avgClg))
              values_from=c(pts, flr, clg))

# força das posições de ataque
strengh_FLEX <- draft_data %>% 
  filter(pos %in% c("RB","WR")) %>% 
  group_by(team.id, team.name, pos) %>% 
  slice_max(points, n=3) %>% 
  group_by(team.id, team.name) %>% 
  slice_min(points, n=1) %>% 
  summarise(
    pts_FLEX = sum(points),
    flr_FLEX = sum(floor),
    clg_FLEX = sum(ceiling),
    .groups = "drop"
  ) %>% 
  arrange(desc(pts_FLEX))

# força das posições de ataque
strengh_QB <- draft_data %>% 
  filter(pos %in% c("QB")) %>% 
  group_by(team.id, team.name) %>% 
  slice_max(points, n=1) %>% 
  summarise(
    pts_QB = sum(points),
    flr_QB = sum(floor),
    clg_QB = sum(ceiling),
    .groups = "drop"
  ) %>% 
  arrange(desc(pts_QB))

# força das posições de ataque
strengh_TE <- draft_data %>% 
  filter(pos %in% c("TE")) %>% 
  group_by(team.id, team.name) %>% 
  slice_max(points, n=1) %>% 
  summarise(
    pts_TE = sum(points),
    flr_TE = sum(floor),
    clg_TE = sum(ceiling),
    .groups = "drop"
  ) %>% 
  arrange(desc(pts_TE))

strengh_RBWR %>% 
  select(-team.name) %>% 
  inner_join(pickPosSeq) %>% 
  select(team.id, team.name, pickSeq, RB=pts_RB, WR=pts_WR) %>% 
  inner_join(select(strengh_FLEX, team.id, FLEX=pts_FLEX), by="team.id") %>% 
  inner_join(select(strengh_QB, team.id, QB=pts_QB), by="team.id") %>% 
  inner_join(select(strengh_TE, team.id, TE=pts_TE), by="team.id") %>% 
  mutate( total = RB+WR+FLEX+QB+TE ) %>% 
  arrange(desc(total))


draft_data %>% 
  select(round, pick, player.name, pos, adp, floor, points, ceiling) %>% 
  filter( round <= 9) %>% 
  mutate( name = glue::glue("{player.name} ({pos})") ) %>% 
  mutate( name = fct_reorder(name, points) ) %>% 
  ggplot(aes(x=points, y=name, color=pos)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.2) +
  facet_grid(vars(round), scales = "free_y") +
  theme_light() +
  theme( axis.text.y = element_text(size=6) )

draft_data %>% 
  ggplot(aes(pick, adp, color=pos)) +
  geom_point() +
  #facet_wrap(~team.name) +
  theme_light()

draft_data %>% 
  filter(pick <= 14*9 ) %>% 
  ggplot(aes(pick, adp, color=pos)) +
  geom_point() +
  geom_smooth(method = "lm", se=F) +
  theme_light()


RBWR <- draft_data %>% 
  filter(pos %in% c("RB","WR")) %>% 
  group_by(team.id, pos) %>% 
  slice_max(points, n=2) %>% 
  summarise(
    pts = sum(points),
    flr = sum(floor),
    clg = sum(ceiling),
    .groups="drop"
  ) 


draft_data %>% 
  group_by(team.id, team.name, pos) %>% 
  nest() %>% 
  ungroup() %>% 
  mutate( lm = map(data, function(drft){
    lm(pick~adp, data=drft) %>% 
      tidy()
  })) %>% 
  unnest(lm) %>% 
  filter(p.value <= 0.05) %>% 
  arrange(desc(estimate)) %>% 
  inner_join(RBWR, by = c("team.id", "pos")) %>% 
  arrange(desc(estimate)) %>% 
  ggplot(aes(estimate, pts, color=pos)) +
  geom_point() +
  #geom_smooth() +
  theme_minimal()


draft_data %>% 
  group_by(team.id, team.name) %>% 
  summarise(
    floor = sum(floor), 
    points = sum(points),
    ceiling = sum(ceiling),
    .groups = "drop"
  ) %>% 
  arrange(team.id) %>% 
  mutate( autopick = c(F,T,T,F,F,F,T,T,F,T,F,T,F,T)) %>% 
  mutate( team.name = fct_reorder(team.name, points)) %>% 
  ggplot(aes(y=team.name, x=points, color=autopick)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.5) +
  theme_light()

pick_order <- draft_data %>% 
  filter(round==1) %>% 
  select(team.id, draft.position=pick)


draft_data %>% 
  group_by(team.id, team.name) %>% 
  summarise(
    floor = sum(floor), 
    points = sum(points),
    ceiling = sum(ceiling),
    .groups = "drop"
  ) %>% 
  arrange(team.id) %>% 
  mutate( autopick = c(F,T,T,F,F,F,T,T,F,T,F,T,F,T)) %>% 
  inner_join(pick_order, by="team.id") %>% 
  mutate( draft.order = glue("{team.name} #{draft.position}")) %>% 
  mutate( draft.order = fct_reorder(draft.order, draft.position)) %>% 
  ggplot(aes(y=draft.order, x=points, color=autopick)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.5) +
  theme_light() +
  theme( axis.text.x = element_text(angle=45, hjust = 1)) + 
  coord_flip()



pos_points <- draft_data %>% 
  group_by(round, pos) %>% 
  summarise(
    avg_floor = mean(floor), 
    avg_points = mean(points),
    avg_ceiling = mean(ceiling),
    .groups="drop"
  )

pos_points %>% 
  ggplot(aes(x=round, y=avg_points, color=pos)) +
  geom_point() +
  theme_light()

draft_data %>% 
  select(round, team.id, team.name, pos, player.name, floor, points, ceiling) %>% 
  inner_join(pos_points, by = c("round", "pos")) %>% 
  mutate( pick_strengh = points - avg_points  ) %>% 
  inner_join(pick_order, by = "team.id") %>% 
  mutate(team.name = fct_reorder(team.name, draft.position)) %>% 
  ggplot(aes(x=round, y=pick_strengh, fill=pos)) +
  geom_bar(stat="identity") +
  geom_hline(yintercept = 0 ) +
  geom_vline(xintercept = 9.5, linetype="dashed", color="grey") + 
  facet_wrap(~team.name) +
  theme_light()

#### performance dos picks

team.pickstrat <- draft_data %>%
  select(team.id, team.name) %>% 
  distinct() %>% 
  arrange(team.id) %>% 
  mutate( autopick = c(F,T,T,F,F,F,T,T,F,T,F,T,F,T))

pstats <- readRDS("./data/players_points.rds") 

playerPts <- pstats %>% 
  filter(week==1) %>% 
  select(playerId, week, weekPts)

draft_data %>% 
  select(round, pick, team.id, team, nfl_id, player.name, pos) %>% 
  inner_join(team.pickstrat, by="team.id") %>% 
  left_join(playerPts, by=c("nfl_id"="playerId")) %>%
  group_by(team.name, autopick) %>% 
  summarise(points=sum(weekPts, na.rm = T), .groups="drop") %>% 
  mutate(team.name=fct_reorder(team.name, points)) %>% 
  ggplot(aes(y=team.name, x=points, fill=autopick)) +
  geom_bar(stat="identity") +
  labs(title="Drafted Picks", subtitles="Fantasy Points Week 1 - all picks", y="team")+ 
  theme_light() +
  theme(legend.position = "bottom")

draft_data %>% 
  select(round, pick, team.id, team, nfl_id, player.name, pos) %>% 
  inner_join(team.pickstrat, by="team.id") %>% 
  left_join(playerPts, by=c("nfl_id"="playerId")) %>%
  group_by(round, team.name, autopick) %>% 
  summarise(points=sum(weekPts, na.rm = T), .groups="drop") %>% 
  group_by(round) %>% 
  mutate(team.name=fct_reorder(team.name, points)) %>% 
  ungroup() %>% 
  ggplot(aes(y=team.name, x=points, fill=autopick)) +
  geom_bar(stat="identity") +
  facet_wrap(~round, scales = "free") +
  labs(title="Drafted Picks", subtitles="Fantasy Points Week 1 - all picks", y="team")+ 
  theme_light() +
  theme(legend.position = "bottom")


sim <- readRDS("./data/simulation_v5_week1_final.rds")

aTeam <- sim$matchup_sim %>% 
  select(contains("teamId"), contains("totalPts")) %>% 
  select(contains("awayTeam")) %>% 
  set_names(c("team.id", "totalPts", "simPts"))

hTeam <- sim$matchup_sim %>% 
  select(contains("teamId"), contains("totalPts")) %>% 
  select(contains("homeTeam")) %>% 
  set_names(c("team.id", "totalPts", "simPts"))

bind_rows(aTeam, hTeam) %>% 
  inner_join(team.pickstrat) %>% 
  group_by(team.name, autopick) %>% 
  summarise(points=sum(totalPts, na.rm = T), .groups="drop") %>% 
  mutate(team.name=fct_reorder(team.name, points)) %>% 
  ggplot(aes(y=team.name, x=points, fill=autopick)) +
  geom_bar(stat="identity") +
  labs(title="Total Score", subtitles="Fantasy Points Week 1 - Starters", y="team")+ 
  theme_light() +
  theme(legend.position = "bottom")
  
  