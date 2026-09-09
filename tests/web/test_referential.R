# tests/web/test_referential.R - logical foreign keys resolve
# (contract section 32.2).

suppressMessages({library(nanoparquet)})

FIX <- "./tests/fixtures/web_bundle"
rp  <- function(x) as.data.frame(read_parquet(file.path(FIX, x)))

teams   <- rp("dimensions/teams.parquet")
players <- rp("dimensions/players.parquet")
rosters <- rp("current/rosters.parquet")
matchups <- rp("current/matchups.parquet")

inside <- function(vals, universe) all(stats::na.omit(vals) %in% universe)

stopifnot(
  inside(rosters$team_id, teams$team_id),
  inside(rosters$player_id, players$player_id),
  inside(matchups$home_team_id, teams$team_id),
  inside(matchups$away_team_id, teams$team_id),
  inside(rp("current/standings.parquet")$team_id, teams$team_id),
  inside(rp("current/lineup_evaluations.parquet")$team_id, teams$team_id)
)

cat("PASS test_referential.R\n")
