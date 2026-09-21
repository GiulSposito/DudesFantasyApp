library(tidyverse)
library(glue)

.team <- "Amparo Bikers"
.week <- 1

# dados dos jogadores
players <- readRDS(glue("./data/week{.week}_players_projections.rds")) %>% 
  filter(
    avg_type=="average",
    fantasy.team %in% c(.team,"*FreeAgent"),
    team!="FA",
    week==.week
  ) %>%  
  select(id, playerId=nfl_id, name, pos=position, team = nflTeamAbbr, week, weekPts, weekSeasonPts, teamId, fantasy.team, injuryGameStatus, rankAgainstPosition, byeWeek)

# projeção de dados "Dudes"
dudes_proj <- readRDS("./data/points_projection_and_errors.rds") %>% 
  filter(week==.week)

SIMULATION_SIZE = 1000

ptsproj <- dudes_proj %>% 
  nest(data=c(data_src, pts.proj)) %>% 
  mutate( pts.proj = map(data, function(.dt,.n){
  
    if(all(.dt$pts.proj == .dt$pts.proj[1])) return(sample(.dt$pts.proj, .n, T))
    
    # print(head(.dt))
    
    pdfden <- .dt %>% 
      pull(pts.proj) %>% 
      ecdf() %>% 
      knots() %>% 
      density(from=-10, to=100)
    
    approx( cumsum(pdfden$y)/sum(pdfden$y), 
            pdfden$x, runif(.n) )$y %>% 
      return()
    
  }, .n=SIMULATION_SIZE) )

pdfden <- ptsproj |> 
  filter(id==13116) |> 
  unnest(data, names_sep = "_") |> 
  pull(data_pts.proj) |> 
  ecdf() |> 
  knots() |> 
  density(from=-10, to=100)

approx( cumsum(pdfden$y)/sum(pdfden$y), 
        pdfden$x, runif(100) )$y |> 
  hist()

tibble( x=pdfden$x, y=pdfden$y ) |> 
  filter(y>.1) |> 
  ggplot(aes(x,y)) +
  geom_point() +
  theme_minimal()

ptsproj |> 
  unnest(pts.proj, names_sep="_")

players_proj <- players %>% 
  select(-week) %>% 
  inner_join(ptsproj, by=c("id","pos")) %>% 
  mutate( points  = map_dbl(pts.proj, quantile, probs=.5, na.rm=T),
          ceiling = map_dbl(pts.proj, quantile, probs=.8, na.rm=T),
          floor   = map_dbl(pts.proj, quantile, probs=.2, na.rm=T))


# injury_table <- readRDS(glue("./data/week{.week}_players_projections.rds")) %>% 
#   select(injuryGameStatus) %>% 
#   distinct() %>%
#   arrange(injuryGameStatus) %>% 
#   mutate( injuryFactor = case_when(
#     is.na(injuryGameStatus) ~ 1,
#     injuryGameStatus == "Questionable" ~ 0.5,
#     injuryGameStatus == "Doubtful" ~ 0.25,
#     T ~ 0
#   ))
# 
# players_proj <- players_proj %>% 
#   inner_join(injury_table, by = "injuryGameStatus") %>% 
#   mutate( injuryFactor = if_else(byeWeek==.week,0,injuryFactor)) %>% 
#   mutate( points  = injuryFactor*points,
#           ceiling = injuryFactor*ceiling,
#           floor   = injuryFactor*floor) 
# starts
starters <- tibble(
  pos=c("QB","RB","WR","TE","K","DST"),
  qtd=c(1,2,2,1,1,1)
) %>% 
  split(1:nrow(.)) %>% 
  map_df(function(.x, .players){
    .players %>% 
      filter(pos==.x$pos) %>%
      slice_max(points, n=.x$qtd)
  }, .players=players_proj)

starters <- players_proj %>% 
  filter(pos %in% c("WR","RB")) %>% 
  anti_join(starters, by=c("id","pos")) %>% 
  slice_max(points, n=1) %>% 
  bind_rows(starters,.)

## bench
bench <- tibble(
  pos=c("QB","RB","WR","TE"),
  qtd=c(1,2,2,1)
) %>% 
  split(1:nrow(.)) %>% 
  map_df(function(.x, .players){
    .players %>% 
      filter(pos==.x$pos) %>% 
      slice_max(points, n=.x$qtd)
  }, .players = anti_join(players_proj, starters, by=c("id","pos")) )

# releases
releases <- players_proj %>% 
  filter(fantasy.team==.team) %>% 
  anti_join(starters, by=c("id","pos")) %>% 
  anti_join(bench, by=c("id","pos"))

starters %>% select(id, name, pos, team, fantasy.team, rankAgainstPosition, byeWeek, floor, points, ceiling, weekPts, weekSeasonPts, injuryGameStatus)
bench  %>% select(id, name, pos, team, fantasy.team, rankAgainstPosition, byeWeek, floor, points, ceiling, weekPts, weekSeasonPts, injuryGameStatus)
releases %>% select(id, name, pos, team, fantasy.team, rankAgainstPosition, byeWeek, floor, points, ceiling, weekPts, weekSeasonPts, injuryGameStatus)

starters$pts.proj %>% reduce(`+`) %>% summary()
starters$weekPts %>% sum(na.rm = T)


