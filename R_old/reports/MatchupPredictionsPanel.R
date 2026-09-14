library(tidyverse)
library(glue)
library(htmltools)

# -------- função que gera o HTML para um confronto --------
render_matchup <- function(df, file = "matchup.html") {
  stopifnot(nrow(df) == 16)
  pct_txt <- function(x) paste0(round(x * 100), "%")
  
  # card de um time
  team_card <- function(row, side = c("left","right")) {
    side <- match.arg(side)
    tags$div(class = paste("team", side),
             tags$div(class = "row1",
                      tags$img(src = row$image_url, class = "avatar", alt = row$team),
                      tags$div(class = "score", sprintf("%.1f", row$score_current))
             ),
             tags$div(class = "handle", row$handle),
             tags$div(class = "team-name", row$team),
             tags$div(class = "proj",
                      tags$span("Proj."),
                      tags$span(class = "num", sprintf(" %.1f", row$projection))
             ),
             tags$div(class = "barwrap",
                      tags$div(class = "bar",
                               tags$div(class = "fill",
                                        style = paste0("width:", round(row$compl*100), "%;"))
                      ),
                      tags$div(class = "under",
                               tags$span(class = "record", row$record),
                               tags$span(class = "winprob", pct_txt(row$win_prob))
                      )
             )
    )
  }
  
  ui <- tags$html(
    tags$head(
      tags$meta(charset = "utf-8"),
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
      tags$title("Matchup"),
      tags$style(HTML("
        :root {
          --bg: #0f1420; --card:#1c2433; --text:#e7edf7; --muted:#9fb0c9;
          --pink:#ff7ac3; --blue:#58c4ff; --bar:#2a3447;
        }
        * { box-sizing: border-box; }
        body {
          margin:0; background:var(--bg); color:var(--text);
          font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Inter, Arial, sans-serif;
        }
        .wrap { max-width: 460px; margin: 24px auto; padding: 12px; }
        .card {
          background: var(--card); border-radius: 16px; padding: 14px;
          display: flex; align-items: stretch; gap: 12px;
          box-shadow: 0 6px 18px rgba(0,0,0,.25);
        }
        .team {
          flex: 1 1 0; background: rgba(255,255,255,.02);
          border-radius: 12px; padding: 12px;
          display: flex; flex-direction: column; gap: 6px;
        }
        .row1 { display:flex; align-items:center; gap:10px; }
        .avatar {
          width: 56px; height: 56px; border-radius: 50%; object-fit: cover;
          border: 2px solid rgba(255,255,255,.12);
        }
        .score { margin-left:auto; font-weight:800; font-size:22px; }
        .handle { font-size:12px; color:var(--muted); }
        .team-name { font-weight:600; line-height:1.2; }
        .proj { display:flex; gap:6px; align-items:baseline; color:var(--muted); font-size:12px; }
        .proj .num { color:var(--text); font-weight:600; }
        .barwrap { display:flex; flex-direction:column; gap:6px; }
        .bar { height:6px; background:var(--bar); border-radius:999px; overflow:hidden; }
        .fill { height:100%; border-radius:999px; }
        .team.left  .fill { background:linear-gradient(90deg, var(--pink), var(--blue)); }
        .team.right .fill { background:linear-gradient(90deg, var(--blue), var(--pink)); }
        .under { display:flex; justify-content:space-between; font-size:12px; color:var(--muted); }
        .under .winprob { color:var(--text); font-weight:600; }
        .vs {
          display:grid; place-items:center; width:44px; font-weight:800;
          color:var(--muted);
        }
        @media (max-width: 460px) { .card { gap: 8px; } .vs { width: 36px; } }
      "))
    ),
    tags$body(
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[1,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[2,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[3,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[4,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[5,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[6,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[7,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[8,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[9,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[10,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[11,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[12,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[13,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[14,], side = "right")
               )
      ),
      tags$div(class = "wrap",
               tags$div(class = "card",
                        team_card(df[15,], side = "left"),
                        tags$div(class = "vs", "VS"),
                        team_card(df[16,], side = "right")
               )
      ),
    )
  )
  
  htmltools::save_html(ui, file = file, background = "transparent")
  message("HTML salvo em: ", normalizePath(file))
}


generateMatchupPredictionPanel <- function(.week, .prefix) {
  # .week <- 2
  # .prefix <- "posTNF"
  
  sim <- readRDS(glue("./data/simulation_v5_week{.week}_{.prefix}.rds"))
  
  # game summary in long form
  teams_sims <- bind_rows(
    select(sim$matchup_sim, teamId=awayTeam.teamId, winProb=awayTeam.winProb, winProb.org=awayTeam.winProb.org, pred.Pts=awayTeam.totalPts, sim.pts=awayTeam.simulation, sim.pts.org=awayTeam.simulation.org),
    select(sim$matchup_sim, teamId=homeTeam.teamId, winProb=homeTeam.winProb, winProb.org=homeTeam.winProb.org, pred.Pts=homeTeam.totalPts, sim.pts=awayTeam.simulation, sim.pts.org=homeTeam.simulation.org)
  ) |>  mutate(
    pred.Pts.org = map_dbl(sim.pts.org, median, na.rm=T)
  )
  
  # obtem nome e pontuacao dos times
  teams_stats <- sim$teams |> 
    unnest( rosters ) |> 
    filter( rosterSlotId < 20 ) |>
    select( teamId, playerId, isEditable ) |> 
    inner_join( sim$players_stats, by = "playerId" ) |> 
    unnest( weekPts ) |> 
    filter( week==.week ) |> 
    select( teamId, playerId, isEditable, weekPts ) |> 
    group_by( teamId ) |> 
    summarise(
      players = n(),
      played  = sum(!isEditable),
      points = sum(weekPts, na.rm = T)
    ) |> 
    ungroup()
  
  invalidAvatars <- c("https://static.www.nfl.com/league/apps/fantasy/logos/avatar/240x240/OAK_1.png")
  genericAvatar <- "https://static.www.nfl.com/league/apps/fantasy/logos/200x213/NO.png"
  
  teams <- sim$teams |> 
    select(teamId, name, imageUrl) |> 
    inner_join(teams_sims, by = "teamId") |> 
    inner_join(teams_stats, by = "teamId") |>
    mutate(imageUrl=if_else(imageUrl %in% invalidAvatars, genericAvatar, imageUrl))
  
  
  games_summary <- sim$matchup_sim |> 
    inner_join(set_names(teams, paste0("away.",names(teams))), by=c("awayTeam.teamId"="away.teamId")) |> 
    inner_join(set_names(teams, paste0("home.",names(teams))), by=c("homeTeam.teamId"="home.teamId")) |> 
    mutate(game=paste0(away.name, " @ ", home.name)) |> 
    mutate( away.nickname = gsub("([a-zA-Z\']+ )?", "", away.name),
            home.nickname = gsub("([a-zA-Z\']+ )?", "", home.name),
            away.handle   = str_trim(str_remove_all(away.name, away.nickname)),
            home.handle   = str_trim(str_remove_all(home.name, home.nickname))) |> 
    mutate( game.nickname = paste0(away.nickname, " @ ", home.nickname))
  
  game_center <- games_summary |>
    select(game, away.imageUrl, away.handle, away.nickname, away.points, home.points, home.handle, home.nickname, home.imageUrl,
           away.winProb, away.played, away.players, away.pred.Pts, 
           home.winProb, home.played, home.players, home.pred.Pts) |> 
    mutate(
      across(c(away.points, home.points, away.pred.Pts, home.pred.Pts),
             \(x) round(x, digits=1))
      # across(c(away.winProb, home.winProb), function(.x){ paste0(round(100*.x),"%") })
    )
  
  left <- game_center |> 
    mutate(side="left") |> 
    select(game, side, starts_with("away.")) 
  
  left <- setNames(left, str_remove_all(names(left), "away."))
  
  right <- game_center |> 
    mutate(side="right") |> 
    select(game, side, starts_with("home.")) 
  
  right <- setNames(right, str_remove_all(names(right), "home."))
  
  cardsDF<- bind_rows(left, right) |> 
    arrange(game, side) |> 
    mutate(
      compl=(9-played)/9,
      record = glue("{played}/{players}")
    ) |> 
    select(
      handle, team=nickname, score_current=points, 
      projection=pred.Pts, win_prob=winProb, compl,
      record, image_url=imageUrl
    )
  
  
  # # EXEMPLO de dados (substitua pelos seus)
  # matchup <- tibble::tibble(
  #   handle        = c("@Giuliano", "@Abdala"),
  #   team          = c("Amparo Bikers", "Indaiatuba Pats"),
  #   score_current = c(35, 3),
  #   projection    = c(118.4, 110.8),
  #   win_prob      = c(0.61, 0.39),     # 0 a 1
  #   compl         = c(3/9, 1/9), 
  #   record        = c("0-0", "0-0"),
  #   image_url     = c(
  #     "https://static.www.nfl.com/league/apps/fantasy/logos/avatar/240x240/SF_1.png",
  #     "https://fantasy.nfl.com/image/81e9ca9e01ac58835b2c263bb1e39f3f.jpg?&x=50&y=50"
  #   )
  # )
  
  # gerar o HTML
  render_matchup(cardsDF, "./static/reports/2025/matchups.html")
  
}
