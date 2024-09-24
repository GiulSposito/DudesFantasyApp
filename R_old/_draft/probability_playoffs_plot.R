library(googlesheets4)
library(tidyverse)
library(ggimage)
library(ggrepel)

# prbs_raw <- googlesheets4::read_sheet("1byZST8k0F4TZ8CkKM4v0lEBoltlK96PtFrIh4pLI74c")
prbs_raw <- googlesheets4::read_sheet("1cCwgiq_OHKpYmLy9tlpI8-h-u8_gwb9Yb_PcotyL7EU")



odds <- prbs_raw %>% 
  pivot_longer(-Week, names_to = "team", values_to = "probs") %>% 
  mutate( team = str_remove_all(team,"'"))

sim11 <- readRDS("./data/simulation_v5_week13_final.rds")

team_odds <- sim11$teams %>% 
  select(teamId, team=name, imageUrl, imageUrlLarge) %>% 
  inner_join(odds, by="team")


TEAMS_COLOR_SCALE <- c("#B3995D","black","#03202F","#0B2265","#fb9a99","#A5ACAF","#0085CA",
                       "#ff7f00","#203731","#6a3d9a","#A71930","#A71930","#FFB612","#004953")

team_odds %>% 
  mutate( imageUrl = if_else(Week==14, imageUrl, as.character(NA))) %>% 
  ggplot(aes(x=Week, y=probs)) +
  geom_line(aes(color=team), size=2, alpha=.4) +
  geom_image(aes(image=imageUrl), size=0.04) +
  geom_hline(yintercept=0.5, linetype="dashed", color="grey") +
  # geom_text(aes(label=if_else(Week==12, team, ""), color=team)) +
  geom_text_repel(aes(label=if_else(Week==14, team, ""), color=team), direction="y", nudge_x = 1, hjust="left") +
  scale_x_continuous(breaks = scales::pretty_breaks(), limits = c(1,18)) +
  scale_colour_manual(values = TEAMS_COLOR_SCALE) +
  theme_minimal() +
  theme( legend.position = "none" ) +
  labs(title="Playoff Probability", x="week", y="playoff probability")
  

