library(tidyverse)
library(ffanalytics)
library(magrittr)

my_scrape <- scrape_data(pos = c("QB", "RB", "WR", "TE", "DST", "K"),
                         season = 2023, week = 0)


my_projections <-  projections_table(my_scrape,scoring_rules = yaml::read_yaml("./config/score_settings.yml"))
proj_stats <- add_ecr(my_projections)
proj_stats <- add_adp(proj_stats) 
proj_stats <- add_aav(proj_stats)
proj_stats <- add_uncertainty(proj_stats)

proj_info <- proj_stats %>% 
  add_player_info()

saveRDS(my_scrape, "./data/season_scrap.rds")
saveRDS(my_projections, "./data/season_projection.rds")
saveRDS(proj_info, "./data/season_proj_stats.rds")

my_scrape <- readRDS("./data/season_scrap.rds")
my_projections <- readRDS("./data/season_projection.rds")
proj_info <- readRDS("./data/season_proj_stats.rds")

proj_info %>% 
  filter(avg_type=="average") %>% 
  arrange(desc(points_vor)) %>% 
  select(position, first_name, last_name, team, age, rank, tier, uncertainty, points, everything()) %>% 
  slice_max(points_vor, n=30) %>% 
  ggplot(aes(x=points_vor, y=-rank, color=uncertainty)) +
  geom_point() +
  geom_text(aes(x=ceiling_vor,label=paste0(first_name, " ", last_name))) +
  geom_errorbarh(aes(xmax=ceiling_vor, xmin=floor_vor)) +
  theme_light()

proj_info %>% 
  filter(avg_type=="average") %>% 
  select(position, first_name, last_name, team, age, rank, tier, points, points_vor, uncertainty, everything()) %>% 
  arrange( desc(points_vor) ) %>% 
  View("draft list")


proj_info %>% 
  filter(avg_type=="average", pos=="RB") %>%
  slice_max(points_vor, n=30) %>% 
  arrange(desc(points_vor)) %>% 
  mutate(display.order=1:nrow(.), tier=as.factor(tier)) %>% 
  ggplot(aes(x=reorder(paste0(first_name, " ", last_name, " (", team, ")"), -display.order), color=tier)) +
    geom_pointrange(aes(y=points, ymin=floor, ymax=ceiling), size=.5) +
    # geom_label(aes(y=med, label=round(med,1)), size = 3,
    #            label.padding = unit(0.15, "lines"), show.legend = F) +
    xlab("") +
    ylab("Season Projected Fantasy Points (FPPR)") +
    labs(title = "Running Backs (top 30)", 
         subtitle = "Src: CBS, FantasyPros, FantasySharks, FFToday, NumberFire, NFL, RTSports, WalterFootball") +
    coord_flip() +
    theme_minimal() +
    theme(axis.text.y = element_text(size=10)) 

# legend.position = "bottom",

my_scrape[["TE"]] %>% 
  select(data_src) %>% 
  distinct() %>% 
  pull %>% 
  paste(collapse = ", ")


############


fgw <- readxl::read_xlsx("./static/exports/2021/fgw_week_final.xlsx") %>% 
  select(-1)

# starters: QB, WR, WR, RB, RB, TE, K, DST, WR/RB = 9

# frequencia em que a posicao fez diferença
# quantas vezes a posição estava entre os 9 com mais FGW na semana
fgw %>% 
  group_by(week) %>% 
  slice_max(fgw, n=9) %>% 
  ungroup() %>% 
  count(position, sort=T) %>% 
  mutate( odds = n/9 )

# Comportamento por posição e round

proj_info %>% 
  filter(avg_type=="average") %>% 
  select(id, pos, first_name, last_name, team, everything()) %>% 
  arrange(desc(points)) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  select(round, everything()) %>% 
  group_by(round, pos) %>% 
  summarise( rnd_pos_avg_pts = sum(points)) %>% 
  ggplot(aes(x=round, y=rnd_pos_avg_pts, color=pos)) +
  geom_point() +
  geom_line() +
  theme_minimal()

proj_info %>% 
  filter(avg_type=="average") %>% 
  ggplot(aes(points_vor, pos_ecr, color=pos)) +
  geom_point() +
  theme_minimal()


proj_info %>% 
  filter(avg_type=="average") %>% 
  select(id, pos, first_name, last_name, team, everything()) %>% 
  arrange(adp) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  group_by(round, pos) %>% 
  summarise( rnd_pos_avg_pnts = sum(points) ) %>% 
  ungroup() %>% 
  group_by(pos) %>% 
  arrange(pos, round) %>% 
  mutate( acc_points = cumsum(rnd_pos_avg_pnts)) %>% 
  mutate( dev = lead(acc_points)-acc_points ) %>% 
  ggplot(aes(x=round, y=acc_points, color=pos)) +
  geom_point() + 
  geom_line() +
  theme_minimal()

#### quais os starters que serão draftados?

# fixed positions in the lineup
line_up <- tibble(
  pos = c("QB", "WR", "RB", "TE", "K", "DST"),
  qtd = c(1,2,2,1,1,1)
)

blacklist <- c(15697,15694,15692,15840,15794,15873,9902, 10868, 15882,13909)

# tanking the AVERAGE PROJECTION
proj_stats <- proj_info %>% 
  filter(avg_type=="average") %>% 
  filter( !(id %in% blacklist) ) %>% 
  select(id, pos, first_name, last_name, team, everything())

# get the best players for each fixed position to be drafted
starts_fixed <- line_up %>% 
  split(1:nrow(.)) %>% 
  map_df(function(slot,stats){
    proj_stats %>% 
      filter(pos==slot$pos) %>% 
      # using ADP as criteria
      slice_max(-adp, n=14*slot$qtd) %>% 
      return()
  }, stats = proj_stats)

# geting the best remaining players to the flex position 
starts_flex <- proj_stats %>% 
  anti_join(starts_fixed, by="id") %>% 
  filter(pos %in% c("WR","RB")) %>% 
  slice_max(-adp, n=14) %>% 
  mutate( pos = "W/R")

# all players drafted
drafted_starters <- bind_rows(starts_fixed, starts_flex)

# total fantasy season points for position
season_points <- drafted_starters %>% 
  group_by(pos) %>% 
  summarise( season_points = sum(points))

# lets see how the availability of season points drop of each draf position
drafted_starters %>% 
  inner_join(season_points, by="pos") %>% 
  arrange(adp) %>% 
  select(id, pos, first_name, last_name, adp, points, season_points) %>% 
  group_by(pos) %>% 
  mutate( acc_points = cumsum(points) ) %>% 
  ungroup() %>% 
  mutate( drop_off = season_points-acc_points) %>% 
  ggplot(aes(adp, drop_off, color=pos)) +
  geom_point() +
  geom_line() +
  theme_minimal()

# average points for position in each round
drafted_starters %>% 
  inner_join(season_points, by="pos") %>% 
  arrange(adp) %>% 
  select(id, pos, first_name, last_name, adp, points, season_points) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  group_by(round, pos) %>% 
  summarise( avg_points = mean(points),
          max_points = max(points), 
          min_points = min(points)) %>% 
  ungroup() %>% 
  ggplot(aes(round, avg_points, color=pos)) +
  geom_point() +
  geom_line() +
  # geom_errorbar(aes(ymin=min_points, ymax=max_points)) +
  theme_minimal()


# qual estratégia maximiza o total de pontos?
round_points <- drafted_starters %>% 
  arrange(adp) %>% 
  select(id, pos, first_name, last_name, adp, points) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  group_by(round, pos) %>% 
  summarise( avg_points = mean(points),
             max_points = max(points), 
             min_points = min(points), .groups = "drop") 


# strategias
strat_points <- expand_grid(
  round = 1:9,
  pos = unique(drafted_starters$pos)
) %>% 
  inner_join(round_points, by=c("round", "pos"))

strats <- tibble(
  strat_id = rep(1:1000000,each=9),
  round = rep(1:9, 1000000),
  pos   = unlist(map(1:1000000, ~sample(c("RB","WR","RB", "WR", "QB", "W/R", "TE", "K", "DST"),9)))
)

expand.grid(
  round = 1:9,
  pos = c("RB","WR","RB", "WR", "QB", "W/R", "TE", "K", "DST")
)

strats %>% 
  filter(strat_id==37281)
strats %>% 
  inner_join(strat_points) %>% 
  group_by(strat_id) %>% 
  summarise( pts = sum(avg_points), 
             min = sum(min_points),
             max = sum(max_points),
             n = n()) %>% 
  ungroup() %>% 
  filter(n==9) %>% 
  arrange(desc(pts))


tibble(
  strat_id = rep(1:9,each=9),
  round = rep(1:9, 9),
  pos=c(
    "RB","WR","RB", "WR", "QB", "W/R", "TE", "K", "DST", # 
    "WR","RB","WR", "RB", "QB", "W/R", "TE", "K", "DST",
    "RB","RB","WR", "WR", "QB", "W/R", "TE", "K", "DST", #
    "WR","WR","RB", "RB", "QB", "W/R", "TE", "K", "DST",
    "WR","RB","RB", "WR", "QB", "W/R", "TE", "K", "DST", #
    "RB","WR","WR", "RB", "QB", "W/R", "TE", "K", "DST",
    "RB","TE","RB", "WR", "WR", "QB", "W/R", "K", "DST",
    "RB","RB","WR", "QB", "WR", "W/R", "TE", "K", "DST", #
    "WR","RB","RB", "QB", "WR", "W/R", "TE", "K", "DST"  #
  )) %>% 
  inner_join(strat_points) %>% 
  group_by(strat_id) %>% 
  summarise( pts = sum(avg_points), 
             min = sum(min_points),
             max = sum(max_points),
             n = n())
tibble(
  round = c(1:9),
  pos   = c("QB","WR","WR","RB","RB","TE","W/R","K","DST")
) %>% 
  inner_join(round_points) %>% 
  summarise( pts = sum(avg_points), 
             min = sum(min_points),
             max = sum(max_points))


slot_comb <- gtools::permutations(n=9, r=9, v=c("QB","WR","WR","RB","RB","TE","W/R","K","DST"), set=F) %>% 
  as_tibble() %>% 
  distinct() %>% 
  mutate(strat_id=1:nrow(.))

strats <- slot_comb %>% 
  pivot_longer(cols = 1:9, names_to="round", values_to = "pos") %>% 
  mutate( round = as.integer(str_remove(round,"V")))

draft_seq <- strats %>% 
  nest(data=c(round,pos)) %>% 
  mutate( draft_seq = map_chr(data, function(dt){
    paste(dt$pos, collapse = ".")
  })) %>% 
  select(-data)

strats  %>% 
  inner_join(round_points, by = c("round", "pos")) %>% 
  group_by(strat_id) %>% 
  summarise( pts = sum(avg_points), 
             min = sum(min_points),
             max = sum(max_points),
             n = n()) %>% 
  filter( n==9 ) %>% 
  inner_join(draft_seq, by="strat_id") %>% 
  slice_max(pts, n=20) %>% 
  mutate(draft_seq = fct_reorder(draft_seq, pts, median)) %>% 
  ggplot(aes(y=draft_seq, x=pts)) +
  geom_errorbarh(aes(xmin=min, xmax=max)) +
  geom_point() +
  theme_minimal()

#Best Approach
#   
# Round 1-5: WRs e RB2 e TEs
# Round 6-9: QB, W/R, K, DST

projs <- proj_info %>% 
  filter(avg_type=="average") %>% 
  select(id, pos, first_name, last_name, team, everything())

tibble(
  pos = c("WR", "RB", "TE"),
  qtd = c(28,28,14)
) %>% 
  split(1:nrow(.)) %>% 
  map_df(function(slot, stats){
    stats %>% 
      filter( pos==slot$pos ) %>% 
      slice_max(points_vor, n=slot$qtd) %>% 
      return()
  }, stats=projs) %>% 
  arrange(desc(points_vor))

tibble(
  pos = c("QB", "K", "DST"),
  qtd = c(14,14,14)
) %>% 
  split(1:nrow(.)) %>% 
  map_df(function(slot, stats){
    stats %>% 
      filter( pos==slot$pos ) %>% 
      slice_max(points_vor, n=slot$qtd) %>% 
      return()
  }, stats=projs) %>% 
  arrange(desc(points_vor))

##### Draft Monte Carlo Simulation

# definindo as estratégias de picks

## estrategias de draft
strats <- gtools::permutations(n=9, r=9, v=c("QB","WR","WR","RB","RB","TE","W/R","K","DST"), set=F) %>% 
  as_tibble() %>% 
  distinct() %>% 
  mutate(strat_id=1:nrow(.))

## picks das estratégias
strat_picks <- strats %>% 
  pivot_longer(cols = 1:9, names_to="round", values_to = "pos") %>% 
  mutate( round = as.integer(str_remove(round,"V")))

## label das estratégias
strat_labels <- strat_picks %>% 
  nest(data=c(round,pos)) %>% 
  mutate( draft_seq = map_chr(data, function(dt){
    paste(dt$pos, collapse = ".")
  })) %>% 
  select(-data)

strats
strat_picks
strat_labels

# qual starters será selecionado em qual round

## FIXED positions in the lineup
line_up <- tibble(
  pos = c("QB", "WR", "RB", "TE", "K", "DST"),
  qtd = c(1,2,2,1,1,1)
)

projs %>% 
  filter( pos == "RB" ) %>% 
  arrange(adp) %>% 
  View()

blacklist <- c(15697, 1569, 15692, 13113, 13424, # QBs low proj
               15240, # trey lance
               15840, 15794, 15873, 9902, 15798,  # TEs low proj
               15761) # WR low proj
#                12625, 13130, 13604 ) # Zeke, CMC e Barkley
# blacklist <- c()
               
# tanking the AVERAGE PROJECTION
proj_stats <- proj_info %>% 
  filter(avg_type=="average") %>% 
  filter( !(id %in% blacklist) ) %>% 
  select(id, pos, first_name, last_name, team, everything())

# get the best players for each FIXED position to be drafted
starts_fixed <- line_up %>% 
  split(1:nrow(.)) %>% 
  map_df(function(slot,stats){
    proj_stats %>% 
      filter(pos==slot$pos) %>% 
      # using ADP as criteria
      slice_min(adp, n=14*slot$qtd) %>% 
      return()
  }, stats = proj_stats)

# geting the best remaining players to the FLEX position 
starts_flex <- proj_stats %>% 
  anti_join(starts_fixed, by="id") %>% 
  filter(pos %in% c("WR","RB")) %>% 
  slice_min(adp, n=14) %>% 
  mutate( pos = "W/R")

# all players drafted
drafted_starters <- bind_rows(starts_fixed, starts_flex) %>% 
  arrange(adp)

# defining the round pick position
round_picks <- drafted_starters %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  select( round, everything() )

# MONTE CARLO
pickables <- strat_picks %>%  
  inner_join(select(round_picks, round, pos, id), by = c("round", "pos"))

valid_strats <- pickables %>% 
  select(strat_id, round, pos) %>% 
  distinct() %>% 
  count(strat_id) %>% 
  filter(n==9) %>% 
  select(-n)

sim_results <- pickables %>% 
  inner_join(valid_strats, by="strat_id") %>% 
  group_by(strat_id, round, pos) %>% 
  nest( ids = id ) %>% 
  ungroup() %>% 
  mutate( id_set = map(ids, function(.id) .id$id) ) %>% 
  mutate( simulation = map(id_set, function(.set){
    sample(.set, 1000, replace=T)
  })) %>% 
  select(strat_id, round, pos, simulation) %>% 
  unnest( simulation ) %>% 
  rename( id=simulation ) %>% 
  mutate( id_sim = rep(1:1000, nrow(.)/1000) ) %>% 
  inner_join( drafted_starters, by=c("id","pos") ) %>% 
  select(strat_id, round, pos, id_sim, id, points ) %>% 
  group_by(strat_id, id_sim) %>% 
  summarise(
    n = n(),
    points = sum(points)
  ) %>%
  nest(sim_raw_result = c(id_sim, n, points)) %>% 
  mutate( sim_stats = map(sim_raw_result, function(.simres){
    .simres$points %>% 
      t.test() %>% 
      broom::tidy() %>% 
      return()
  })) %>% 
  ungroup() %>% 
  unnest(sim_stats) %>% 
  select(strat_id, points = estimate, low=conf.low, high=conf.high)

sim_results %>% 
  inner_join(strat_labels, by="strat_id") %>% 
  slice_max(points, n=30) %>% 
  mutate( draft_seq = fct_reorder(draft_seq, points)) %>% 
  arrange(desc(points)) %>% 
  ggplot(aes(x=points, y=draft_seq)) +
  geom_point() +
  geom_errorbarh(aes(xmin=low, xmax=high), size=.3) +
  theme_light()

###### FINAL DRAFT ORDER ######
#
# STARTERS
# RANK BY ADP
# SLOTS: RB, TE, RB, WR, WR, QB, W/R, K, DST
# 2016. 2014. 2019. RB.TE.RB.WR.WR.QB.W/R.K.DST
# 
# 40825  2010. 2008. 2013. RB.TE.WR.WR.RB.QB.W/R.K.DST
# 

RB1
TEWR1
TEWR2RB2
TE 
QB
FLEX


genDraftPicks <- function(.dataset, .pos, .num){
  .dataset %>% 
    filter( avg_type=="average" ) %>% 
    select(id, pos, first_name, last_name, team, everything()) %>% 
    select(1:5, adp, pos_ecr, points_vor, floor, points, ceiling) %>% 
    filter( pos %in% .pos) %>% 
    slice_max(points, n=.num) %>% 
    mutate(name = glue::glue("{first_name} {last_name} {pos} ({team})")) %>% 
    mutate(name = fct_reorder(name, points)) %>% 
    arrange(desc(points)) %>%  
    return()
}

RB1 <- genDraftPicks(proj_info, "RB", 14)

TEWR1 <- proj_info %>% 
  anti_join(select(RB1, id, pos), by = c("id", "pos")) %>% 
  genDraftPicks(c("WR", "TE"), 28)

TERB2WR2 <- proj_info %>% 
  anti_join(select(RB1, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(TEWR1, id, pos), by = c("id", "pos")) %>% 
  genDraftPicks(c("WR", "RB", "TE"), 2*14)

QB <- proj_info %>% 
  genDraftPicks(c("QB"), 14)

FLEX <- proj_info %>% 
  anti_join(select(RB1, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(TEWR1, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(TERB2WR2, id, pos), by = c("id", "pos")) %>% 
  genDraftPicks(c("WR", "RB"), 14)

K <- genDraftPicks(proj_info, "K", 14)
DST <- genDraftPicks(proj_info, "DST", 14)

bind_rows(RB1, TEWR1, TERB2WR2, QB, FLEX, K, DST) %>% 
  mutate( rank=1:nrow(.) ) %>% 
  mutate( name = glue::glue("{first_name} {last_name} {pos} ({team})") ) %>% 
  mutate( name = fct_reorder(name, -rank)) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  ggplot(aes(x=points, y=name, color=pos)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.2) +
  facet_grid(vars(round), scales = "free_y") +
  theme_light() +
  theme(axis.text.y = element_text(size=5)) +
  labs(facet="round")

proj_info %>% 
  filter( avg_type=="average" ) %>% 
  select(id, pos, first_name, last_name, team, everything()) %>% 
  select(1:5, adp, pos_ecr, points_vor, floor, points, ceiling) %>% 
  filter( pos %in% c("RB", "WR", "TE")) %>% 
  slice_min(adp, n=14*3) %>% 
  mutate(name = glue::glue("{first_name} {last_name} {pos} ({team})")) %>% 
  mutate(name = fct_reorder(name, points)) %>% 
  arrange(desc(points)) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  ggplot(aes(x=points, y=name, color=pos)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.2) +
  facet_grid(vars(round), scales = "free_y") +
  theme_light() +
  theme(axis.text.y = element_text(size=6)) +
  labs(facet="round")



proj_info %>% 
  filter( avg_type=="average" ) %>% 
  select(id, pos, first_name, last_name, team, everything()) %>% 
  anti_join(select(RB1, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(TEWR1, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(TEWR2RB2, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(QB, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(FLEX, id, pos), by = c("id", "pos")) %>% 
  anti_join(select(TE, id, pos), by = c("id", "pos")) %>% 
  select(1:5, adp, pos_ecr, points_vor, floor, points, ceiling) %>% 
  slice_max(points, n=14) %>% 
  mutate(name=paste(first_name, last_name, pos, sep=" ")) %>% 
  mutate(name = fct_reorder(name, floor)) %>% 
  ggplot(aes(x=points, y=name)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.2) +
  theme_light()


draft_list <- bind_rows(RB1, TEWR1, TEWR2RB2, TE, QB, FLEX) %>% 
  mutate( rank = 1:nrow(.) ) %>% 
  mutate( name = glue::glue("{first_name} {last_name} {pos} ({team})") ) %>% 
  mutate( name = fct_reorder(name, -rank))

saveRDS(draft_list, "./data/bikers_draft_list.rds")

bind_rows(RB1, TEWR1, TEWR2RB2, TE, QB, FLEX) %>% 
  mutate( rank=1:nrow(.) ) %>% 
  mutate( name = glue::glue("{first_name} {last_name} {pos} ({team})") ) %>% 
  mutate( name = fct_reorder(name, -rank)) %>% 
  mutate( round = rep(1:nrow(.),each=14)[1:nrow(.)] ) %>% 
  ggplot(aes(x=points, y=name, color=pos)) +
  geom_point() +
  geom_errorbarh(aes(xmin=floor, xmax=ceiling), size=.2) +
  facet_grid(vars(round), scales = "free_y") +
  theme_light() +
  labs(facet="round")

RB OK
TE
WR
WR
RB KO
QB
FLEX
K
DST


