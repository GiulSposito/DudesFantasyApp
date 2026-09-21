### teste space

library(ffanalytics)
load("../ffanalytics/R/sysdata.rda") # <<- Players IDs !!!

espn2ffa_ids <- espn_getEspn2FfaIds(player_ids)
espnRaw <- espn_srapeCurrWeekProj()
espnScrape <- espn_rawToFfaScrap(espnRaw, espn2ffa_ids, .week=3, .season=2022)

webScrape <- readRDS("./data/weekly_webscraps_3.rds")

allScrapes <- espn_InjectScrap(espnScrape, webScrape)

allScrapes %>% 
  map_df(~select(.x, data_src, team, id), .id="pos") %>% 
  count(data_src, pos) %>% 
  pivot_wider(names_from = "pos",values_from="n")

projections_table( allScrapes, yaml::read_yaml("./config/score_settings.yml")) %>% filter(pos=="DST")
projections_table( webScrape, yaml::read_yaml("./config/score_settings.yml")) %>% filter(pos=="DST")

allScrapes[["QB"]] %>% 
  arrange(id) %>% 
  select(data_src, id, src_id, player, pos, everything()) %>% 
  View()

# saveRDS(allScrapes,"./data/weekly_webscraps_3.rds")

#   filter(pos %in% c("K")) %>%
#   arrange(desc(appliedTotal)) %>%
#   head(50) %>%
#   select(fullName, pos, stats) %>%
#   unnest(stats) %>%
#   pivot_wider(id_cols=c(fullName, pos), names_from = statId, values_from = value) %>%
#   arrange(desc(appliedTotal)) %>%
#   xlsx::write.xlsx("./static/exports/espn_players_proj.xlsx", showNA = F)
# 
# 
# map(ffanalytics::projection_sources, function(src){
#   print(src$base)
#   print(src$stat_cols)
# })
# 
# glimpse(ffanalytics::projection_sources[["ESPN"]])
# 
# kicker_stats <- tibble(
#   colName = names(ffanalytics::projection_sources[["CBS"]]$stat_cols),
#   shortName = ffanalytics::projection_sources[["CBS"]]$stat_cols,
#   janName   = janitor::make_clean_names(shortName)
# ) %>% 
#   filter(str_detect(colName, "fg") | str_detect(colName, "xp"))
# 
# stat_ids %>% 
#   bind_rows(kicker_stats) %>% 
#   as_tibble() %>% 
#   xlsx::write.xlsx("./static/exports/espn_stat_ids_kicker.xlsx")
# 
# 
# 
# data$players$player[1,]$stats[[1]]$stats %>% 
#   pivot_longer(everything(), names_to = "statId", values_to = "value")
#   
# 
# QB:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# RB:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[2]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# WR:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[4]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# TE:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[6]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# DST: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[16]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# K:   {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[17]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# 
# 
# 
# # URL Call - Page 2
# curl 'https://fantasy.espn.com/apis/v3/games/ffl/seasons/2022/segments/0/leaguedefaults/3?scoringPeriodId=0&view=kona_player_info' \
# -H 'authority: fantasy.espn.com' \
# -H 'accept: application/json' \
# -H 'accept-language: pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7' \
# -H 'cookie: region=unknown; _dcf=1; SWID=f3f130db-eb28-41fb-8b69-13de6604f5d7; _fbp=fb.1.1663242834846.1795890146; s_ensCDS=0; AMCVS_EE0201AC512D2BE80A490D4C%40AdobeOrg=1; IR_gbd=espn.com; _cb=DPSbxADRQiJeBskUtj; s_ecid=MCMID%7C67382231223866423640793098928952453895; AMCV_EE0201AC512D2BE80A490D4C%40AdobeOrg=-330454231%7CMCIDTS%7C19251%7CMCMID%7C67382231223866423640793098928952453895%7CMCAAMLH-1663847636%7C4%7CMCAAMB-1663847636%7CRKhpRz8krg2tLO6pguXWp5olkAcUniQYPHaMWWgdJ3xzPWQmdj0y%7CMCOPTOUT-1663250036s%7CNONE%7CMCAID%7CNONE%7CvVersion%7C3.1.2; s_c24_s=First%20Visit; s_cc=true; __gads=ID=eb9f779c1cd22cc7:T=1663242837:S=ALNI_MZt6mzCNj-p00pamb5PCEI3TqFTkQ; __gpi=UID=0000096a285811cb:T=1663242837:RT=1663242837:S=ALNI_MYyGccRpbDli0J1Nq3mJ4twLFTu1g; espngptCreative6108598067=1; trc_cookie_storage=taboola%2520global%253Auser-id%3Daa427a7a-f68c-430d-9b47-5af57c943f01-tuct8966a26; country=br; country=br; _ga=GA1.1.240750933.1663242838; _cc_id=341c2f2ade1fc9a5b916eebb1e538fa4; panoramaId_expiry=1663847640231; panoramaId=82b34dfa0bbbcb3919500044ed9f4945a7028f287cb98cd41b533118532df32e; _cb_svref=https%3A%2F%2Ffantasy.espn.com%2Ffootball%2Fplayers%2Fprojections; s_gpv_pn=fantasy%3Afootball%3Aleague%3Atoolsprojections; _chartbeat2=.1663242837578.1663244937272.1.BkhOtWCPzv4lDOIaoCVZFa6DO69hr.2; IR_9070=1663244937396%7C0%7C1663244937396%7C%7C; _ga_TNVCMNW09Q=GS1.1.1663244900.2.1.1663244938.0.0.0; s_c6=1663244938429-Repeat; s_c24=1663245329602; s_sq=wdgespcom%252Cwdgespge%3D%2526pid%253Dfantasy%25253Afootball%25253Aleague%25253Atoolsprojections%2526pidt%253D1%2526oid%253Dhttps%25253A%25252F%25252Ffantasy.espn.com%25252Ffootball%25252Fplayers%25252Fprojections%252523%2526ot%253DA; _chartbeat5=757|2758|%2Ffootball%2Fplayers%2Fprojections|https%3A%2F%2Ffantasy.espn.com%2Ffootball%2Fplayers%2Fprojections|C9H6LOqeJqRBaPK6KB4sSAlD6LNYh||c|4gMvtBfUDkJDW8za8CrJBvLgqdlC|espn.com|' \
# -H 'if-none-match: W/"0e0c26bcfbdb699ca5a96dd9f73549d6e"' \
# -H 'referer: https://fantasy.espn.com/football/players/projections' \
# -H 'sec-ch-ua: "Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"' \
# -H 'sec-ch-ua-mobile: ?0' \
# -H 'sec-ch-ua-platform: "macOS"' \
# -H 'sec-fetch-dest: empty' \
# -H 'sec-fetch-mode: cors' \
# -H 'sec-fetch-site: same-origin' \
# -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36' \
# -H 'x-fantasy-filter: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":50,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}' \
# -H 'x-fantasy-platform: kona-PROD-d2ecbc57dbf77c440f3be7ff68dccec940f0e115' \
# -H 'x-fantasy-source: kona' \
# --compressed
# 
# # URL call Page 1
# curl 'https://fantasy.espn.com/apis/v3/games/ffl/seasons/2022/segments/0/leaguedefaults/3?scoringPeriodId=0&view=kona_player_info' \
# -H 'authority: fantasy.espn.com' \
# -H 'accept: application/json' \
# -H 'accept-language: pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7' \
# -H 'cookie: region=unknown; _dcf=1; SWID=f3f130db-eb28-41fb-8b69-13de6604f5d7; _fbp=fb.1.1663242834846.1795890146; s_ensCDS=0; AMCVS_EE0201AC512D2BE80A490D4C%40AdobeOrg=1; IR_gbd=espn.com; _cb=DPSbxADRQiJeBskUtj; s_ecid=MCMID%7C67382231223866423640793098928952453895; AMCV_EE0201AC512D2BE80A490D4C%40AdobeOrg=-330454231%7CMCIDTS%7C19251%7CMCMID%7C67382231223866423640793098928952453895%7CMCAAMLH-1663847636%7C4%7CMCAAMB-1663847636%7CRKhpRz8krg2tLO6pguXWp5olkAcUniQYPHaMWWgdJ3xzPWQmdj0y%7CMCOPTOUT-1663250036s%7CNONE%7CMCAID%7CNONE%7CvVersion%7C3.1.2; s_cc=true; __gads=ID=eb9f779c1cd22cc7:T=1663242837:S=ALNI_MZt6mzCNj-p00pamb5PCEI3TqFTkQ; __gpi=UID=0000096a285811cb:T=1663242837:RT=1663242837:S=ALNI_MYyGccRpbDli0J1Nq3mJ4twLFTu1g; espngptCreative6108598067=1; trc_cookie_storage=taboola%2520global%253Auser-id%3Daa427a7a-f68c-430d-9b47-5af57c943f01-tuct8966a26; country=br; country=br; _ga=GA1.1.240750933.1663242838; _cc_id=341c2f2ade1fc9a5b916eebb1e538fa4; panoramaId_expiry=1663847640231; panoramaId=82b34dfa0bbbcb3919500044ed9f4945a7028f287cb98cd41b533118532df32e; _chartbeat2=.1663242837578.1663244937272.1.BkhOtWCPzv4lDOIaoCVZFa6DO69hr.2; IR_9070=1663244937396%7C0%7C1663244937396%7C%7C; _ga_TNVCMNW09Q=GS1.1.1663244900.2.1.1663244938.0.0.0; s_c6=1663244938429-Repeat; s_sq=wdgespcom%252Cwdgespge%3D%2526pid%253Dfantasy%25253Afootball%25253Aleague%25253Atoolsprojections%2526pidt%253D1%2526oid%253Dhttps%25253A%25252F%25252Ffantasy.espn.com%25252Ffootball%25252Fplayers%25252Fprojections%252523%2526ot%253DA; s_c24=1663248195017; s_c24_s=Less%20than%201%20day; _chartbeat5=723|2758|%2Ffootball%2Fplayers%2Fprojections|https%3A%2F%2Ffantasy.espn.com%2Ffootball%2Fplayers%2Fprojections|Dft4fJjPKWdCVIEYMB2pBEF_hwbI||c|DVQepoS43QiBaZYxICjkjjKDLVgDT|espn.com|' \
# -H 'if-none-match: W/"0f9159113b4fc6e0fc9db3933e7c4c6f5"' \
# -H 'referer: https://fantasy.espn.com/football/players/projections' \
# -H 'sec-ch-ua: "Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"' \
# -H 'sec-ch-ua-mobile: ?0' \
# -H 'sec-ch-ua-platform: "macOS"' \
# -H 'sec-fetch-dest: empty' \
# -H 'sec-fetch-mode: cors' \
# -H 'sec-fetch-site: same-origin' \
# -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36' \
# -H 'x-fantasy-filter: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":0,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}' \
# -H 'x-fantasy-platform: kona-PROD-d2ecbc57dbf77c440f3be7ff68dccec940f0e115' \
# -H 'x-fantasy-source: kona' \
# --compressed
# 
# Same URL
# 'https://fantasy.espn.com/apis/v3/games/ffl/seasons/2022/segments/0/leaguedefaults/3?scoringPeriodId=0&view=kona_player_info'
# 'https://fantasy.espn.com/apis/v3/games/ffl/seasons/2022/segments/0/leaguedefaults/3?scoringPeriodId=0&view=kona_player_info'
# 
# PAGGING
# x-fantasy-filter (offset is different)
# -H 'x-fantasy-filter: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":50,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}' 
# -H 'x-fantasy-filter: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":0,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}' 
# -H 'x-fantasy-filter: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":[false],"sortPriority":[3],"value":["1120222"]},"sortDraftRanks":{"sortPriority":[2],"sortAsc":[true],"value":["PPR"]},"sortPercOwned":{"sortAsc":[false],"sortPriority":[4]},"limit":[100],"offset":[0],"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":[2],"additionalValue":["002022","102022","002021","1120222","022022"]}}}'
# 
# page2 <- fromJSON('{"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":50,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}')
# page1 <- fromJSON('{"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":0,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}')
# 
# 
# POSITION
# x-fantasy-filter (offset is different)
# QB:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# RB:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[2]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# WR:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[4]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# TE:  {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[6]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# DST: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[16]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# K:   {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[17]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# ALL: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# FLX: {"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[23]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortPriority":4,"sortAsc":false},"limit":50,"offset":0,"sortStatId":{"additionalValue":"1120222","sortAsc":true,"sortPriority":1,"value":3},"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}
# 
# resp <- request("https://fantasy.espn.com/apis/v3/games/ffl/seasons/2022/segments/0/leaguedefaults/3?scoringPeriodId=0&view=kona_player_info") %>%
#   req_method("GET") %>% 
#   # pagging: 'limit' and 'offset'
#   req_headers("x-fantasy-filter"='{"players":{"filterStatsForSplitTypeIds":{"value":[1]},"filterSlotIds":{"value":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,23,24]},"filterStatsForSourceIds":{"value":[1]},"sortAppliedStatTotal":{"sortAsc":false,"sortPriority":3,"value":"1120222"},"sortDraftRanks":{"sortPriority":2,"sortAsc":true,"value":"PPR"},"sortPercOwned":{"sortAsc":false,"sortPriority":4},"limit":50,"offset":0,"filterRanksForScoringPeriodIds":{"value":[2]},"filterRanksForRankTypes":{"value":["PPR"]},"filterRanksForSlotIds":{"value":[0,2,4,6,17,16]},"filterStatsForTopScoringPeriodIds":{"value":2,"additionalValue":["002022","102022","002021","1120222","022022"]}}}') %>% 
#   req_perform()
# 
# data <- resp %>% 
#   resp_body_json()
# 
# 
# data$players[[1]]$player %>% glimpse()
# data$players[[1]]$player$stats %>% glimpse()
# data$players[[3]]$player$stats %>% glimpse()
# 
