# junta os rosters dos times, estatíticas dos jogadores, a tabela de projecao e
# uma de-para de apreviacao do Injury Status
rosters <- sim$teams %>% 
  # unnest do roster por time
  select(teamId, teamName=name, rosters) %>% 
  unnest(rosters) %>%                                                         # 210 players
  # mapeamento ffa<->nfl
  inner_join(select(sim$players_id, id, playerId=nfl_id), by="playerId") %>%  # 210 players
  # statisticas dos jogadores
  inner_join(sim$players_stats, by="playerId") %>%                            # 210 players]
  # estatisticas podem ter mais de uma semana
  unnest(weekPts) %>%
  group_by(id, position) %>% 
  mutate( avgPts = mean(weekPts, na.rm=T) ) %>% 
  ungroup() %>% 
  filter(week == .week) %>% 
  # mapeamento da posicao do slot no roster
  left_join(rosterSlots, by="rosterSlotId") %>% 
  # adiciona abreviatura do injury game status
  left_join(readRDS("./data/injuryGameStatusAbbr.rds"), by = "injuryGameStatus") %>% 
  mutate( 
    full_name = case_when(
      !is.na(injuryGameStatus) ~ paste0(name, " (", injuryAbbr, ")"),
      is.na(injuryGameStatus) ~ name
    ),
    full_name = paste0(full_name, " [", rosterSlot ,"]")
  ) %>% 
  # campos de interesse
  select(week, id, playerId, full_name, teamId, teamName, name, pos=position, nflTeamAbbr, rosterSlot, 
         injuryGameStatus, isEditable, isReserveStatus=isReserveStatus.x, isUndroppable, 
         byeWeek, weekPts, avgPts, weekSeasonPts, rankAgainstPosition)

dudes_projections <- readRDS("./data/points_projection_and_errors.rds") %>% 
  inner_join(rosters, by = c("week", "id", "pos")) %>% 
  filter(week==.week, byeWeek!=.week) %>%
  select(season, week,id, name, full_name, pos, nflTeamAbbr, rankAgainstPosition, 
         teamId, teamName, byeWeek, injuryGameStatus, data_src, pts.proj, rosterSlot, isEditable, weekPts) %>% 
  mutate(adj_factor = case_when(
    is.na(injuryGameStatus) ~ 1,
    injuryGameStatus == "Questionable" ~ .5,
    injuryGameStatus == "Doubtful" ~ .25,
    T ~ 0
  )) %>% 
  mutate(pts.proj = pts.proj * adj_factor) %>% 
  nest(proj = c(data_src, pts.proj)) %>% 
  mutate( dudes.proj = map_dbl(proj, ~median(.x$pts.proj, na.rm = T)) ) %>% 
  mutate( pts.sim = map(proj, function(.dt,.n){
    
    if (all(.dt$pts.proj == .dt$pts.proj[1]))
      return(sample(.dt$pts.proj, .n, T))
    
    pdfden <- .dt %>%
      pull(pts.proj) %>%
      ecdf() %>%
      knots() %>%
      density(from = -10, to = 100)
    
    approx(cumsum(pdfden$y) / sum(pdfden$y),
           pdfden$x, runif(.n))$y %>%
      return()
    
  }, .n=SIMULATION_SIZE) )


## plot do grafico do roster
plotRoster <- function(.teamId, .rosterData) {
  
  plotData <- .rosterData %>%
    filter(teamId == .teamId,
           rosterSlot != "RES") %>%
    mutate(
      # fixa posicao e slot como fatores fixo para melhorar o gráfico
      pos = factor(pos, levels = posLevels),
      rosterSlot = factor(rosterSlot, levels = slotLevels)
    ) %>%
    # decide se em pontos deixa vazio (ainda nao jogou) ou coloca week points (já jogou)
    mutate(points = case_when(isEditable ~ as.numeric(NA),!isEditable ~ weekPts)) %>%
    arrange(rosterSlot, pos) %>%
    mutate(display.order = 1:nrow(.))
  
  plotData %>%
    unnest(proj) %>%
    ggplot(aes(
      x = pts.proj,
      y = reorder(full_name,-display.order),
      fill = pos
    )) +
    geom_density_ridges(scale = 2,
                        color = "white",
                        alpha = .7) +
    theme_ridges() +
    xlab("Fantasy Points") +
    ylab("") +
    theme(legend.position = "bottom") 
}
