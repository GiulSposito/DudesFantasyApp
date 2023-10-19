source("./R/api/nfl_api.R")

nfl_league_settings <- function(.authToken, .leagueId){
  nfl_api(
    .path = "/v2/league/settings",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId
    ),
    .auth=.authToken)
}


# return the user id, leagues and teams of a 'authToken'
nfl_league_teams <- function(.authToken, .leagueId){
  
  players <- nfl_api(
    .path = "/v2/league/teams",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId
    ),
    .auth=.authToken)
  
}


# return the user id, leagues and teams of a 'authToken'
nfl_league_matchups <- function(.authToken, .leagueId, .week, .incRosters=T){
  
  players <- nfl_api(
    .path = "/v2/league/matchups",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "week"      =  .week,
      "includeRosters" = ifelse(.incRosters,1,0),
      "forcePlayoffs" = 1
    ),
    .auth=.authToken)
  
}

# return the user id, leagues and teams of a 'authToken'
# https://api.fantasy.nfl.com/v2/docs/service?serviceName=leagueSchedule
nfl_league_schedule <- function(.leagueId, .authToken, .week){
  
  players <- nfl_api(
    .path = "/v2/league/schedule",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "week"      = .week
    ),
    .auth=.authToken)
  
}


# return the user id, leagues and teams of a 'authToken'
nfl_league_standings <- function(.authToken, .leagueId, .week){
  
  players <- nfl_api(
    .path = "/v2/league/standings",
    .query = list(
      "appKey"    = "internalemailuse",
      "week"      = .week, 
      "leagueId"  = .leagueId
    ),
    .auth=.authToken)
  
}

# return the user id, leagues and teams of a 'authToken'
nfl_league_team_roster <- function(.authToken, .leagueId, .teamId, .week){
  
  players <- nfl_api(
    .path = "/v2/league/teams",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "teamId"    = .teamId,
      "week"      = .week
    ),
    .auth=.authToken)
  
}

# return the user id, leagues and teams of a 'authToken'
nfl_league_matchups_recap <- function(.authToken, .leagueId, .week,.teamId){
  
  players <- nfl_api(
    .path = "/v2/league/team/matchuprecap",
    .query = list(
      "appKey"    = "internalemailuse",
      "leagueId"  = .leagueId,
      "week"      = .week,
      "teamId"    = .teamId
    ),
    .auth=.authToken)
  
}

nfl_extractRecap <- function(recapResp){
  if (length(recapResp$content)==0) return(NULL)
  tibble(
    team   = c("away","home"),
    teamId = recapResp$content$teams$id,
    name   = recapResp$content$teams$name,
    coachPoints = recapResp$content$teams$coach_points
  ) |> 
    pivot_wider(names_from="team", values_from=c(teamId, name, coachPoints), names_sep=".") %>% 
    mutate(
      title = recapResp$content$title,
      week  = recapResp$content$week_num,
      paragraphs  = list(tibble(recapResp$content$paragraphs)), 
      leagueHighligths = list(tibble(recapResp$content$league_notes))
    ) 
}

# recebe um recap DB com a tabela colapsada e devolve o modelo expandido
nfl_expandeRecapDB <- function(nfl_recap_db){

  # GENERATE MATCHUPID ####
  recap_raw <- nfl_recap_db$nfl_recap |> 
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
  
  return(nfl_recap_db)
}

# pega o DF do recap, gera um id unico e devolve um DB
nfl_convertRecapDB <- function(nfl_recap_df){
    
    # GENERATE MATCHUPID ####
  nfl_recap <-
    nfl_recap_df |> 
      mutate( matchupId = map(teams, pull, id),
              matchupId = map_chr(matchupId, \(ids){paste0("a", ids[1], "_h", ids[2])}),
              matchupId = as.character(glue("w{week}_{matchupId}"))) |> 
    select(1:3, matchupId, everything())
  
  dm(nfl_recap) |> 
    dm_add_pk(nfl_recap, c(leagueId, season, week, matchupId))

}
    
    

# extrai o time e o roster
nfl_extractTeams <- function(teamsResp){
  
  # extract teams
  teamsResp$content$games[[1]]$leagues[[1]]$teams |> 
    #transforma a lista de times em tibble
    tibble() |> 
    set_names("team") |> 
    unnest_wider(team) |> 
    # corrige tipos inteiros
    mutate(across(c(teamId, ownerUserId), as.integer))
}


nfl_extractTeamOwners  <- function(teamsResp){
  teamsResp$content$users |> 
    tibble(owner=_) |> 
    unnest_wider(owner) |> 
    mutate(
      userId = as.integer(userId),
      name = str_trim(name)
    ) |> 
    select(ownerUserId=userId, name)
}


# extrai o time e o roster
nfl_extractTeamsFromMatchups <- function(leagueMatchupsResp, season, week, tag, timestamp){
  
  # extract teams and rosters
  teams_raw <- leagueMatchupsResp$content$games[[1]]$leagues[[1]]$teams |> 
    #transforma a lista de times em tibble
    tibble() |> 
    set_names("team") |> 
    unnest_wider(team) |> 
    mutate(season, week, tag, timestamp)
  
  # dados do time na rodada 
  nfl_teams_round <- teams_raw |> 
    mutate(season=season, week=week) |> 
    select(season, week, teamId, rank, imageUrl, imageUrlLarge)|> 
    mutate(across(c(teamId, rank),as.integer))
  
  # dados do roster
  nfl_teams_rosters <- teams_raw |>
    select(season, week, tag, timestamp, teamId, rosters) |>
    mutate(rosters = map(rosters, \(.r) {
      .r[[1]] |>
        bind_rows(.id = "slotPosition")
    })) |>
    unnest(rosters) |>
    select(season, week, tag, timestamp, teamId, everything()) |> 
    mutate(across(c(teamId, rosterSlotId, playerId), as.integer))
  
  nfl_teams_rosters_db <- dm(nfl_teams_round, nfl_teams_rosters) |> 
    dm_add_pk(nfl_teams_round, c(season, week, teamId)) |> 
    dm_add_pk(nfl_teams_rosters, c(season, week, tag, timestamp, teamId, rosterSlotId, playerId)) |> 
    dm_add_fk(nfl_teams_rosters, c(season, week, teamId), nfl_teams_round)
  
  return(nfl_teams_rosters_db)
}

nfl_extractStatsFromMatchups <- function(leagueMatchupsResp, season,  week, tag, timestamp){
  
  # extract teams and rosters
  teams_raw <- leagueMatchupsResp$content$games[[1]]$leagues[[1]]$teams |> 
    #transforma a lista de times em tibble
    tibble() |> 
    set_names("team") |> 
    unnest_wider(team) |> 
    mutate(season, week, tag, timestamp)
  
  # statisticas do time na rodada
  teams_stats <- teams_raw |> 
    select(season, week, tag, timestamp, teamId, stats) |> 
    mutate( weekStats = map(stats,\(.st){
      .st$week[[1]] |> 
        unlist() |> 
        enframe() |> 
        separate(name, into=c("week", "statId"), sep="\\.", convert = T) |> 
        mutate( value = parse_number(as.character(value)),
                statId = as.character(statId)) |> 
        select(statId, value)    
    })) |> 
    mutate( seasonStats = map(stats, \(.st){
      .st$season[[1]] |> 
        unlist() |> 
        enframe()
    }))
  
  nfl_teams_week_stats <- teams_stats |> 
    select(season:teamId, weekStats) |> 
    unnest(weekStats) |> 
    mutate(teamId = as.integer(teamId))
    
  nfl_teams_season_stats <- teams_stats |> 
    select(season:teamId, seasonStats) |> 
    unnest(seasonStats) |> 
    mutate(teamId = as.integer(teamId))
    
  nfl_teams_stats <- dm(nfl_teams_week_stats, nfl_teams_season_stats) |> 
    dm_add_pk(nfl_teams_week_stats, c(season, week, tag, timestamp, teamId, statId)) |> 
    dm_add_pk(nfl_teams_season_stats, c(season, week, tag, timestamp, teamId, name))
  
  return(nfl_teams_stats)
    
}


# extrai os jogos
nfl_extractMatchups <- function(leagueMatchupsResp, season){
  
  # extract matchups
  leagueMatchupsResp$content$games[[1]]$leagues[[1]]$matchups |> 
    tibble() %>% 
    set_names("matchups") |> 
    unnest_wider(matchups) |> 
    unnest_wider(awayTeam, names_sep="_") |> 
    unnest_wider(homeTeam, names_sep="_") |>
    janitor::clean_names("lower_camel") |> 
    mutate(
      season=season,
      across(c(week, ends_with("TeamId"), ends_with("PlayoffSeeding")), as.integer),
      across(starts_with("bracket"), as.character)
    ) |> 
    select(season, week, matchupId, everything())
}
