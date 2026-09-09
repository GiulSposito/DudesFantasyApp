# ESPN_API.md

Referência da API ESPN Fantasy Football e do cliente R que a embrulha
(`R/api/espn_fantasy_client.R`). Cobre o endpoint, autenticação, parâmetros de
requisição, as *views* disponíveis, e — para cada entidade — a origem no JSON, os
parâmetros aceitos e os campos retornados pelo parser.

A API **não é oficial nem documentada** pela ESPN e pode mudar sem aviso. Todos os
nomes de campo abaixo são o que o *cliente* expõe; a coluna "origem JSON" aponta o
caminho no payload cru (`espn_snapshot()$raw`).

Gerado por leitura de `R/api/espn_fantasy_client.R` em 2026-09-08.

---

## 1. Visão geral

| item | valor |
|------|-------|
| host | `https://lm-api-reads.fantasy.espn.com` |
| base | `/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league_id}` |
| metadata | `/apis/v3/games/ffl` · `/apis/v3/games/ffl/seasons/{season}` |
| formato | JSON (`resp_body_json(simplifyVector = FALSE)`) |
| transporte | `httr2`, `Accept: application/json`, `User-Agent: R espn-fantasy-client/1.0` |

Uma única URL de liga serve **todas** as entidades da liga. O que muda é o conjunto
de *views* passado em `?view=` (repetido, `.multi = "explode"`) e, opcionalmente, o
header `X-Fantasy-Filter` (para o pool de jogadores) e os query params
`scoringPeriodId` / `matchupPeriodId`.

O pool de jogadores (`kona_player_info`) é a mesma URL, mas o corpo útil vem no
header de filtro, não na query.

### Autenticação

Ligas privadas exigem dois cookies, enviados juntos no header `Cookie`:

```
Cookie: espn_s2={valor}; SWID={valor-entre-chaves}
```

- `ESPN_S2` — token longo, **já URL-encoded** no `config/config.yml`; passe verbatim.
- `ESPN_SWID` — GUID entre chaves, ex. `{XXXXXXXX-XXXX-...}`.

Sem cookies válidos: `HTTP 401` (liga privada / cookie expirado) ou `403`. O cliente
converte esses status em erros com mensagem em português. `404` normalmente é ano de
liga errado.

### Resiliência

`req_retry(max_tries = 4)` com back-off em `408, 425, 429, 500, 502, 503, 504` e em
falha de conexão. `req_timeout` = `client$timeout` (padrão 30s; o pipeline usa 60s).
`cache_dir` opcional liga `req_cache` (cache em disco do `httr2`, `use_on_error`).

---

## 2. `espn_client()` — construtor

```r
espn_client(
  league_id = "342842788",
  season    = 2026L,
  espn_s2   = Sys.getenv("ESPN_S2"),
  swid      = Sys.getenv("ESPN_SWID", unset = Sys.getenv("SWID")),
  timeout   = 30,
  max_tries = 4L,
  cache_dir = NULL
)
```

| parâmetro | tipo | default | efeito |
|-----------|------|---------|--------|
| `league_id` | chr/num | `"342842788"` | id da liga; entra na URL base |
| `season` | int | `2026` | ano; entra na URL base e em `espn_season_meta()` |
| `espn_s2` | chr | env `ESPN_S2` | cookie de auth; string vazia = requisições anônimas |
| `swid` | chr | env `ESPN_SWID` ou `SWID` | cookie de auth |
| `timeout` | num | `30` | segundos por requisição |
| `max_tries` | int | `4` | tentativas totais (1 + 3 retries) |
| `cache_dir` | chr\|NULL | `NULL` | se setado, cache de resposta em disco |

Retorna um objeto S3 `espn_fantasy_client` (lista com `host = ...`, `game = "ffl"`).
`espn_has_auth(client)` diz se os dois cookies estão presentes.

O pipeline (`R/pipeline/data_pipeline_espn.R`) monta o cliente a partir do
`config.yml`: `ESPN_LEAGUEID`, `season` (parâmetro `.season` do master script),
`ESPN_S2`, `ESPN_SWID`, `timeout = 60`.

---

## 3. Requisição base

### `espn_raw(client, views, week = NULL, matchup_period = NULL, fantasy_filter = NULL)`

Getter de baixo nível da URL de liga. Todo getter de alto nível chama este.

| parâmetro | vira | observação |
|-----------|------|------------|
| `views` | `?view=` (repetido) | lista de views — ver seção 4 |
| `week` | `?scoringPeriodId=` | semana NFL (1–18); filtra rosters, stats e transações |
| `matchup_period` | `?matchupPeriodId=` | período de confronto; normalmente = `week` |
| `fantasy_filter` | header `X-Fantasy-Filter` (JSON) | só para `kona_player_info` |

`scoringPeriodId` e `matchupPeriodId` **não são a mesma coisa**: em semanas de
playoff um matchup period pode cobrir mais de uma scoring period. Fora dos playoffs
coincidem.

### Metadata (fora da URL de liga)

| função | endpoint | retorna |
|--------|----------|---------|
| `espn_game_meta(client)` | `/apis/v3/games/ffl` | metadados do "jogo" ffl (temporada corrente etc.) — JSON cru |
| `espn_season_meta(client)` | `/apis/v3/games/ffl/seasons/{season}` | metadados da temporada — JSON cru |
| `espn_current_week(client)` | (usa `season_meta`) | `currentScoringPeriod$id` como inteiro |

Quando `week = NULL` é passado a qualquer getter, ele resolve via
`espn_current_week()`.

---

## 4. Views

Cada view liga um bloco do payload. As entidades abaixo dependem destes blocos:

| view | preenche no `raw` | usado por |
|------|-------------------|-----------|
| `mSettings` | `settings` (nome, tamanho, draft, roster, scoring, schedule, acquisition) | league, roster_slots, scoring_rules |
| `mStatus` | `status` (scoring/matchup period corrente, final) | league |
| `mTeam` | `teams` (cadastro), `members` | members, teams, e é pré-requisito dos joins de nome |
| `mStandings` | `teams[].record`, ranks | teams (classificação) |
| `mRoster` | `teams[].roster.entries` | rosters, starters, bench |
| `mMatchupScore` | `schedule` (pontos por lado) | matchups |
| `mScoreboard` / `mLiveScoring` | `schedule` ao vivo | scoreboard |
| `mDraftDetail` | `draftDetail.picks` | draft |
| `mTransactions2` | `transactions` | transactions |
| `kona_player_info` | `players` (pool + stats embutidas) | player pool, player stats |

`espn_snapshot()` pede de uma vez: `mSettings, mStatus, mTeam, mRoster, mStandings,
mMatchupScore, mDraftDetail` (+ `mTransactions2` se `include_transactions = TRUE`).

---

## 5. Entidades

Convenção das tabelas de campos: **campo** = nome no tibble do cliente · **origem
JSON** = caminho relativo ao bloco da view · campos marcados _(mapa)_ vêm de um
lookup local (seção 6), não da API · _(derivado)_ é calculado pelo cliente.

### 5.1 League — `espn_league(client)`

Views: `mSettings`, `mStatus`. Parser: `.espn_parse_league_summary`. Uma linha.

| campo | origem JSON | significado |
|-------|-------------|-------------|
| `league_id` | `id` | id da liga |
| `season` | `seasonId` | ano |
| `league_name` | `settings.name` | nome da liga |
| `size` | `settings.size` | nº de times |
| `current_scoring_period` | `scoringPeriodId` ‖ `status.currentScoringPeriod.id` | semana corrente |
| `current_matchup_period` | `status.currentMatchupPeriod` | período de confronto corrente |
| `final_scoring_period` | `status.finalScoringPeriod` | última semana da temporada |
| `draft_date` | `settings.draftSettings.date` | data/hora do draft (epoch ms → POSIXct UTC) |
| `draft_type` | `settings.draftSettings.type` | código do tipo de draft |
| `draft_time_per_selection` | `settings.draftSettings.timePerSelection` | segundos por pick |
| `draft_slot_count` | `settings.draftSettings.slotCount` | slots no board |
| `roster_locktime` | `settings.rosterSettings.lineupLocktime` ‖ `.locktime` | política de trava de lineup |
| `waiver_process_days` | `settings.acquisitionSettings.waiverProcessDays` | dias de processamento de waiver |
| `matchup_period_count` | `settings.scheduleSettings.matchupPeriodCount` | nº de períodos de confronto |

### 5.2 Members — `espn_members(client)`

View: `mTeam`. Parser: `.espn_parse_members`. Uma linha por membro (dono).

| campo | origem JSON | significado |
|-------|-------------|-------------|
| `member_id` | `members[].id` | GUID do membro (SWID-like) |
| `display_name` | `members[].displayName` | apelido |
| `first_name` | `members[].firstName` | nome |
| `last_name` | `members[].lastName` | sobrenome |
| `is_league_manager` | `members[].isLeagueManager` | flag de comissário (default `FALSE`) |

### 5.3 Teams — `espn_teams(client)`

Views: `mTeam`, `mStandings`. Parser: `.espn_parse_teams`. Uma linha por time.
Traz tanto o cadastro quanto a classificação corrente (a API só dá o estado de
agora — sem histórico).

| campo | origem JSON | significado |
|-------|-------------|-------------|
| `team_id` | `teams[].id` | id do time na liga |
| `team_name` | `teams[].name` ‖ `location`+`nickname` ‖ `"Team {id}"` _(derivado)_ | nome |
| `abbrev` | `teams[].abbrev` | sigla |
| `owner_ids` | `teams[].owners[]` (join `,`) | GUIDs dos donos |
| `owners` | nomes resolvidos via `members` _(derivado)_ | donos por `display_name` (join `, `) |
| `division_id` | `teams[].divisionId` | divisão |
| `current_projected_rank` | `teams[].currentProjectedRank` | rank projetado atual |
| `draft_day_projected_rank` | `teams[].draftDayProjectedRank` | rank projetado no dia do draft |
| `waiver_rank` | `teams[].waiverRank` | posição na fila de waiver |
| `points` | `teams[].points` | pontos totais |
| `points_adjusted` | `teams[].pointsAdjusted` | pontos ajustados |
| `wins` / `losses` / `ties` | `teams[].record.overall.wins` / `.losses` / `.ties` | campanha (default `0`) |
| `win_pct` | `teams[].record.overall.percentage` | aproveitamento |
| `points_for` / `points_against` | `teams[].record.overall.pointsFor` / `.pointsAgainst` | pontos pró / contra |
| `streak_type` | `teams[].record.overall.streakType` | tipo de sequência (`WIN`/`LOSS`) |
| `streak_length` | `teams[].record.overall.streakLength` | tamanho da sequência |
| `acquisitions` / `drops` / `trades` | `teams[].transactionCounter.acquisitions` / `.drops` / `.trades` | contadores de transação (default `0`) |

### 5.4 Roster slots — `espn_roster_slots(client)`

View: `mSettings`. Parser: `.espn_parse_roster_slots`. Uma linha por slot de lineup.

| campo | origem JSON | significado |
|-------|-------------|-------------|
| `lineup_slot_id` | chave de `settings.rosterSettings.lineupSlotCounts` | id do slot (seção 6) |
| `lineup_slot` | _(mapa)_ | rótulo (`QB`, `RB`, `FLEX`, `BE`, `IR`, …) |
| `count` | valor de `lineupSlotCounts` | quantas vagas desse slot |

### 5.5 Scoring rules — `espn_scoring_rules(client)`

View: `mSettings`. Parser: `.espn_parse_scoring_rules`. Uma linha por item de
pontuação.

| campo | origem JSON | significado |
|-------|-------------|-------------|
| `stat_id` | `settings.scoringSettings.scoringItems[].statId` | id da estatística |
| `points` | `...scoringItems[].points` | pontos por unidade da estatística |
| `is_reverse_item` | `...scoringItems[].isReverseItem` | pontuação invertida (default `FALSE`) |
| `points_overrides` | `...scoringItems[].pointsOverrides` (list-column) | overrides por posição — **descartado no pipeline** |

### 5.6 Rosters — `espn_rosters(client, week)` · `espn_starters()` · `espn_bench()`

Views: `mTeam`, `mRoster`. Parâmetro `week` → `scoringPeriodId` (define de que
semana é o lineup). Parser: `.espn_parse_rosters`. Uma linha por jogador rosterado.
`espn_starters()` / `espn_bench()` são o mesmo com `filter(is_starter)` /
`filter(is_bench)`.

| campo | origem JSON (`teams[].roster.entries[]`) | significado |
|-------|------------------------------------------|-------------|
| `team_id` | `teams[].id` | time |
| `team_name` | _(derivado)_ | nome do time |
| `player_id` | `entry.playerId` ‖ `playerPoolEntry.id` ‖ `player.id` | jogador |
| `player_name` | `player.fullName` | nome |
| `first_name` / `last_name` | `player.firstName` / `.lastName` | — |
| `pro_team_id` | `player.proTeamId` | time NFL (seção 6) |
| `pro_team` | _(mapa)_ | sigla NFL |
| `default_position_id` | `player.defaultPositionId` | posição (seção 6) |
| `position` | _(mapa)_ | `QB`/`RB`/`WR`/`TE`/`K`/`D/ST` |
| `lineup_slot_id` | `entry.lineupSlotId` | slot em que foi escalado |
| `lineup_slot` | _(mapa)_ | rótulo do slot |
| `is_starter` / `is_bench` / `is_ir` | _(derivado de `lineup_slot_id`)_ | `BE` = 20, `IR` = 21, resto = titular |
| `acquisition_type` | `entry.acquisitionType` ‖ `playerPoolEntry.acquisitionType` | como foi adquirido |
| `acquisition_date` | idem `.acquisitionDate` | epoch ms → POSIXct |
| `percent_owned` / `percent_started` | `playerPoolEntry.percentOwned` / `.percentStarted` | % de ligas |
| `total_points` | `playerPoolEntry.totalPoints` | pontos na temporada |
| `applied_stat_total` | `playerPoolEntry.appliedStatTotal` | total de stats aplicadas |
| `injury_status` | `entry.injuryStatus` ‖ `player.injuryStatus` | `ACTIVE`/`QUESTIONABLE`/`OUT`/… |
| `active` / `injured` / `droppable` | `player.active` / `.injured` / `.droppable` | flags |
| `lineup_locked` | `playerPoolEntry.lineupLocked` | lineup travado |
| `eligible_slot_ids` | `player.eligibleSlots` (join `,`) | slots elegíveis |
| `stats_raw` | `player.stats` (list-column) | stats embutidas — insumo do expand (5.9) |

O pipeline mantém a maioria mas **descarta** `first_name`, `last_name`,
`pro_team_id`, `default_position_id`, `active`, `injured`, `droppable`,
`lineup_locked`, `stats_raw`.

### 5.7 Matchups — `espn_matchups(client, week)` · `espn_scoreboard(client, week)`

Views: `mTeam`, `mMatchupScore`, `mStandings` (scoreboard usa `mScoreboard`,
`mLiveScoring`). Parâmetros `week` → `scoringPeriodId` **e** `matchupPeriodId`.
Parser: `.espn_parse_schedule`. Uma linha por confronto de **toda** a temporada
(o `schedule` não é filtrado por semana; o filtro afeta os pontos ao vivo).

| campo | origem JSON (`schedule[]`) | significado |
|-------|---------------------------|-------------|
| `matchup_id` | `id` | id do confronto |
| `matchup_period_id` | `matchupPeriodId` | período de confronto (≈ semana) |
| `playoff_tier_type` | `playoffTierType` | `NONE` / `WINNERS_BRACKET` / … |
| `winner` | `winner` | `HOME` / `AWAY` / `UNDECIDED` |
| `home_team_id` / `away_team_id` | `home.teamId` / `away.teamId` | times |
| `home_team_name` / `away_team_name` | _(join de `teams`)_ | nomes |
| `home_points` / `away_points` | `home.totalPoints` / `away.totalPoints` | pontos reais |
| `home_projected_points` / `away_projected_points` | `home.totalProjectedPointsLive` / `away.…` | pontos projetados ao vivo |

### 5.8 Draft — `espn_draft(client, resolve_players = TRUE)`

Views: `mTeam`, `mDraftDetail`. Sem parâmetro de semana (evento único). Parser:
`.espn_parse_draft`. Uma linha por pick, ordenada por `overall_pick`. Com
`resolve_players = TRUE` faz join do nome/posição/time via `espn_player_pool()`.

| campo | origem JSON (`draftDetail.picks[]`) | significado |
|-------|------------------------------------|-------------|
| `pick_id` | `id` | id da pick |
| `overall_pick` | `overallPickNumber` | nº geral |
| `round` | `roundId` | rodada |
| `round_pick` | `roundPickNumber` | nº dentro da rodada |
| `team_id` | `teamId` | time que escolheu |
| `team_name` | _(join)_ | nome |
| `player_id` | `playerId` | jogador escolhido |
| `player_name` / `position` / `pro_team` | _(join do pool, se `resolve_players`)_ | — |
| `bid_amount` | `bidAmount` | lance (ligas de leilão) |
| `auto_draft_type_id` | `autoDraftTypeId` | tipo de auto-pick |
| `keeper` | `keeper` | foi keeper (default `FALSE`) |
| `trade_locked` | `tradeLocked` | pick travada para troca (default `FALSE`) |

### 5.9 Player pool — `espn_player_pool()` · `espn_available_players()` · `espn_all_players()`

View: `kona_player_info`. O filtro vai no header `X-Fantasy-Filter` (JSON):

```r
.espn_player_filter(
  status   = c("FREEAGENT", "WAIVERS"),          # + "ONTEAM" em espn_all_players()
  slot_ids = c(0, 2, 4, 6, 16, 17, 23),          # QB, RB, WR, TE, D/ST, K, FLEX
  limit    = 1000                                  # 5000 em espn_all_players()
)
```

que serializa para:

```json
{"players":{
  "filterStatus":{"value":["FREEAGENT","WAIVERS"]},
  "filterSlotIds":{"value":[0,2,4,6,16,17,23]},
  "limit":1000,
  "sortPercOwned":{"sortPriority":1,"sortAsc":false}
}}
```

| função | `status` | `limit` | uso |
|--------|----------|---------|-----|
| `espn_player_pool()` | configurável | 1000 | base — genérica |
| `espn_available_players()` | `FREEAGENT`, `WAIVERS` | 1000 | quem está livre |
| `espn_all_players()` | + `ONTEAM` | 5000 | pool completo (usado pelo pipeline) |

Parser: `.espn_parse_player_pool`. Uma linha por jogador.

| campo | origem JSON (`players[]`) | significado |
|-------|--------------------------|-------------|
| `player_id` | `id` ‖ `player.id` | jogador |
| `player_name` | `player.fullName` | nome |
| `first_name` / `last_name` | `player.firstName` / `.lastName` | — |
| `on_team_id` | `onTeamId` | time da liga que o tem (`0` = livre) |
| `pro_team_id` | `player.proTeamId` | time NFL |
| `pro_team` | _(mapa)_ | sigla NFL |
| `default_position_id` | `player.defaultPositionId` | posição |
| `position` | _(mapa)_ | rótulo |
| `status` | `status` | `FREEAGENT` / `WAIVERS` / `ONTEAM` |
| `percent_owned` / `percent_started` | `percentOwned` / `percentStarted` | % de ligas |
| `total_points` | `totalPoints` | pontos na temporada |
| `applied_stat_total` | `appliedStatTotal` | total de stats aplicadas |
| `injury_status` | `player.injuryStatus` | status de lesão |
| `active` / `injured` / `droppable` | `player.active` / `.injured` / `.droppable` | flags |
| `eligible_slot_ids` | `player.eligibleSlots` (join `,`) | slots elegíveis |
| `stats_raw` | `player.stats` (list-column) | insumo do expand |

Do pool, o pipeline guarda em `espn_players` apenas identidade/posição/time e em
`espn_player_injury_status` apenas `injury_status`/`injured`/`active`. `on_team_id`,
`status`, `percent_*`, `total_points`, `applied_stat_total`, `droppable` **não são
persistidos**.

### 5.10 Player stats — `espn_player_stats()` · `espn_projection_table()` · `espn_actual_points_table()`

`espn_player_stats()` chama `espn_player_pool(status = ONTEAM+FREEAGENT+WAIVERS)` e
roda `.espn_expand_stats()`, que explode `stats_raw` em **uma linha por registro de
estatística**. Um jogador tem vários registros: por temporada, por semana, real vs.
projetado, split.

| campo | origem JSON (`player.stats[]`) | significado |
|-------|-------------------------------|-------------|
| `player_id` / `player_name` / `position` / `pro_team` | _(do pool)_ | identificação |
| `season_id` | `seasonId` | temporada **do registro** (≠ temporada da run) |
| `scoring_period_id` | `scoringPeriodId` | semana do registro (`0` = total da temporada) |
| `stat_source_id` | `statSourceId` | **`0` = real, `1` = projeção** |
| `stat_split_type_id` | `statSplitTypeId` | tipo de split (0 season, 1 last-7, …) |
| `pro_team_id` | `proTeamId` | time NFL no registro |
| `fantasy_points` | `appliedTotal` | pontos de fantasy (aplicando o scoring da liga) |
| `stats` | `stats` (list-column) | box score cru `{statId: valor}` — **descartado no pipeline** |
| `applied_stats` | `appliedStats` (list-column) | pontos por `statId` — **descartado no pipeline** |

Atalhos:

| função | filtro | retorno |
|--------|--------|---------|
| `espn_projection_table(client, week)` | `scoring_period_id == week & stat_source_id == 1` | projeção da semana |
| `espn_actual_points_table(client, week)` | `scoring_period_id == week & stat_source_id == 0` | resultado real da semana |

### 5.11 Transactions — `espn_transactions(client, week, resolve_players = TRUE)`

Views: `mTeam`, `mTransactions2`. Parâmetro `week` → `scoringPeriodId`. Parser:
`.espn_parse_transactions`. Uma linha por **item** de transação (uma transação de
troca tem vários itens).

| campo | origem JSON (`transactions[]` / `.items[]`) | significado |
|-------|--------------------------------------------|-------------|
| `transaction_id` | `id` | id da transação |
| `transaction_type` | `type` | `WAIVER` / `FREEAGENT` / `TRADE` / … |
| `execution_type` | `executionType` | `EXECUTE` / `PROCESS` / … |
| `status` | `status` | `EXECUTED` / `PENDING` / … |
| `team_id` | `teamId` | time |
| `team_name` | _(join)_ | nome |
| `scoring_period_id` | `scoringPeriodId` | semana |
| `process_date` / `proposed_date` | `processDate` / `proposedDate` | epoch ms → POSIXct |
| `bid_amount` | `bidAmount` | lance de waiver (FAAB) |
| `priority` | `priority` | prioridade de waiver |
| `member_id` | `memberId` | membro que iniciou |
| `item_type` | `items[].type` | `ADD` / `DROP` / `LINEUP` |
| `player_id` | `items[].playerId` | jogador do item |
| `from_team_id` / `to_team_id` | `items[].fromTeamId` / `.toTeamId` | origem / destino (trocas) |
| `is_keeper` | `items[].isKeeper` | item de keeper (default `FALSE`) |

Não é lido pelo pipeline (`include_transactions = FALSE` na chamada de `espn_snapshot()`).

---

## 6. Mapas de referência

Lookups locais do cliente (`espn_*_map()`), não vêm da API.

### `lineup_slot_id` → `lineup_slot` (`espn_lineup_slot_map()`)

| id | slot | id | slot | id | slot |
|----|------|----|------|----|------|
| 0 | QB | 9 | DE | 18 | P |
| 1 | TQB | 10 | LB | 19 | HC |
| 2 | RB | 11 | DL | 20 | BE (banco) |
| 3 | RB/WR | 12 | CB | 21 | IR |
| 4 | WR | 13 | S | 22 | (vazio) |
| 5 | WR/TE | 14 | DB | 23 | FLEX |
| 6 | TE | 15 | DP | 24 | ER |
| 7 | OP | 16 | D/ST | 25 | ROOKIE |
| 8 | DT | 17 | K | | |

### `default_position_id` → `position` (`espn_default_position_map()`)

`1 = QB` · `2 = RB` · `3 = WR` · `4 = TE` · `5 = K` · `16 = D/ST`

### `pro_team_id` → `pro_team` (`espn_pro_team_map()`)

`0 = FA`, `1 ATL`, `2 BUF`, `3 CHI`, `4 CIN`, `5 CLE`, `6 DAL`, `7 DEN`, `8 DET`,
`9 GB`, `10 TEN`, `11 IND`, `12 KC`, `13 LV`, `14 LAR`, `15 MIA`, `16 MIN`, `17 NE`,
`18 NO`, `19 NYG`, `20 NYJ`, `21 PHI`, `22 ARI`, `23 PIT`, `24 LAC`, `25 SF`,
`26 SEA`, `27 TB`, `28 WSH`, `29 CAR`, `30 JAX`, `33 BAL`, `34 HOU`.

---

## 7. Helpers de conversão

| helper | faz |
|--------|-----|
| `%||%` | `x` se não-nulo/não-vazio, senão `y` (semântica null-**ou**-vazio) |
| `.espn_chr` / `.espn_int` / `.espn_num` / `.espn_lgl` | pega `x[[1]]`, converte, `NA` tipado se ausente |
| `.espn_date_ms(x)` | epoch **ms** → `POSIXct` UTC; `NA` se `<= 0` |
| `.espn_compact_chr(x)` | vetor/lista → string única separada por `,` |

---

## 8. `espn_snapshot()` — requisição combinada

```r
espn_snapshot(client, week = NULL,
              include_available = TRUE, available_limit = 1000L,
              include_transactions = TRUE)
```

Uma requisição à URL de liga com 7–8 views, parseada localmente. Retorna uma
**lista**:

| elemento | conteúdo |
|----------|----------|
| `league` | 5.1 |
| `members` | 5.2 |
| `teams` | 5.3 |
| `roster_slots` | 5.4 |
| `scoring_rules` | 5.5 |
| `rosters` | 5.6 (tabela cheia) |
| `starters` / `bench` | `rosters` filtrado |
| `matchups` | 5.7 |
| `draft` | 5.8 |
| `transactions` | 5.11 (ou tibble vazio) |
| `available_players` | 5.9 (`espn_available_players`, ou tibble vazio) |
| `raw` | **payload JSON cru** — tudo que as views trouxeram, incluindo campos que nenhum parser extrai |

O pipeline chama com `include_available = FALSE, include_transactions = FALSE` e
busca o pool completo à parte (`espn_all_players` + `espn_player_stats`).

---

## 9. Adaptador `ffscrapr` (opcional)

`espn_ffscrapr_connect(client)` e `espn_ffscrapr_snapshot(client)` expõem a mesma
liga pela API tidy do pacote `ffscrapr` (`ff_league`, `ff_franchises`, `ff_rosters`,
`ff_starters`, `ff_schedule`, `ff_standings`, `ff_draft`, `ff_transactions`).
Requer `install.packages("ffscrapr")`. Não é usado pelo pipeline.

---

## 10. Health check

`espn_test_connection(client)` tenta `espn_league()` e devolve
`list(ok, league, error)` (classe `espn_connection_test`). O pipeline aborta se
`ok` não for `TRUE`.

---

## 11. O que a API **não** dá

Relevante para entender por que o pipeline injeta `season`, `week`, `tag`,
`timestamp` (ver `DATA_CATALOG.md`):

- **Sem histórico.** A API da liga devolve só o estado corrente — a classificação de
  agora, o roster de agora. Não há como pedir "o roster da semana 3 como estava na
  semana 3"; `scoringPeriodId` filtra o lineup escalado, mas os agregados
  (`points`, `record`, `percentOwned`) são sempre os atuais.
- **Sem timestamp.** Nenhum campo diz quando o snapshot foi tirado — `timestamp` é
  100% do pipeline.
- **Sem `tag`.** Conceito exclusivo deste projeto (`preview` / `final` / `season`).
- **`week` como coluna** só existe de fato em `player.stats[]` (`scoringPeriodId`) e
  em `schedule[]` (`matchupPeriodId`). Nas demais entidades é um parâmetro de query
  que o pipeline reanexa.
- **`season` como coluna** só é real em `league` (`seasonId`) e nos registros de
  stats (`seasonId`, exposto como `stat_season`). Nas demais, o pipeline fixa a
  temporada da run.
