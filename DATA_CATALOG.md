------------------------------------------------------------------------

editor_options: markdown: wrap: 72 ---

# DATA_CATALOG.md

Dicionário dos arquivos de dados (`.rds`) do projeto: o que cada objeto contém (tabelas, colunas, chaves) e o range de temporadas/semanas coberto por cada cópia.

Gerado por introspecção em 2026-09-06 (pastas `historic/*_20231221/` adicionadas em 2026-09-07; `analytical_db` e `decision_db` adicionados em 2026-09-08; `free_agent_recommendations` / M4 em 2026-09-08; `trade_recommendations` / M5 em 2026-09-08). Reproduza os números com o script da seção [Como foi levantado](#como-foi-levantado).

------------------------------------------------------------------------

## 1. Visão geral

Os dados são objetos R serializados com `saveRDS()`. A maioria é um objeto **`dm`** (conjunto de tabelas relacionais com chaves --- pacote `{dm}`); alguns são `list()` ou `tibble` soltos.

``` r
db <- readRDS("data/ffa_db.rds")   # um dm
db$ffa_projtable                    # acessa uma tabela
names(db)                           # lista as tabelas
```

### Localizações

| local | git | papel | temporadas |
|------------------|------------------|------------------|------------------|
| `data/*.rds` | ignorado | **vivo** --- todo `updateDB()` do pipeline lê/grava aqui | 2024--2026 |
| `data/temp/*.rds` (165) | ignorado | cache de payload cru da API para reprocessar sem rede | 2023--2026 |
| `historic/2023/*.rds` (9) | ignorado | snapshot congelado da temporada 2023 (dez/2023--jan/2024) | 2019--2023 |
| `historic/*.rds` (7) | não versionado | merge multi-temporada, gravado 2026-03-08; **sem PK/FK, tipos degradados** | 2019--2025 |
| `historic/DudesApp_Database_Backup_20231221/` (7) | não versionado | backup dos `dm` **congelado em 21/dez/2023** --- PK/FK preservadas, mesmo schema de `historic/2023/`, mas para na semana 15--16 (predecessor de `historic/2023/`). [Catálogo próprio](historic/DudesApp_Database_Backup_20231221/DATA_CATALOG.md) | 2019--2023 |
| `historic/dudes_database_backup_20231221/` (255) | não versionado | despejo do diretório de trabalho do pipeline `R_old` no fim da temporada 2023 (~335 MB); artefatos avulsos (`tibble`/`list`), **não são `dm`**. [Catálogo próprio](historic/dudes_database_backup_20231221/DATA_CATALOG.md) | 2023 |
| `data/*.zip`, `historic/*.zip`, `historic/2023/*.zip` | ignorado | backups manuais (nenhum código gera); os dois `*_20231221.zip` descompactam nas pastas acima | --- |
| `export/*.json` | ignorado | dumps ad-hoc (nenhum código gera; provavelmente obsoletos) | --- |

`data/analytical_db.rds` também mora em `data/` mas **não é escrito por nenhum pipeline**: é um derivado, montado sob demanda pelo script standalone `R/analysis/build_historic_datasets.R`, que lê `data/` + `historic/` e funde as duas gerações. Ver a entrada `analytical_db` na [seção 2](#2-dicionário-de-tabelas).

`data/decision_db.rds` é escrito por `R/decision/decision_pipeline.R` (não pelos pipelines de ingestão): consome `ffa_db` + `espn_db` + `analytical_db` e persiste previsões/recomendações do decision engine. Ver a entrada `decision_db` na [seção 2](#2-dicionário-de-tabelas).

Nenhum código em `R/` lê de `historic/`, `historic/2023/`, das pastas `historic/*_20231221/` ou de `export/` --- só de `data/` e `data/temp/`. `historic/` era `import/` até ser renomeado. Os `.rds` não são versionados: um clone limpo não tem dado nenhum.

------------------------------------------------------------------------

## 2. Dicionário de tabelas

O schema abaixo é o da cópia em **`data/`** (canônica, com PK/FK). As cópias em `historic/2023/` e `historic/` têm as mesmas tabelas com divergências documentadas na [seção 6](#6-caveats--qualidade-dos-dados).

### `ffa_db` --- projeções FantasyFootballAnalytics

Construído por `R/api/ffa_projection.R`, orquestrado por `R/pipeline/data_pipeline.R`.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `ffa_scrape` | 40 | `season, week, tag, timestamp` | 1 linha por scrape; guarda o resultado bruto de `ffanalytics::scrape_data` na list-column `scrapeData` |
| `ffa_player_ids` | 5700 | `id` | crosswalk de ids de jogador entre sites --- cópia de `ffanalytics:::player_ids` |
| `ffa_players` | 924 | `id, pos` | master do jogador no scrape: nome, posição, time, idade, experiência |
| `ffa_projtable` | 62933 | `season, week, tag, timestamp, avg_type, id, pos` | projeção de consenso agregada; `avg_type` ∈ `average` / `robust` / `weighted` |
| `ffa_proj_source_points` | 104977 | `season, week, tag, timestamp, data_src, id, pos` | a mesma projeção quebrada por fonte individual (`data_src` = CBS, ESPN, NFL, FantasyPros, ...) |

**FKs:** `ffa_players.id → ffa_player_ids`; `ffa_projtable`/`ffa_proj_source_points (id,pos) → ffa_players` e `(season,week,tag,timestamp) → ffa_scrape`.

Colunas:

- `ffa_player_ids`: `id, stats_id, cbs_id, fleaflicker_id, nfl_id, espn_id, fftoday_id, numfire_id, fantasypro_id, fantasydata_id, fantasynerd_id, rts_id, fantasypro_num_id, gsis_id, sleeper_id` (todas `chr`). Colunas que o código vivo usa: **`nfl_id`** (ponte FFA↔NFL, em `simulation_machine.R`, `transformation/simulation.R`), `numfire_id` (chave de nome). **`espn_id`** é a ponte futura para o `espn_db`.
- `ffa_players`: `id, pos, first_name, last_name, team, position, age, exp`
- `ffa_projtable`: chaves + `points, sd_pts, dropoff, floor, ceiling, points_vor, floor_vor, ceiling_vor, rank, floor_rank, ceiling_rank, pos_rank, tier, first_name, last_name, team, position, age, exp`
- `ffa_proj_source_points`: chaves + `points`
- `ffa_scrape`: chaves + `scrapeData` (list)

### `nfl_teams_db` --- times e donos da liga (NFL Fantasy API)

`R/api/nfl_league.R`.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `nfl_teams` | 16 | `teamId` | um time de fantasy da liga: `teamId, name, ownerUserId, imageUrl` |
| `nfl_owners` | 16 | `ownerUserId` | um membro/dono: `ownerUserId, name` |

**FK:** `nfl_teams.ownerUserId → nfl_owners`. Sem `season` (cadastro acumulado).

### `nfl_players_db` --- registro de jogadores e lesões

`R/api/nfl_players.R`.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `nfl_players` | 1398 | `playerId` | registro do jogador: `name, position, nflTeamId, nflTeamAbbr, byeWeek, esbId, nflGlobalEntityId, isUndroppable, …` |
| `nfl_player_injury_status` | 43430 | `playerId, timestamp` | log de `injuryGameStatus` --- um snapshot por execução do pipeline |

**FK:** `nfl_player_injury_status.playerId → nfl_players`. Sem `season` (só `timestamp`).

### `nfl_stats_db` --- pontuação e estatísticas de jogadores

`R/api/nfl_players.R` + `R/api/nfl_game.R`.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `nfl_stat_dictionary` | 95 | `statId` | lookup `statId` → `abbr, name, shortName, scoringType, groupName, positionCategory, colName` |
| `nfl_players_points` | 12593 | `playerId, season, week` | pontos de fantasy por jogador-semana (`pts`) |
| `nfl_players_stats` | 75596 | `playerId, season, week, statId` | box-score cru em formato long (`value` por `statId`) |
| `nfl_players_adv_stats` | 19816 | `playerId, season, week` | estatísticas avançadas wide: `averageDraftPosition, percentStarted, percentOwned, percentRostered, targets, touches, receptionPercentage, redzoneTargets, redzoneTouches, rushingYardsPerAttempt, passingPercentage, …` |

**FK:** `nfl_players_stats.statId → nfl_stat_dictionary`.

### `nfl_round_db` --- rodada: rosters, confrontos, stats de time

`R/api/nfl_league.R` (`getFantasyRound`).

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `matchups_games` | 257 | `season, week, matchupId` | confrontos H2H da semana: `homeTeamTeamId, awayTeamTeamId, *Outcome, *PlayoffSeeding, bracketType, previewUrl, recapUrl` |
| `nfl_teams_round` | 510 | `season, week, teamId` | estado do time na semana: `rank`, imagens |
| `nfl_teams_rosters` | 8744 | `season, week, tag, timestamp, teamId, rosterSlotId, playerId` | qual `playerId` em qual `rosterSlotId` / `slotPosition` em qual time; `isEditable, isReserveStatus` |
| `nfl_teams_week_stats` | 540 | `season, week, tag, timestamp, teamId, statId` | stats acumuladas do time só naquela semana (long, `value`) |
| `nfl_teams_season_stats` | 8760 | `season, week, tag, timestamp, teamId, name` | stats acumuladas do time na temporada até a semana (long, `value` como `chr`) |

**FKs:** `nfl_teams_rosters` / `nfl_teams_week_stats` / `nfl_teams_season_stats` `(season,week,teamId) → nfl_teams_round`.

### `nfl_recap_db` --- narrativas de confronto

`R/pipeline/data_pipeline.R` --- só é construído quando `.tag == "final"`.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `nfl_recap` | 220 | `leagueId, season, week, matchupId` | recap/narrativa do confronto: `title, type, weekday, written_at, playoff` + list-columns `paragraphs, teams, free_agent_target_touch_leaders, league_notes` |

Existe um modelo expandido alternativo de 8 tabelas em `R/api/nfl_league.R::nfl_expandeRecapDB` e `R/snippets/recap2DB.R` --- **não usado** pelo pipeline.

### `dudes_simulation_db` --- seeds e simulações de Monte Carlo

`R/snippets/simulation_machine.R` (lê `ffa_db`, `nfl_stats_db`, `nfl_players_db`).

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `dudes_players_seeds` | 21809 | `season, week, id, playerId, pos, simType` | pool de valores-candidatos de pontos (`seeds`, list-column de vetor numérico) que cada estratégia gerou; linhas de bye week removidas |
| `dudes_players_simulations` | 15799 | `season, week, id, playerId, pos, simType` | só para `simType` multi-valor: `simulation` (1000 reamostras bootstrap dos `seeds`), `simQuantiles` (percentis 5/15/30/50/70/85/95) |

**`simType`** --- single-valor: `NFL`, `proj_table_average`, `proj_table_robust`, `proj_table_weighted` (estes 4 ficam de fora de `dudes_players_simulations`); Monte-Carlo: `proj_src`, `proj_src_errors`, `proj_src_w_errors`, `proj_src_w_errors_balanced`, `hist_data`, `current_season_his`; density: as 7 variantes `*_density`. Erros históricos vêm de `R/transformation/simulation.R` (`calcProjectionErrors` = `pts - projetado` por fonte; `applyErrorToProjection` soma esses erros à projeção atual).

### `espn_db` --- liga no ESPN Fantasy (só em `data/`, só 2026)

`R/pipeline/data_pipeline_espn.R`. Um único `dm` de 12 tabelas montado de um snapshot combinado (`espn_snapshot()`) + o pool de jogadores.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `espn_league` | 1 | `league_id, season` | configurações da liga: tamanho, períodos de pontuação/matchup, config de draft, waiver/roster-lock |
| `espn_members` | 14 | `member_id` | membros/donos: nome de exibição + real, flag de manager |
| `espn_teams` | 14 | `season, team_id` | times: `team_name, abbrev, division_id, owner_ids, owners` |
| `espn_roster_slots` | 25 | `season, lineup_slot_id` | definição de slots de lineup (id → label, `count`) |
| `espn_scoring_rules` | 29 | `season, stat_id` | pontos por `stat_id` (+ `is_reverse_item`) |
| `espn_players` | 1036 | `season, player_id` | master de jogador: união de todo `player_id` referenciado (pool/rosters/stats/draft); nome, time, posição |
| `espn_team_standings` | 14 | `season, week, tag, timestamp, team_id` | snapshot da classificação: ranks, W-L-T, points for/against, streak, acquisitions/drops/trades |
| `espn_player_injury_status` | 1036 | `season, week, tag, timestamp, player_id` | `injury_status`, `injured`, `active` por jogador |
| `espn_players_points` | 2617 | `season, week, tag, timestamp, player_id, stat_source_id, stat_split_type_id` | pontos por jogador por período --- **projetado (`stat_source_id==1`) e real (`==0`)**; `week` = período do registro, `stat_season` = temporada do registro |
| `espn_rosters` | 209 | `season, week, tag, timestamp, team_id, player_id` | quem estava rosterado por qual time: `lineup_slot`, `is_starter`/`is_bench`/`is_ir`, aquisição, `% owned/started`, pontos |
| `espn_matchups` | 98 | `season, week, tag, timestamp, matchup_id` | confronto H2H: pontos real + projetado por lado, `winner`, `playoff_tier_type` |
| `espn_draft` | 210 | `season, overall_pick` | draft board: `round, round_pick, team_id, player_id, bid_amount, keeper, trade_locked` |

**FKs:** `espn_team_standings` / `espn_rosters` / `espn_matchups` (home + away) / `espn_draft` `(season, team_id) → espn_teams`; `espn_rosters` / `espn_player_injury_status` / `espn_players_points` / `espn_draft` `(season, player_id) → espn_players`.

### `analytical_db` --- base analítica projeção x realizado

`R/analysis/build_historic_datasets.R` (standalone, fora dos dois pipelines). Funde as
duas gerações de dados: `data/ffa_db` + `historic/ffa_db` para projeções e
`data/nfl_stats_db` + `historic/nfl_stats_db` para pontos reais, colapsa cada semana
para o snapshot de `timestamp` mais recente (ignora `tag`), remove projeções sem
`proj_points` e a fonte CBS na semana 16 de 2024/2025 (suspeita de projeção corrigida
pós-jogo). Grava `data/analytical_db.rds` + `export/analytical_db.png`.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `ffa_projections` | 120 131 | `season, week, data_src, ffa_id, pos` | projeção-baseline por jogador/fonte/semana (o último scrape da semana). Cols: chaves + `proj_points`. Sem `tag`/`timestamp` (colapsados) |
| `nfl_player_points` | 42 446 | `nfl_id, season, week` | pontos de fantasy realizados por jogador-semana (`points`); `week == 0` = agregado de temporada |
| `player_ids` | 5 700 | `ffa_id` | recorte de `ffa_db$ffa_player_ids`: `ffa_id, nfl_id, espn_id, numfire_id`. ~2 000 linhas sem `nfl_id`, ~1 000 sem `espn_id` |
| `source_errors` | 197 | `data_src, pos, season` | acurácia por fonte/posição/temporada: `bias` (média de `points - proj_points`), `mae`, `rmse`, `n`. Temporadas 2020--2025 |
| `consensus_projections` | 52 124 | `season, week, ffa_id, pos` | projeção de consenso (média das fontes) por jogador-semana + dispersão: `n_sources`, `sources` (lista separada por vírgula), `projection` (média), `source_median`, `source_sd`, `source_mad`, `source_min`, `source_max`, `source_range` (sd/mad/range = `NA` quando `n_sources < 2`) |
| `consensus_error_history` | 28 805 | `season, week, ffa_id, pos` | `consensus_projections` cruzado com pontos reais e ids: todas as colunas de consenso + `nfl_id, espn_id, numfire_id, actual_points, residual` (`actual_points - projection`), `abs_residual`, `squared_residual`, `consensus_type` (`"mean"`), `coverage_class` (`single` = 1 fonte · `sparse` = 2--3 · `ensemble` = 4+) |

**FKs:** nenhuma. `ffa_projections` / `consensus_*` têm `ffa_id` que não existe em
`player_ids` (mesmo buraco de mapeamento de id descrito para o `espn_db`), então as
`dm_add_fk` estão comentadas no script.

### `decision_db` --- previsões e recomendações do decision engine (só em `data/`, só 2026)

`R/pipeline/../R/decision/decision_pipeline.R::run_decision_pipeline(season, week, tag)`.
Camada de decisão: cruza o consenso FFA atual com os resíduos históricos do
`analytical_db$consensus_error_history` para gerar uma distribuição preditiva de pontos
por jogador (`points_sim = projection + sample(residual_histórico)`, **não**
`Normal(projection, source_sd)`). Não faz scraping --- lê `ffa_db`, `espn_db` e
`analytical_db` já atualizados. Cada execução gera um `run_id` e o `dm` **acumula
runs** via `dm_rows_upsert` (nunca colidem; re-run do mesmo `run_id` sobrescreve só
suas linhas). **Milestones 1--5**: as 7 tabelas abaixo. Se o `.rds` no
disco tiver um conjunto de tabelas diferente (schema evoluiu entre milestones), `updateDB()`
sobrescreve em vez de fazer upsert.

| tabela | linhas | PK | o que é |
|------------------|------------------|------------------|------------------|
| `simulation_runs` | 1/run | `run_id` | metadados da execução: `created_at, season, week, tag, ffa_timestamp, espn_timestamp` (snapshots consumidos), `model_version` (`"player-mc-v2"`), `n_sim`, `seed`. `run_id` = `{season}-W{week}-{tag}-{timestamp}` (ex.: `2026-W01-preview-20260908T161947`) |
| `player_forecasts` | ~561/run | `run_id, ffa_id, pos` | previsão probabilística por jogador. Chaves + `season, week, tag, espn_id` (do crosswalk, nullable) + do consenso: `projection` (média das fontes), `n_sources`, `coverage_class`, `source_sd`, `source_mad` + da simulação Monte Carlo: `sim_mean`, `sim_sd`, `p05/p10/p25/p50/p75/p90/p95`, `prob_gt_10/15/20/25/30` + diagnóstico do pool de resíduos: `residual_pool_level` (1--4, ver spec §9.1), `residual_pool_n`. **`sim_mean != projection`** de propósito: a diferença é o viés histórico do consenso |
| `matchup_simulations` | 7/run (1 por confronto da semana) | `run_id, matchup_id` | simulação Monte Carlo de cada confronto H2H da ESPN. Chaves + `season, week, tag, home_team_id, away_team_id` + `home_expected, away_expected`, `home_p10/p50/p90`, `away_p10/p50/p90`, `home_win_probability, away_win_probability, tie_probability` (somam 1), `n_sim`. Soma os draws alinhados dos **starters marcados pela ESPN** de cada time e compara draw a draw. FK `run_id → simulation_runs` |
| `lineup_evaluations` | 14/run (1 por time) | `run_id, team_id` | avaliação do lineup de cada time na semana (M3, spec §18/§41). Chaves + `season, week, tag, opponent_team_id` + para o lineup ESPN atual: `current_expected`, `current_p10/p50/p90`, `current_win_probability`; para o lineup ótimo (max `sum(sim_mean)` sujeito às regras de slot da liga): `optimal_expected`, `optimal_p10/p50/p90`, `optimal_win_probability` + `bench_value` (soma de `sim_mean` dos rostered fora do lineup ótimo) + `n_substitutions`. Adversário mantido no lineup ESPN atual dele. `optimal_win_probability` **não** é garantidamente ≥ `current_win_probability`. FK `run_id → simulation_runs` |
| `lineup_recommendations` | 0+/run (só as trocas; time já-ótimo não gera linha) | `run_id, team_id, player_out` | trocas de escalação sugeridas (M3, spec §17). Chaves + `season, week, tag` + `player_in` (ambos `espn_id`), `player_out_name`, `player_in_name`, `slot` (slot do lineup ótimo que `player_in` ocupa) + `current_expected`/`optimized_expected`/`delta_expected` e `current_win_probability`/`optimized_win_probability`/`delta_win_probability` (todos nível-time, repetidos nas linhas do mesmo time) + `recommendation_rank` (por ganho marginal `sim_mean` da troca). Jogadores `is_ir` ou `injury_status == "OUT"` são excluídos dos candidatos. FK `run_id → simulation_runs` |
| `free_agent_recommendations` | 0..25/run (só do time escolhido, `config$myTeamEspnId`) | `run_id, team_id, drop_player_id, add_player_id` | add/drop sugeridos (M4, spec §19--22/§42). Chaves + `season, week, tag` + `drop_ffa_id, add_ffa_id` (nullable quando o drop é dead weight) + `drop_position, add_position` (posição ESPN) + `before_expected`/`after_expected`/`delta_expected` e `before_win_probability`/`after_win_probability`/`delta_win_probability` (`before_*` nível-time, repetido nas linhas) + `recommendation_rank` (por `delta_expected` desc; `delta_win_probability` é reportado, não ordena). Free agent = `espn_players` ANTI JOIN `espn_rosters` do snapshot, bridged a `ffa_id`, só quem tem forecast e não está IR/inativo; `eligible_slot_ids` = moda por posição das linhas do roster. Grid DROP×ADD limitado por `fa_max_drops` (10) × `fa_max_adds_per_pos` (5), pontuado por `evaluate_roster()`, uma linha por add (melhor drop). Adversário mantido nos starters ESPN atuais. Nenhuma simulação nova. FK `run_id → simulation_runs` |
| `trade_recommendations` | 0..25 por time/run (todos os times da liga; `trade_team_id` restringe) | `run_id, my_team_id, other_team_id, give_player_id, receive_player_id` | trocas 1×1 sugeridas (M5, spec §24--28/§43). Chaves + `season, week, tag` + `give_ffa_id, receive_ffa_id` (nunca nulos --- cada lado precisa de vetor de draws) + `give_position, receive_position` (posição ESPN) + `my_before_expected`/`my_after_expected`/`my_delta_expected`, `their_before_expected`/`their_after_expected`/`their_delta_expected`, `my_before_win_probability`/`my_after_win_probability`/`my_delta_win_probability` + `fairness` (= `-abs(my_delta - their_delta)`, mais negativo = mais desbalanceado) + `trade_score` (= `my_delta + pmin(my_delta, their_delta)`, spec §27) + `partner_is_my_opponent` (quando TRUE o `my_*_win_probability` fica otimista --- jogador recebido conta nos dois lados do meu matchup; deltas de pontos e rank não são afetados) + `recommendation_rank` (recomeça em 1 por `my_team_id`, `trade_score` desc; `my_delta_win_probability` é reportado, não ordena). Para cada time aconselhado, cada um dos outros times é parceiro, avaliado contra o adversário da própria semana mantido nos starters ESPN atuais. Grid GIVE×RECEIVE: os `trade_max_give` (5) jogadores mais fracos do time aconselhado × os `trade_max_receive_per_pos` (5) melhores por posição do parceiro que sejam upgrade estrito e compartilhem um slot titular (flex-compatível). Filtro: `my_delta > 0` (spec §26) e `their_delta >= 0`. Uma linha por jogador recebido (melhor give). Nenhuma simulação nova. FK `run_id → simulation_runs` |

**FKs:** `player_forecasts.run_id`, `matchup_simulations.run_id`, `lineup_evaluations.run_id`, `lineup_recommendations.run_id`, `free_agent_recommendations.run_id` e `trade_recommendations.run_id → simulation_runs`.

Os 10 mil draws individuais **não** são persistidos (spec §32) --- só mean/sd/quantis/probabilidades. `run_decision_pipeline(persist_draws = TRUE)` os devolve em memória para debug/backtest. O `current_players` (estado da liga: 1 linha por jogador rosterado na ESPN, spec §12; a partir de M3 carrega também `lineup_slot_id` e `eligible_slot_ids`) também fica só em memória (`res$current_players`). O otimizador de lineup (`R/decision/lineup_optimizer.R`) é uma atribuição exata recursiva com branch-and-bound (sem solver LP); lê contagem de slots de `espn_roster_slots` e elegibilidade de `eligible_slot_ids` --- nada hard-coded (spec §16). `evaluate_roster()` (`R/decision/roster_evaluator.R`) é a função de valor compartilhada; M4 (`R/decision/free_agents.R`: `get_free_agents()` + `recommend_free_agents()`) a reusa para pontuar cada par DROP×ADD e M5 (`R/decision/trades.R`: `recommend_trades()`) para pontuar cada par GIVE×RECEIVE, sem simulação nova (os `draws_by_ffa` já cobrem todo jogador projetado pela FFA, não só os rosterados).

**Ponte de ids ESPN → FFA** (a partir de M2, feita fresh a cada run em `R/decision/league_state.R`): 4 estratégias em cascata --- (0) arquivo manual opcional `data/decision_espn_ffa_overrides.rds` (`tibble(player_id, ffa_id)`, consultado primeiro); (1) `player_id` ESPN == `analytical_db$player_ids$espn_id`; (2) D/ST: `44000 - player_id` == `ffa_player_ids$espn_id` (offset 60000, ver `R_old/import/espn_scraper.R`); (3) nome normalizado + posição único em `ffa_players`. A coluna `bridge_method` em `current_players` registra qual pegou. `run_decision_pipeline()` **falha** (spec §35) se algum starter não mapear ou não tiver forecast; bench não-mapeado é só warning. Por padrão `matchups = TRUE`, então toda run precisa de um snapshot ESPN válido para `season/week/tag`.

### Glossário de colunas-chave

| coluna | significado |
|------------------------------------|------------------------------------|
| `season` | ano da temporada NFL |
| `week` | semana da temporada; **`week == 0`** = agregado de temporada, não é semana real (o código de simulação filtra `week != 0`) |
| `tag` | momento da captura: `preview` (projeção cedo na semana) · `final` (pós-jogos; único que dispara recap) · `season` (nível-temporada, com `week=0`). Ver typos/variantes na seção 6 |
| `timestamp` | `lubridate::now()` da execução; entra na PK das tabelas de fato → re-execuções **acumulam** snapshots em vez de colidir |
| `id` (ffa) | id de jogador do ffanalytics (`ffa_player_ids$id`) |
| `playerId` (nfl) | id de jogador da NFL Fantasy API; ponte: `ffa_player_ids$nfl_id` |
| `player_id` (espn) | id de jogador do ESPN; ponte futura: `ffa_player_ids$espn_id` (D/ST usa offset 60000 --- ver `R_old/import/espn_scraper.R`) |
| `statId` / `stat_id` | id de estatística; resolver via `nfl_stat_dictionary` / `espn_scoring_rules` |
| `avg_type` | método de agregação da projeção ffanalytics: `average` / `robust` / `weighted` |
| `data_src` | fonte individual da projeção (CBS, ESPN, NFL, ...) |
| `stat_source_id` (espn) | `0` = real, `1` = projeção |
| `lineup_slot_id` (espn) | `20` = banco, `21` = IR (deriva `is_starter`/`is_bench`/`is_ir`) |

### list-columns (não podem ser PK)

`ffa_scrape$scrapeData` · `nfl_recap$paragraphs` / `$teams` / `$free_agent_target_touch_leaders` / `$league_notes` · `dudes_players_seeds$seeds` · `dudes_players_simulations$simulation` / `$simQuantiles` · `dudes_simSeeds$seeds` (só em `historic/2023/dudes_simulation.rds`).

------------------------------------------------------------------------

## 3. Matriz de cobertura (temporada × semana)

Semanas 1--17 é a temporada completa; `w0` é o agregado de pré-temporada.

### `ffa_db` --- `ffa_projtable` / `ffa_proj_source_points`

| temporada | `data/`                  | `historic/2023/`         | `historic/`     |
|----------------|---------------------|---------------------|----------------|
| 2020      | ---                      | ---                      | w1--16 (14 344) |
| 2021      | ---                      | ---                      | **só w1** (968) |
| 2022      | ---                      | ---                      | w1--17 (10 154) |
| 2023      | ---                      | w1--17 (52 280 / 93 559) | w1--17 (17 471) |
| 2024      | w2--17 (32 007 / 57 800) | ---                      | w2--17 (10 704) |
| 2025      | w0--17 (29 325 / 45 466) | ---                      | w0--17 (9 981)  |
| 2026      | **w0** (1 601 / 1 711)   | ---                      | ---             |

### `nfl_stats_db` --- `nfl_players_points` (linhas)

| temporada | `data/` | `historic/2023/` | `historic/` |
|-----------|---------|------------------|-------------|
| 2019      | ---     | 3 334            | 3 334       |
| 2020      | ---     | 4 033            | 15 058      |
| 2021      | ---     | 4 695            | 16 029      |
| 2022      | ---     | 5 570            | 15 462      |
| 2023      | ---     | 6 281            | 6 281       |
| 2024      | 6 269   | ---              | 6 269       |
| 2025      | 6 324   | ---              | 6 324       |

Todas com semanas **0--17 completas**. `nfl_players_stats` ~6× essas contagens; `nfl_players_adv_stats` menor e rasa em 2019--2020.

### `nfl_round_db` (as 5 tabelas acompanham)

| temporada | `data/` | `historic/2023/`          | `historic/`               |
|-----------|---------|---------------------------|---------------------------|
| 2020      | ---     | ---                       | w1--16                    |
| 2021      | ---     | ---                       | w1--17                    |
| 2022      | ---     | ---                       | w1--17                    |
| 2023      | ---     | **w1,2,4--17 (falta w3)** | **w1,2,4--17 (falta w3)** |
| 2024      | w1--17  | ---                       | w1--17                    |
| 2025      | w1--17  | ---                       | w1--17                    |

### `nfl_recap_db` --- `nfl_recap`

| temporada | `data/` | `historic/2023/` | `historic/` |
|------------------|------------------|------------------|------------------|
| 2023 | --- | w1--10,12--14 (falta w11) · 91 | w1--10,12--14 · 91 |
| 2024 | **w1--4,6--13 (falta w5, para em w13)** · 84 | --- | w1--4,6--13 · 84 |
| 2025 | w1--17 · 136 | --- | w1--17 · 136 |

### `dudes_simulation_db`

| temporada | `data/` | `historic/2023/` | `historic/` |
|----|----|----|----|
| 2020 | --- | --- | w1--16 (3 422) |
| 2021 | --- | --- | só w1 (210) |
| 2022 | --- | --- | w1--17 (3 759) |
| 2023 | --- | w1--11 (89 018 seeds) | w1--11 (7 440, downsampled) |
| 2024 | **só w2--4** (21 809 seeds) | --- | w2--4 (1 642) |

### `espn_db`

Só **2026**. Tabelas de dimensão (`espn_league`, `espn_teams`, `espn_roster_slots`, `espn_scoring_rules`, `espn_players`, `espn_draft`) sem `week`; fatos em `w0` (pré-temporada), exceto `espn_players_points` que traz registros de `w0` e `w1`.

### `analytical_db`

| temporada | `ffa_projections` / `consensus_*` | `nfl_player_points` |
|-----------|-----------------------------------|--------------------|
| 2019      | ---                               | w0--17 (3 334)     |
| 2020      | w1--16 (14 344)                   | w0--17 (6 283)     |
| 2021      | **só w1** (968)                   | w0--17 (6 901)     |
| 2022      | w1--17 (10 145)                   | w0--17 (7 054)     |
| 2023      | w1--17 (9 012)                    | w0--17 (6 281)     |
| 2024      | w2--17 (46 320)                   | w0--17 (6 269)     |
| 2025      | w1--17 (39 342)                   | w0--17 (6 324)     |

`ffa_projections` nunca tem `w0`. 5--8 fontes por semana (menos em 2021 e na w7/2023);
2024 é bem mais densa que as outras temporadas (mais fontes distintas por jogador).
`source_errors` cobre 2020--2025. `consensus_error_history`: 18 227 linhas `single`,
737 `sparse`, 9 841 `ensemble`.

### `decision_db`

Só **2026**, gerado sob demanda. Cada `run_decision_pipeline(season, week, tag)` adiciona
1 linha em `simulation_runs`, ~1 linha por jogador do snapshot FFA em `player_forecasts`
(2026 w1 preview: 561 jogadores --- 99 `single` / 149 `sparse` / 313 `ensemble`), 1 linha
por confronto da semana em `matchup_simulations` (2026 w1: 7), 1 por time em
`lineup_evaluations` (14) + as trocas de lineup em `lineup_recommendations`, e 0..25
add/drop do time escolhido em `free_agent_recommendations`. O `dm` acumula todas as runs.

### `nfl_players_db` / `nfl_teams_db` (sem `season`)

|   | `data/` | `historic/2023/` | `historic/` |
|---------------------|---------------|---------------|----------------------|
| `nfl_players` | 1398 | 1053 | 2309 |
| `nfl_player_injury_status` | 43 430 | 25 134 | 120 052 |
| `nfl_owners` | 16 | 14 | **44** (histórico de donos) |

### Pastas `historic/*_20231221/` (fora da matriz)

Não entram nas tabelas acima --- têm catálogo próprio:

- `historic/DudesApp_Database_Backup_20231221/` --- mesmo schema de `historic/2023/` (PK/FK), mas backup de **21/dez/2023**: 2023 só até w15--16, sem `dudes_simulation`. [Catálogo](historic/DudesApp_Database_Backup_20231221/DATA_CATALOG.md).
- `historic/dudes_database_backup_20231221/` --- 255 artefatos de script `R_old` da temporada 2023 (`tibble`/`list`, não `dm`): scrapes semanais, projeções, 112 snapshots `simulation_v5`, recap de draft. [Catálogo](historic/dudes_database_backup_20231221/DATA_CATALOG.md).

------------------------------------------------------------------------

## 4. Arquivos que não são `dm` principal

| arquivo | classe | o que é |
|------------------------|------------------------|------------------------|
| `historic/2023/dudes_simulation.rds` (21 MB) | `dm` de **1 tabela** `dudes_simSeeds` | versão pré-split (só `seeds`) da simulação; 2023 w1--11 (91 111 linhas). `R/snippets/team_sim.R:5` lê `./data/dudes_simulation.rds` --- **esse arquivo não existe em `data/`, só em `historic/2023/`; o script está quebrado hoje** |
| `data/missing_player_ids.rds` · `historic/2023/missing_player_ids.rds` | **tibble** 44 × 13 | patch manual FFA↔NFL: linhas de `ffa_player_ids` (era de 13 colunas) com `nfl_id` recuperado por nome; escrito por `R/transformation/missing_player_ids.R:57`. O merge em `R/api/ffa_projection.R` está **comentado** → sem uso hoje |
| `data/decision_espn_ffa_overrides.rds` | **tibble** `player_id, ffa_id` | patch manual opcional ESPN→FFA para o decision engine (M2+): a estratégia 0 da ponte de ids em `R/decision/league_state.R`. Arquivo ausente = no-op; criar à mão quando um starter não mapear no meio da temporada. **Não versionado, não existe hoje** |
| `data/dudes_app_final_2025.zip` (35 MB) | zip | backup manual do conjunto `data/` (dez/2025) --- 7 `.rds` |
| `historic/2023/DudesApp_Database_Backup_20231221.zip` · `historic/DudesApp_Database_Backup_20231221.zip` (6.7 MB) | zip | backup manual do conjunto 2023 (21/dez/2023) --- 7 `.rds`, sem `dudes_simulation_db`. Descompactado em `historic/DudesApp_Database_Backup_20231221/` --- ver [catálogo da pasta](historic/DudesApp_Database_Backup_20231221/DATA_CATALOG.md) |
| `historic/dudes_database_backup_20231221.zip` (342 MB) | zip | despejo do diretório de trabalho do pipeline `R_old` (fim da temporada 2023). Descompactado em `historic/dudes_database_backup_20231221/` (255 artefatos avulsos, ~335 MB) --- ver [catálogo da pasta](historic/dudes_database_backup_20231221/DATA_CATALOG.md) |
| `export/recap.json`, `export/stats.json`, `export/test.json` | JSON | dumps ad-hoc; nenhum código gera; provavelmente obsoletos |

------------------------------------------------------------------------

## 5. `data/temp/` --- cache (resumo)

165 arquivos. Nome: `{objeto}_s{AAAA}w{SS}_{tag}_{timestamp}.rds`. Range 2023--2026. Servem para reprocessar o pipeline sem novas chamadas de rede.

| prefixo | qtd | classe | conteúdo |
|------------------|------------------|------------------|------------------|
| `ffa_scrape_db_*` | 84 | `dm` de 1 tabela | só `ffa_scrape` (1 linha, com o scrape cru) |
| `ffa_db_*` | 74 | `dm` de 5 tabelas | snapshot único do `ffa_db` (um scrape) |
| `espn_snapshot_*` | 3 | **`list` de 13 elementos** | retorno de `espn_snapshot()`: `league`, `teams`, `rosters`, `matchups`, `draft`, ..., `raw` (JSON cru) |
| `espn_player_pool_*` | 3 | **`list` de 2 elementos** | `players` (pool) + `stats` (expandido), com list-columns `stats_raw` / `stats` / `applied_stats` |
| `Teste_*` | 1 | vetor `character` | artefato de teste (lixo) |

------------------------------------------------------------------------

## 6. Caveats / qualidade dos dados

- **`historic/` não tem PK nem FK** em nenhum `dm` --- o merge multi-temporada perdeu as chaves. Tratar como tabelas planas; não confiar em integridade referencial.
- **Type drift em `historic/`**: em `ffa_projtable` / `ffa_proj_source_points` / `ffa_scrape` a coluna `week` é `chr`; `nfl_players_adv_stats` tem **todas** as métricas como `chr` e colunas extras (`DEPRECIATED_DO_NOT_USE`, `opponent`, `schema_version`, `schema_note`); `nfl_teams_season_stats.teamId` e os `*PlayoffSeeding` como `chr`; `dudes_*` com `season` como `dbl` e `week` como `chr`. `ffa_projtable` em `historic/` tem 38 colunas (adiciona box-score projetado `pass_*`/`rush_*`/`rec_*` como `chr`).
- **Schema drift menor em `historic/2023/`**: `ffa_projtable` tem 23 colunas (tem `pos_ecr` / `sd_ecr` / `uncertainty`, não tem `first_name` / `team` / `age` / `exp`); `ffa_player_ids` tem 13 colunas (era antes de `gsis_id` / `sleeper_id`); `dudes_*` com `season` como `dbl`.
- **`nfl_stats_db` de `historic/2023/` é menor** que `historic/` para 2020--2022 (ex.: `nfl_players_points` 2020 tem 4 033 linhas em `historic/2023/` vs 15 058 em `historic/`) --- coleta parcial na época.
- **Gaps de semana**: `nfl_round_db` / `nfl_recap_db` de 2023 sem a semana 3; `nfl_recap` de 2024 sem a semana 5 (e para na semana 13); `nfl_recap` de 2023 sem a semana 11. `ffa_db` de 2021 (em `historic/`) só tem a semana 1.
- **`data/dudes_simulation_db.rds` está preso em 2024 w2--4** --- desatualizado em relação ao resto de `data/` (que vai até 2025/2026).
- **Tags com typo em `historic/nfl_round_db`**: `posaivers` (por `posWaivers`) e `preview` (misturado com `preTNF`/etc). Tags de evento presentes em 2023/historic e ausentes em `data/`: `preGermanGame`, `preLondonGame`, `preSNF`, `preSunday`, `preSundayGames`, `posDraft`.

------------------------------------------------------------------------

## Como foi levantado

``` r
library(dm); library(tidyverse)
db <- readRDS("data/ffa_db.rds")
names(db)                                    # tabelas
dm_get_all_pks(db); dm_get_all_fks(db)       # chaves
db$ffa_projtable |>
  distinct(season, week) |>
  summarise(weeks = paste(sort(week), collapse = ","), .by = season)
```
