# global parameters
options(dplyr.summarise.inform = FALSE) # Suppress summarise info

# devtools::install_github("FantasyFootballAnalytics/ffanalytics")
remotes::install_github("FantasyFootballAnalytics/ffanalytics")

### testing yahoo scrapping
# 1. log on http://football.fantasysports.yahoo.com
# 2. start a new ppr league
# 3. go to players page
# 4. copy new URL (the league id should changed ../f1/NNNNNN/ )
# 5. open network in chrome dev tools
# 6. copy the requested cookies to config
source("./R/import/scrap_yahoo_fantasy_projection.R")
config <- yaml::read_yaml("./config/config.yml")
scrapYahooProjection(.week = 0, .season = 2021, .yahooCookies = config$yahooCookies)


## ffanalytics full run

library(ffanalytics)

my_scrape <- scrape_data(pos = c("QB", "RB", "WR", "TE", "DST"),
                         season = 2022, week = 0)


my_projections <-  projections_table(my_scrape,scoring_rules = yaml::read_yaml("./config/score_settings.yml"))

library(magrittr)
proj_stats <- my_projections %>% 
  add_ecr() %>% 
  add_adp() %>% 
  add_aav() %>%
  add_uncertainty()

proj_info <- proj_stats %>% 
  add_player_info()

proj_info %>% View()

saveRDS(my_scrape, "./data/season_scrap.rds")
saveRDS(my_projections, "./data/season_projection.rds")
saveRDS(proj_info, "./data/season_proj_stats.rds")
