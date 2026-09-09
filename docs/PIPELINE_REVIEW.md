# Revisão do processo — ingestão → simulação → recomendações

Data da revisão: 2026-09-08. Escopo: os três estágios do fluxo operacional
(ingestão FFA + ESPN, geração de simulações, recomendações) mais o código
adjacente que os alimenta. Avaliação de correção e de qualidade de escrita.

**Veredito geral.** O caminho vivo — `data_pipeline.R` (FFA + ESPN) →
`analytical_db.rds` → `run_decision_pipeline()` — está funcional e coerente com a
spec (`docs/decision_engine_spec.md`). A *decision engine* (`R/decision/*`) é a
parte mais bem escrita do repositório: funções puras que retornam tibbles, ordem de
fases explícita, 13 arquivos de teste, e limites deliberados marcados em comentário.
Os problemas estão concentrados (a) na duplicação de helpers entre os pipelines de
ingestão, (b) em código legado morto que ainda está no caminho de `source()` de
alguém, e (c) no builder do `analytical_db`, que hoje não roda.

Nenhum finding abaixo foi corrigido nesta rodada (escopo aprovado: relatório +
executar o ciclo). Estão ordenados por severidade.

**Execução de validação.** O ciclo completo foi rodado em 2026-09-08 sob o tag
`preKickoff` para `season 2026 / week 1`: ingestão FFA (6 fontes;
FantasySharks/NFL.com/RTSports/Walterfootball indisponíveis) + ESPN, depois
`run_decision_pipeline(2026, 1, "preKickoff")` em 21 s. Saiu limpo —
`dm_examine_constraints` sem violação no `espn_db` e no `decision_db`, quantis
monótonos em todas as 563 linhas de `player_forecasts`, win prob somando 1 em todos
os 7 matchups. Nenhum bug novo apareceu na execução além dos listados abaixo. Ver
`docs/PIPELINE_RUNBOOK.md` para os números.

---

## 1. Bloqueantes (impedem um estágio de rodar hoje)

### 1.1 `build_historic_datasets.R` — builder do `analytical_db` está quebrado
`R/analysis/build_historic_datasets.R:42-43,83` lê `./data/nfl_stats_db.rds` e
`./data/nfl_players_db.rds`. Nenhum dos dois existe em `data/` (só `analytical_db`,
`decision_db`, `espn_db`, `ffa_db`). Esses arquivos vêm do pipeline NFL legado
(`data_pipeline_nfl.R`), que está morto (ver 1.2). Consequência: o `analytical_db`
não pode ser reconstruído pelo caminho atual. O `data/analytical_db.rds` existente
(histórico ≤ 2025) continua válido para runs da temporada corrente porque só contém
a distribuição de erros históricos — mas assim que 2026 terminar e você quiser
incorporar os resultados reais de 2026 à calibração, não há como.

Outros problemas no mesmo arquivo:
- `:279` — `dm_draw_png(ffa_db, ...)` desenha o dm errado; deveria ser
  `analytical_dm`. O PNG em `export/analytical_db.png` é na verdade o ERD do
  `ffa_db`.
- `:32` — `filter(!(pos %in% c("FB", "Kenneth Walker III")))`: filtro de poluição
  hardcoded, com um nome de jogador no meio de uma lista de posições. Trata sintoma,
  não causa (a origem da linha "Kenneth Walker III" na coluna `pos` não foi
  investigada).
- É um script interativo (dezenas de `count() |> pivot_wider()` de inspeção
  intercalados), não um conjunto de funções. Roda de cima a baixo com `source()` e
  só o `saveRDS` final importa.

### 1.2 Pipeline NFL (`data_pipeline_nfl.R`) — morto e com bugs
`config/config.yml` não tem mais `authToken` nem `leagueId`; ambos são lidos como
`NULL` (`data_pipeline_nfl.R:160`), então toda chamada à API NFL retorna 401/403.
Mesmo que a credencial voltasse:
- `:159` `.week <- 0L` e depois `:180` `getFantasyStatistics(..., 1:.week)` →
  `1:0` = `c(1, 0)` em R, itera semanas 1 **e** 0.
- `getFantasyRound` (`R/api/nfl_league.R:101-119`) referencia nomes de tabela
  (`nfl_teams_week_stats`, `nfl_teams_round`, `nfl_teams_season_stats`) que não
  existem entre os argumentos da função — quebrada como está escrita.
- `R/api/nfl_api.R:17-19` — `cat(url)` / `cat(str(.query))` despejam debug em toda
  request.
- `saveTempResp` (`:31-36`) está definido mas nunca é chamado; este pipeline não
  tem cache de replay de rede (contradiz `CLAUDE.md`, que afirma que todas as
  respostas cruas são cacheadas em `data/temp/` — verdade só para FFA/ESPN).

### 1.3 Gen-1 sim (`simulation_machine.R`, `team_optimizer.R`) — morto e quebrado
Superado por `R/decision/player_simulation.R` (a "V2" da spec). Hoje não roda:
- `R/snippets/simulation_machine.R:12-13` — `readRDS` de `nfl_stats_db.rds` /
  `nfl_players_db.rds` (ausentes).
- `:412` — chama `updateDB()`, que não é definido nem carregado neste arquivo
  (depende de um `source()` anterior ter deixado a função no ambiente global).
- `R/analysis/team_optimizer.R:8` — `ffa <- readRDS()` **sem argumento**: erro
  imediato. Linhas 4-7 leem quatro `.rds` que não existem em `data/`.
- `R/analysis/projection_ml.R:5` — `readRDS("./data/nfl_stats_db.rds")` (ausente);
  usa `pull_workflow_fit()` (deprecado) no lugar de `extract_fit_parsnip()`.
- `data/dudes_simulation_db.rds` está preso em 2024 w2-4.

Recomendação: mover `simulation_machine.R`, `team_optimizer.R`, `projection_ml.R`,
`team_sim.R`, `player_simulation_analysis.R` para `R_old/` ou um `R/_legacy/`, e
apontar `README.md` para a decision engine.

---

## 2. Correção — bugs que não bloqueiam mas dão resultado errado

### 2.1 `R/transformation/simulation.R` — dois filtros que são no-op
- `:14` — `filter(season %in% season, week %in% weeks)`: o `filter()` do dplyr
  resolve `season` no contexto dos dados primeiro, então `season %in% season`
  compara a coluna com ela mesma → sempre `TRUE`. O filtro de temporada **não faz
  nada**. (`week %in% weeks` funciona porque o parâmetro se chama `weeks`, diferente
  da coluna.)
- `:18-20` — `if (tag != "") ... filter(tag == tag)`: `tag == tag` compara a coluna
  com ela mesma → sempre `TRUE`. O filtro de tag **não faz nada**; o parâmetro `tag`
  é ignorado.
- Efeito combinado: `calcProjectionErrors(2024, 1:4)` na verdade processa **todas as
  temporadas** do `ffa_db`, e o `filter(timestamp == max(timestamp), .by = c(season,
  week))` seguinte pode misturar tags. Só não causa dano hoje porque o único
  consumidor (`simulation_machine.R`) está morto.
- Correção: `filter(.data$season %in% .env$season)` e um parâmetro renomeado
  (`.season`), ou usar `.env$tag`.

### 2.2 `R/api/ffa_projection.R:48` — atributo `week` recebe valor de `season`
`attr(resp, "week") <- attr(.scrp, "season")` em `.projections_table_data_sources`.
Copy-paste: deveria ser `attr(.scrp, "week")`. O quanto isso propaga depende de
quem lê `attr(resp, "week")` a jusante (não rastreado nesta revisão).

### 2.3 `R/api/ffa_projection.R:34` — assume QB sempre presente
`unique(.webscrape$QB$data_src)` para enumerar as fontes. Um scrape sem QB (falha
de todos os sites de QB) quebra a enumeração de `data_src` em vez de degradar.

### 2.4 FK quebrada gravada em `ffa_db` a cada run
A execução de validação de 2026-09-08 salvou `ffa_db.rds` com
`ffa_players$id == 15540` sem entrada correspondente em `ffa_player_ids` — o
`ffanalytics` produziu uma projeção para um jogador que não está no crosswalk
interno do pacote (`ffanalytics:::player_ids`). O `updateDB` do FFA imprime o aviso
e salva mesmo assim (ver 2.5). Esse jogador fica invisível para todo o consumo a
jusante que faz join por id. É exatamente o "recurring pain point" de mapeamento de
id citado no `CLAUDE.md`, e não há mecanismo para corrigi-lo sem re-scrape.

### 2.5 `dm_examine_constraints` impresso, nunca validado
`data_pipeline_ffa.R:94`, `data_pipeline_espn.R:272` — o resultado é `print()`ado
mas não checado. Um dm com FK quebrada é salvo em disco na mesma. Deveria ser
`stopifnot(nrow(problems) == 0)` (ou pelo menos um `warning` condicional) antes do
`saveRDS`.

---

## 3. Qualidade de escrita / manutenção

### 3.1 Helpers triplicados
`updateDB`, `dm_draw_png` e o par `saveEspnTemp`/`saveTempResp` estão copiados em
`data_pipeline_ffa.R`, `data_pipeline_espn.R` e `data_pipeline_nfl.R`. Já há drift:
o `updateDB` do FFA usa `in_place = F`, os outros `in_place = FALSE` (mesma coisa,
mas mostra edição independente). **Recomendação:** extrair para
`R/pipeline/_pipeline_helpers.R` e `source()` uma vez em cada orquestrador. É a
mudança de maior retorno e menor risco do repositório.

### 3.2 Parâmetros hardcoded + documentação divergente
Nenhum pipeline lê `season`/`week` de `config/config.yml`. Cada um tem um bloco
`# MASTER PARAMETERS ####` com `.season <- 2026L` e um literal de semana, editado à
mão toda semana (`data_pipeline.R:14-16`, `data_pipeline_nfl.R:158-161`).
`CLAUDE.md` e `README.md` afirmam que `data_pipeline_espn.R` "lê `.season`/`.week`
de `config/config.yml`" — **falso**. O `config.yml` tem `season: 2026` e `week: 0`
que nenhum código consome. Ou passar a ler do config, ou corrigir a documentação
(e remover as chaves mortas do `config.yml`).

O bloco também é descrito em `CLAUDE.md` como estando "near the bottom" de
`data_pipeline.R` — na verdade está no topo (linhas 12-18).

### 3.3 Tags são string livre sem validação
Não há `match.arg`, `%in%` ou `stopifnot` em lugar nenhum sobre `.tag`. A tag entra
na PK das tabelas temporais de `ffa_db` e `espn_db` e no filtro de
`select_ffa_snapshot` / `select_espn_snapshot` (`snapshot.R:24,49`), que dão
`stop()` se `nrow == 0`. Consequência prática: um typo na tag (`"preveiw"`) roda a
ingestão inteira, cria uma partição órfã, e só falha depois no
`run_decision_pipeline`. O histórico do projeto (`preTNF`, `preLondonGame`,
`posWaivers`, e agora `preKickoff`) mostra que tags ad-hoc são intencionais — mas um
conjunto conhecido + aviso para valores fora dele evitaria a partição órfã.

### 3.4 ESPN — fetch duplo do pool de jogadores
`data_pipeline_espn.R:80-81` — `espn_all_players(client, limit = 5000)` e depois
`espn_player_stats(client, limit = 5000)`, sendo que a segunda função refaz
internamente a mesma chamada de 5000 registros ao pool. Uma chamada + reuso do
payload resolveria.

### 3.5 ESPN — `%||%` global com semântica divergente
`R/api/espn_fantasy_client.R:15-17` define um `%||%` global com semântica
null-**ou-vazio**, diferente do `%||%` de `rlang`/base (só null). O próprio
comentário em `data_pipeline_espn.R:16-17` reconhece o footgun. Renomear para
`%|||%` ou `.or_empty()`.

### 3.6 ESPN — `espn_players_points` mistura projetado e real
`data_pipeline_espn.R:167-183` — a mesma tabela guarda projeção
(`stat_source_id == 1`) e resultado real (`== 0`), e `week` é o
`scoring_period_id` de cada registro (varia por linha), não a semana do run. É
navegável via os `stat_source_id`/`stat_split_type_id` na PK, mas é uma tabela
difícil de consultar corretamente sem conhecer a convenção.

### 3.7 Upsert-only, nunca deleta
`updateDB` usa `dm_rows_upsert`: jogador ou time que some de uma fonte permanece
para sempre no `.rds`. Para `espn_players` isso é agravado pela união de "todo
`player_id` visto em qualquer lugar" (`data_pipeline_espn.R:126-145`). Não é bug,
mas o `.rds` só cresce e pode conter jogadores fantasma de temporadas antigas.

### 3.8 Código morto que grava arquivos que ninguém lê
- `R/transformation/missing_player_ids.R` — script top-level, `season == 2023,
  week == 0` hardcoded (`:18`), match ingênuo de `first_name` + `last_name` (sem
  Jr./Sr./D-ST), grava `data/missing_player_ids.rds`. O consumidor em
  `ffa_projection.R:99-107` está **comentado**. Output morto.
- `ffa_projection.R:112-114` — `add_ecr()`, `add_adp()`, `add_aav()`,
  `add_uncertainty()` comentados; `ffa_projtable` não tem colunas ECR/ADP/incerteza
  apesar de README/código antigo sugerirem que tem.

### 3.9 `ffa_player_ids` sobrescrito todo run
`ffa_projection.R:104` copia `ffanalytics:::player_ids` (dado interno do pacote)
verbatim para a tabela `ffa_player_ids` a cada execução. Qualquer correção manual
de mapeamento de id (o "recurring pain point" citado no `CLAUDE.md`) é perdida no
próximo run. O `analytical_db$player_ids` é a versão curada — mas ele também é
reconstruído pelo builder quebrado (1.1).

---

## 4. Decision engine (`R/decision/*`) — findings menores

O código está saudável. Os itens abaixo são limites conhecidos, quase todos já
marcados com comentário `ponytail:` no fonte.

- `trades.R:14-18,201` — quando o parceiro de trade é o adversário da minha semana,
  `my_after_win_probability` conta o jogador recebido em dobro (ele aparece dos dois
  lados do matchup simulado). Sinalizado por linha via `partner_is_my_opponent`;
  `my_delta_expected`, `trade_score` e o ranking não são afetados.
- `roster_evaluator.R:38-40` — `bench_value` é a soma não ponderada dos `sim_mean`
  do banco, sem desconto por probabilidade de uso.
- `decision_db.R:117` — o histórico de runs em `decision_db.rds` cresce sem poda
  (`dm_rows_upsert` acumulando `run_id`).
- `decision_pipeline.R:67` — `stopifnot(!anyDuplicated(sims$ffa_id))` derruba o
  pipeline inteiro se um `ffa_id` aparecer em duas posições no snapshot FFA. É uma
  suposição razoável hoje, mas o modo de falha é abrupto.
- `snapshot.R:118-122` — `pos` inesperado gera `warning` e o run continua; o
  jogador cai no fallback de nível 4 do pool de resíduos (`player_simulation.R`),
  sem sinalização adicional a jusante.
- `league_state.R` — o bridge ESPN→FFA tem quatro estratégias em cascata (arquivo
  de override → `espn_id` direto → offset de D/ST → nome+posição normalizado). É a
  parte mais frágil da engine (mapeamento de id "quebra toda temporada", conforme
  `CLAUDE.md`), mas está bem estruturada e testada (`test_espn_bridge.R`).
- `trades.R:183-206` — o schema real de `trade_recommendations`
  (`my_delta_expected`, `their_delta_expected`, `my_before_expected`, …) diverge do
  nomeado na spec §28 (`my_value_before`, `my_value_after`, `my_delta`). Os testes e
  o `DATA_CATALOG.md` seguem o código; a spec é que está desatualizada. Alinhar a
  spec.
- `current_consensus.R:24-25,32` — `source_sd`/`source_mad` usam guard
  `if (n_distinct(data_src) >= 2)` e `source_range` usa `if_else(n_sources >= 2)`.
  São equivalentes (`n_sources == n_distinct(data_src)`), só inconsistência
  estilística.

---

## 5. Recomendações priorizadas

| # | Ação | Esforço | Retorno |
|---|------|---------|---------|
| 1 | Extrair `updateDB` / `dm_draw_png` / `save*Temp` para `R/pipeline/_pipeline_helpers.R` | baixo | alto |
| 2 | `stopifnot` no `dm_examine_constraints` antes do `saveRDS` nos 3 pipelines | baixo | alto |
| 3 | Corrigir os filtros no-op em `simulation.R` (`.env$` / renomear parâmetro) **ou** arquivar o arquivo junto com o gen-1 | baixo | médio |
| 4 | Mover gen-1 sim (`simulation_machine.R`, `team_optimizer.R`, `projection_ml.R`, snippets quebrados) para `R/_legacy/` | baixo | médio |
| 5 | Alinhar `CLAUDE.md`/`README.md` com a realidade dos parâmetros hardcoded; remover `season`/`week` mortos do `config.yml` **ou** passar a lê-los | baixo | médio |
| 6 | Conjunto de tags conhecido + `warning` para valores fora dele | baixo | médio |
| 7 | Consertar `build_historic_datasets.R` — requer decidir a fonte de resultados reais (reviver pipeline NFL, ou trocar por `espn_players_points` com `stat_source_id == 0`) | alto | alto (necessário para calibração pós-2025) |
| 8 | ESPN: eliminar o fetch duplo do pool | médio | baixo |
| 9 | `ffa_player_ids`: não sobrescrever correções manuais (merge em vez de replace) | médio | médio |

O item 7 é o único de esforço alto e é o gargalo estratégico: sem ele a
distribuição de resíduos que a decision engine usa nunca aprende com temporadas
novas. A alternativa mais barata é trocar a fonte de "actual points" de
`nfl_stats_db` para `espn_players_points` filtrado por `stat_source_id == 0`, o que
elimina a dependência do pipeline NFL morto de uma vez.
