# script que tenta verificar mapeamentos incompletos
# entre FFA e NFL
library(dm)
library(tidyverse)

ffa_db <- readRDS("./data/ffa_db.rds")
nfl <- readRDS("./data/nfl_players_db.rds")
st <- readRDS("./data/nfl_stats_db.rds")

## FFA IDS VALIDOS
ffa_ids <- ffa_db$ffa_player_ids |> 
  transmute(id, playerId=as.integer(nfl_id), name_key=numfire_id)  |> 
  filter(!is.na(playerId))

## NFL PLAYERS ATIVOS
nfl_actPlayers <- nfl$nfl_players |> 
  inner_join(filter(st$nfl_players_points, season==2023, week==0),
             by = join_by(playerId))

## QUEM FALTA?
nfl_missing_players <- nfl_actPlayers |>
  left_join(ffa_ids, by = join_by(playerId)) |>
  select(playerId, id, name_key, name, position, nflTeamAbbr, pts) |>
  filter(is.na(id)) |>
  arrange(desc(pts)) |>
  separate(
    name,
    sep = " ",
    into = c("first_name", "last_name"),
    extra = "drop",
    remove = F
  ) |>
  select(-id,-name_key)

## TENTA FAZER MATCH PELO NOME
missing_ids <- inner_join(nfl_missing_players,
           ffa_db$ffa_players,
           by = join_by(first_name, last_name)) |>
  transmute(
    id,
    nfl_id = as.character(playerId),
    name_key = paste(first_name, last_name, sep = "-")
  ) |> 
  distinct()

## cria registros com os NFL_IDs encontrados
mis_player_ids <- ffa_db$ffa_player_ids |> 
  select(-nfl_id) |> 
  inner_join(select(missing_ids, id, nfl_id), by=join_by(id))

## recompeo ao dados do pacote (teste)
ffa_db$ffa_player_ids |> 
  anti_join(mis_player_ids, by=join_by(id)) |> 
  bind_rows(mis_player_ids)

## salva como um arquivo extra
saveRDS(mis_player_ids, "./data/missing_player_ids.rds")
