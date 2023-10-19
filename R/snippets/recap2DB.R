library(glue)

# GENERATE MATCHUPID ####
recap_raw <- nfl_recap_df |> 
  mutate( matchupId = map(teams, pull, id),
          matchupId = map_chr(matchupId, \(ids){paste0("a", ids[1], "_h", ids[2])}),
          matchupId = as.character(glue("w{week}_{matchupId}")))

# RECAP DF #####
nfl_recap <-
  recap_raw |>
  select(
    leagueId,
    season,
    week,
    type,
    weekday,
    playoff,
    standard_scheduling,
    standard_scoring
  ) |> distinct()

nfl_recap_matchups <- recap_raw |>
  select(
    leagueId,
    season,
    week,
    matchupId,
    written_at
  )

# RECAP TEXT SUMMARY ####
nfl_recap_texts <-
  recap_raw |>
  select(leagueId,
         season,
         week,
         matchupId,
         title,
         paragraphs)

# RECAP LEAGUE NOTES ####
nfl_recap_notes <- recap_raw |> 
  select(leagueId,
         season,
         week,
         league_notes) |> 
  distinct()

# FA LEADERS ####
nfl_fa_leaders <- recap_raw |> 
  select(leagueId,
         season,
         week,
         free_agent_target_touch_leaders) |> 
  mutate( free_agent_target_touch_leaders = map(free_agent_target_touch_leaders, \(fa){
    fa |> 
      enframe(name="category", value="player") |> 
      unnest(player, names_sep="_")
  }) ) |> 
  unnest(free_agent_target_touch_leaders) 


# RECAP TEAMS ####
recap_team_raw <- 
recap_raw |>
  select(
    leagueId,
    season,
    week,
    matchupId,
    teams) |> 
  unnest(teams) |> 
  rename(teamId=id)

nfl_recap_teams <- recap_team_raw |> 
  select(-phases, -players)

# RECAP TEAMS PHASES ####
nfl_recap_team_phases <- recap_team_raw |> 
  select(1:4, teamId, phases)

# RECAP TEAMS PLAYERS ####
nfl_recap_team_players <- recap_team_raw |> 
  select(1:4, teamId, players) |> 
  unnest(players, names_sep = "_")
  
# RECAP DB ####
nfl_recap_db <- dm(
  nfl_recap,
  nfl_recap_matchups,
  nfl_recap_texts,
  nfl_recap_notes,
  nfl_fa_leaders,
  nfl_recap_teams,
  nfl_recap_team_phases,
  nfl_recap_team_players
) |> 
  dm_add_pk(nfl_recap, c(leagueId, season, week)) |> 
  dm_add_pk(nfl_recap_matchups, c(leagueId, season, week, matchupId)) |> 
  dm_add_fk(nfl_recap_matchups, c(leagueId, season, week), nfl_recap) |> 
  dm_add_pk(nfl_recap_texts, c(leagueId, season, week, matchupId)) |> 
  dm_add_fk(nfl_recap_texts, c(leagueId, season, week, matchupId), nfl_recap_matchups) |> 
  dm_add_pk(nfl_recap_notes, c(leagueId, season, week)) |> 
  dm_add_fk(nfl_recap_notes, c(leagueId, season, week), nfl_recap) |> 
  dm_add_pk(nfl_recap_teams, c(leagueId, season, week, matchupId, teamId)) |> 
  dm_add_fk(nfl_recap_teams, c(leagueId, season, week, matchupId), nfl_recap_matchups) |> 
  dm_add_fk(nfl_recap_team_phases, c(leagueId, season, week, matchupId, teamId), nfl_recap_teams) |> 
  dm_add_fk(nfl_recap_team_players, c(leagueId, season, week, matchupId, teamId), nfl_recap_teams) |> 
  dm_add_fk(nfl_fa_leaders, c(leagueId, season, week), nfl_recap)
  
nfl_recap_db |> 
  dm_draw(view_type = "all", column_types = T)





