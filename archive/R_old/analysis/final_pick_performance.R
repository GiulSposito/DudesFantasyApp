library(tidyverse)
library(ggimage)
library(glue)
library(ggrepel)
library(teamcolors)

picks <- readRDS("./data/draft_picks.rds") %>% 
  select(round, pick, player.id, team.id)

points <- readRDS("./data/players_points.rds")

sim <- readRDS("./data/simulation_v5_week14_final.rds")

teams <- sim$teams %>% 
  select(team.id = teamId, team.name=name, teamImgUrl=imageUrl)


TEAMS_COLOR_SCALE <- c("#B3995D","black","#03202F","#0B2265","#fb9a99","#A5ACAF","#0085CA",
                       "#ff7f00","#203731","#6a3d9a","#A71930","#A71930","#FFB612","#004953")
  
seasonPts <- points %>% 
  filter(week==14) %>% 
  select(player.id=playerId, firstName, lastName, position, weekSeasonPts, playerImgUrl=smallImageUrl) %>% 
  arrange(desc(weekSeasonPts))


draft <- picks %>% 
  inner_join(teams, by = "team.id") %>% 
  inner_join(seasonPts, by = "player.id")


roundN <- 5
draft %>% 
  filter(round==roundN) %>% 
  ggplot(aes(y=weekSeasonPts, x=pick, fill=team.name)) +
  geom_image(aes(image=playerImgUrl), size=.055, nudge_y=47, asp=1.7) +
  geom_col(width = .4) +
  geom_text(aes(label=lastName), size=3.7, nudge_y=15, color="black") +
  geom_text(aes(label=weekSeasonPts), size=3, nudge_y=5, color="black") +
  geom_image(aes(y=0, image=teamImgUrl), size=.06, nudge_y=0, asp=1.3) +
  scale_fill_manual(values = TEAMS_COLOR_SCALE) +
  labs(title = glue("Pick Performance - Round #{roundN}"), 
       subtitle = "Total Fantasy Points in Regular Season",
       x="Pick Position", y="Points") +
  theme_light() +
  ylim(-5,70+max(pull(filter(draft, round==roundN),weekSeasonPts))) + 
  theme(legend.position = "none")

draft %>% 
  group_by(round) %>% 
  mutate(
    bestRoundPick = weekSeasonPts==max(weekSeasonPts),
    worstRoundPick = weekSeasonPts==min(weekSeasonPts)
  ) %>% 
  ungroup() %>% 
  ggplot(aes(x=pick, y=weekSeasonPts))+
  geom_line(color="darkgrey") +
  geom_text_repel(aes(color=team.name, label=if_else((bestRoundPick|worstRoundPick), glue("{lastName}({position}) - {team.name}"), as.character(NA))),
                  force_pull = .5, min.segment.length = 0, size=3) +
  scale_color_manual(values = TEAMS_COLOR_SCALE) +
  labs(title="Season Points x Picks", subtitle = "Best and Worst Picks in each round",
       x = "pick position", y="regular season fantasy points") +
  theme_minimal() +
  theme(legend.position = "none")
