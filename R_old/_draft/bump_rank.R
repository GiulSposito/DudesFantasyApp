library(tidyverse)
library(ggbump)

flights <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2022/2022-07-12/flights.csv') %>% 
  janitor::clean_names()


color_palette <- viridisLite::mako(8)
description_color <- 'grey40'
country_colors <- c(
  'United Kingdom' = color_palette[2],
  'Germany' = color_palette[3],
  'Spain' = color_palette[4],
  'France' = color_palette[5],
  'Italy' = color_palette[6], 
  'Türkiye' = color_palette[7]
)

country_flights_by_year <- flights %>% 
  select(year, state = state_name, flights = flt_tot_1) %>% 
  group_by(year, state) %>% 
  summarise(flights = sum(flights))

country_rank_by_year <- country_flights_by_year %>% 
  group_by(year) %>% 
  mutate(
    rank = row_number(desc(flights))
  ) %>% 
  ungroup() %>% 
  arrange(rank, year) 

max_rank <- 6
todays_top <- country_rank_by_year %>% 
  filter(year == 2022, rank <= max_rank) %>% 
  pull(state)


country_rank_by_year %>% 
  filter(state %in% todays_top) %>% 
  ggplot(aes(year, rank, col = state)) + 
  geom_point(stroke = .5) +
  geom_bump(size = 1) +
  scale_y_reverse(position = 'right', breaks = seq(16, 2, -2)) +
  scale_color_manual(values = country_colors) +
  # coord_cartesian(xlim = c(2014, 2022.5), ylim = c(6.5, 0.25), expand = F) +
  theme_light()

sim <- crossing(trail=1:20000,
         prob=seq(.05, 1, .05)) %>% 
  mutate(num_flips = rbinom(n(),4,prob),
         num_tail = rbinom(n(), num_flips, .5),
         set_free = num_flips>0 & num_tail==0)


sim %>% 
  group_by(prob) %>% 
  summarise(pct_free = mean(set_free)) %>% 
  ggplot(aes(x=prob, y=pct_free)) +
  geom_line() +
  theme_light()
