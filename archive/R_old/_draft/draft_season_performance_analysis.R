library(tidyverse)
library(ggrepel)
library(glue)

# escolhas dos times
draft_picks <- readRDS("./data/draft_2022_picks.rds")
players_stats <- readRDS("./data/players_points.rds")

# add player position to draft picks
draft_perf <- draft_picks %>% 
  inner_join(distinct(players_stats, playerId, position, smallImageUrl), by=c("player.id"="playerId"))

player_rank_season <- players_stats %>% 
  select(playerId, name,position,week, weekSeasonPts,smallImageUrl) %>% 
  group_by(position, week) %>% 
  mutate( rankSeasonPos = rank(-weekSeasonPts),
          labelRankSeasonPos = fct_reorder(paste0(position, floor(rankSeasonPos)), rankSeasonPos)) %>% 
  ungroup() 
  
player_rank_draft <- draft_perf %>% 
  group_by(team.id, position) %>% 
  slice_min(pick, n=2) %>% 
  ungroup() %>% 
  arrange(pick) %>% 
  group_by(position) %>% 
  mutate(
    rankDraftPos = rank(pick),
    labelRankDraftPos = paste0(position,rankDraftPos)
  ) %>% 
  ungroup()


rank_draft <- player_rank_draft %>%
  mutate(week=0, weekSeasonPts=0) %>% 
  select(round, pick, team.id, team.name, player.id, player.name, position, week, weekSeasonPts, rankPos=rankDraftPos, rankPosLabel=labelRankDraftPos, smallImageUrl)

rank_season <- player_rank_season %>% 
  inner_join(select(player_rank_draft, round, pick, player.id, player.name, team.id, team.name), by=c("playerId"="player.id")) %>%
  select(round, pick, team.id, team.name, player.id=playerId, player.name, position, week, weekSeasonPts, rankPos=rankSeasonPos, rankPosLabel=labelRankSeasonPos, smallImageUrl)

bind_rows(rank_draft,rank_season) %>% 
  filter(position=="RB", week %in% c(0,6)) %>% 
  ggplot(aes(x=week, y=-rankPos, color=team.name, 
             label=glue("{player.name} {rankPosLabel} ({round}.{pick})"),
             group=player.id)) +
  geom_point() +
  geom_line() +
  geom_text_repel(show.legend = F) +
  lims(y=c(-50,0), x=c(-2,8)) +
  theme_light() +
  theme(axis.text.y = element_blank())
  
bind_rows(rank_draft,rank_season) %>% 
  filter(position=="WR", week %in% c(0,6)) %>% 
  mutate( week = if_else(week==0, "draft", paste0("week",week)),
          rankPos = as.integer(floor(rankPos))) %>% 
  pivot_wider(id_cols = c(round, pick, team.name, player.name), names_from = "week", values_from = "rankPos") %>% 
  mutate( rankDiff = draft - week6 ) %>% View()


draft_picks



players_stats %>% 
  filter(week==7) %>% 
  select(playerId, position, weekSeasonPts, injuryGameStatus) %>% 
  inner_join(draft_picks, by=c("playerId"="player.id")) %>% 
  group_by(round) %>% 
  slice_max(weekSeasonPts, n=1) %>% 
  ungroup() %>% 
  filter(round <= 10) %>%
  inner_join(readRDS("./data/injuryGameStatusAbbr.rds"), by = "injuryGameStatus") %>% 
  mutate( injuryAbbr=if_else(is.na(injuryAbbr),"",injuryAbbr) ) %>% 
  arrange(round) %>% 
  select(round, pick, player.name, pos=position, pts=weekSeasonPts, team=team.name, st = injuryAbbr) %>% 
  View()

readRDS("./data/injuryGameStatusAbbr.rds")


