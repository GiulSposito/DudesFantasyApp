---
editor_options:
  markdown:
    wrap: 72
---

# Visão geral --- do scrape à recomendação

Documento conceitual único, amarrando extração → agregação → projeção →
recomendação → formatos → técnicas → outcomes esperados. Para comandos
exatos de como rodar, ver `docs/PIPELINE_RUNBOOK.md`. Para a spec de
implementação linha a linha do motor de decisão, ver
`docs/decision_engine_spec.md`. Para o dicionário de tabelas/colunas, ver
`DATA_CATALOG.md`.

------------------------------------------------------------------------

## 1. O fluxo, em uma linha

```text
R/api/          R/pipeline/         data/*.rds        R/decision/           data/decision_db.rds   R/web/               site Quarto
scrape + API  →  ingestão (dm,    →  dm relacionais  →  motor de decisão   →  previsões +         →  bundle Parquet    →  estático
                 upsert)                                (Monte Carlo)         recomendações           + manifest.json      (só leitura)
```

Duas fontes de dados independentes alimentam a ingestão: **FFA**
(`ffanalytics`, agregador de projeções de ~10 sites) e **ESPN** (API
oficial da liga). Cada uma vira um objeto `dm` próprio
(`data/ffa_db.rds`, `data/espn_db.rds`). O motor de decisão
(`R/decision/`) lê os dois, mais o histórico em `data/analytical_db.rds`,
e produz `data/decision_db.rds`. A camada web só lê esse resultado final
e publica --- não roda nenhuma análise.

**Importante --- o que está morto hoje:** o pipeline NFL Fantasy legado
(`R/pipeline/data_pipeline_nfl.R`, `R/api/nfl_*.R`, sem `authToken` no
config) e a primeira geração de simulação/otimização
(`R/snippets/simulation_machine.R`, `R/analysis/team_optimizer.R`,
`R/analysis/projection_ml.R`, `R/transformation/*`) foram superados pela
decision engine e não fazem parte do ciclo atual --- alguns nem rodam
mais como estão (`team_optimizer.R` tem uma leitura de RDS incompleta).
Detalhe da divisão: `docs/PIPELINE_RUNBOOK.md:205-209`.

------------------------------------------------------------------------

## 2. Extração e ingestão

Orquestrado por `R/pipeline/data_pipeline.R`, bloco de parâmetros
`.season` / `.week` / `.tag` (linhas 20-27).

- **FFA** (`importFfa()`, `R/pipeline/data_pipeline_ffa.R`,
  `R/api/ffa_projection.R`): scrape multi-site via `ffanalytics` (CBS,
  ESPN, FantasyPros, FFToday, FleaFlicker, FanDuel, NFL, RTSports,
  Walterfootball, ...). Falha de site é silenciosa e parcial --- se uma
  fonte cair, o scrape segue sem ela. O consenso entre fontes é
  calculado com as regras de pontuação de `config/score_settings.yml`.
  Upsert em `data/ffa_db.rds` (5 tabelas).
- **ESPN** (`importEspn()`, `R/pipeline/data_pipeline_espn.R`,
  `R/api/espn_fantasy_client.R`): um snapshot combinado da liga
  (`espn_snapshot()` --- settings, status, times, rosters, standings,
  matchups, draft, tudo numa requisição) mais o pool completo de
  jogadores (`espn_all_players()` + `espn_player_stats()`). Autenticado
  via cookies de sessão (`ESPN_S2`, `ESPN_SWID`) em
  `config/config.yml`. Upsert em `data/espn_db.rds` (12 tabelas).
- Cache bruto de cada resposta em `data/temp/*.rds` --- permite
  reprocessar sem bater na rede de novo.
- `.tag` marca *quando* na semana o snapshot foi capturado (`preview`,
  `preKickoff`, `preTNF`/`posTNF`, `preMNF`, `final`, `season`) e é
  parte da chave primária das tabelas temporais --- múltiplos snapshots
  da mesma `season/week/tag` coexistem (timestamps diferentes); o
  consumo sempre pega `max(timestamp)`. Tags não são validadas em
  lugar nenhum: um typo cria uma partição órfã silenciosa. Vocabulário
  completo: `docs/PIPELINE_RUNBOOK.md:135-148`.

------------------------------------------------------------------------

## 3. Modelo de dados e agregação

Cada `data/*_db.rds` **não é um data frame solto** --- é um objeto `dm`
(pacote `{dm}`): um conjunto de tabelas relacionadas com chaves
primárias e estrangeiras declaradas, examinável com
`dm::dm_examine_constraints()`. O merge incremental é sempre
upsert (`dm_rows_upsert`), nunca overwrite --- uma nova ingestão
acrescenta/atualiza linhas sem apagar histórico. O pipeline ESPN
reconcilia schema-drift entre colunas antes do upsert
(`.reconcile_dm_cols`, `R/pipeline/data_pipeline_espn.R:25-36`).

Duas camadas adicionais, fora do ciclo semanal:

- **`data/analytical_db.rds`** (`consensus_error_history`, ~28.800
  linhas projeção × realizado, temporadas ≤ 2025) --- a base que
  alimenta o Monte Carlo do motor de decisão. Construída uma vez, não
  reconstruída toda semana; só precisa ser refeita para incorporar uma
  temporada encerrada nova à calibração.
- **Bridging de identidade de jogador** (`ffa_id` / `espn_id` /
  `nfl_id`) --- cada fonte usa seu próprio esquema de ids; a ponte é
  frágil e é um ponto de atrito recorrente entre temporadas (warnings
  esperados tipo "N consensus players without nfl_id mapping" em toda
  execução).

Dicionário completo de tabelas/colunas: `DATA_CATALOG.md`.

------------------------------------------------------------------------

## 4. Geração de projeções --- o motor Monte Carlo

Núcleo do motor de decisão (`R/decision/decision_pipeline.R`,
`R/decision/player_simulation.R`), especificado em
`docs/decision_engine_spec.md` §7-11.

**STEP 1 --- consenso atual.** Para cada jogador, agrega as projeções
das fontes ativas naquele snapshot em uma linha: `projection`,
`n_sources`, `coverage_class` (`ensemble` = várias fontes concordando,
`sparse` = poucas fontes, `single` = uma fonte só).

**STEP 2 --- `simulate_player()`.** Transforma essa projeção pontual
numa distribuição, usando a identidade:

```text
actual_points = projection + residual
```

onde `residual` é reamostrado do histórico real
(`analytical_db$consensus_error_history`), **não** de uma distribuição
Normal assumida e **não** a partir de `source_sd` (que mede
desacordo entre fontes na mesma semana, não erro real da projeção
contra o resultado).

O *pool* de resíduos históricos usado para cada jogador é selecionado
por vizinhança (KNN): mesma `position` + `coverage_class`, ordenado por
`|projection atual − projection histórica|`, pegando os `k=300` mais
próximos. Se o pool ficar pequeno demais (`min_pool_size=100`), cai por
uma hierarquia de fallback de 4 níveis até garantir tamanho suficiente:

```text
1. posição + coverage_class + vizinhança de projeção
2. posição + vizinhança de projeção
3. posição
4. todos os resíduos históricos
```

A simulação em si é um bootstrap simples: `sample(pool, n_sim=10000,
replace=TRUE)` somado à projeção atual, com `set.seed()` fixado uma vez
por execução (não por jogador).

**Output persistido** (`player_forecasts`): `sim_mean`, `sim_sd`,
quantis `p05`--`p95`, e probabilidades de limiar (`prob_gt_10`,
`prob_gt_15`, `prob_gt_20`).

**Realized-points folding** (§11.3, `apply_realized_points()`): quando
o jogo de um jogador já travou (`lineup_locked` da ESPN), a distribuição
inteira é substituída por um valor fixo (os pontos reais) --- uma
distribuição degenerada. Esse único mecanismo, aplicado uma vez no
início do pipeline, é suficiente para que lineup, free agents e trades
tratem "jogo já decidido" corretamente sem lógica especial em cada um.

------------------------------------------------------------------------

## 5. Simulação de matchup

`R/decision/matchup_simulation.R`, spec §14-15. Para cada confronto da
semana, compara os dois times **draw a draw** (mesma seed dos dois
lados, 10 mil sorteios pareados) e calcula `expected`, quantis, e
`win_probability` de cada lado --- as probabilidades dos dois lados de
um mesmo confronto somam 1.

------------------------------------------------------------------------

## 6. Recomendações

Três recomendadores, todos consumindo `player_forecasts` +
`matchup_simulations`, todos cientes de jogadores travados via a mesma
lista `locked_ffa`.

### Lineup (`R/decision/lineup_optimizer.R`, `roster_evaluator.R`, spec §16-19)

Otimização **exata** por busca recursiva com poda (branch-and-bound) ---
não é greedy nem programação linear. Decisão deliberada: o problema é
pequeno o bastante (poucas dezenas de jogadores, poucos slots) para não
justificar instalar um solver LP. Função objetivo atual:

```text
maximize  sum(sim_mean[jogador])
sujeito às vagas de espn_roster_slots
```

As vagas do lineup (QB/RB/WR/TE/FLEX/...) e a elegibilidade de cada
jogador para cada slot vêm sempre de `espn_roster_slots` --- nunca
hard-coded, então o código se adapta a qualquer formato de liga.
Titulares com jogo já travado são "pinados" no próprio slot atual via
matching bipartido máximo (algoritmo de Kuhn) antes de otimizar o
resto do roster; reservas travados saem do pool de candidatos (não há
decisão a tomar sobre um jogador cujo jogo acabou). Uma segunda função
objetivo (maximizar `P(win)` direto, gerando e comparando lineups
candidatos contra o adversário) está prevista na spec como evolução,
não é o caminho principal hoje.

`recommend_lineup()` persiste só a diferença entre o lineup atual e o
otimizado: `player_out` / `player_in`, `delta_expected`,
`delta_win_probability`, `recommendation_rank`.

### Free agents (`R/decision/free_agents.R`, spec §19-23)

Ranking de candidatos ADD/DROP por `delta_expected` /
`delta_win_probability` contra o time do usuário. Banco travado é
excluído inteiramente do pool (dropar um jogador cujo jogo já acabou
não é uma decisão real).

### Trades (`R/decision/trades.R`, spec §24-29)

Varre trocas 1×1 candidatas entre times, filtra e ranqueia por
`trade_score` / `fairness` (= `-abs(meu delta − delta do outro)`),
priorizando trocas onde os dois lados ganham. `recommendation_rank`
reinicia em 1 para cada `my_team_id`. Jogadores travados (titulares ou
banco) saem do universo de troca do mesmo jeito que em FA.

### Persistência

Tudo cai em **um único** `data/decision_db.rds` --- 7 tabelas, cada
execução de `run_decision_pipeline()` marcada com um `run_id` próprio,
acumulando histórico (nada é sobrescrito).

------------------------------------------------------------------------

## 7. Formatos de dados

| Camada | Formato | Onde |
|---|---|---|
| Ingestão bruta | cache `.rds` por resposta | `data/temp/*.rds` |
| Dados relacionais | objeto `dm` (PK/FK) em `.rds` | `data/ffa_db.rds`, `data/espn_db.rds`, `data/analytical_db.rds`, `data/decision_db.rds` |
| Publicação web | Parquet + `manifest.json` | `web/data/` (gerado por `R/web/build_web_bundle.R`, contrato em `docs/app_web_data_contract.md`) |
| Apresentação | site Quarto estático, só leitura | `web/*.qmd` |

A camada web nunca lê `.rds` nem roda análise --- só serializa o
resultado já pronto de `decision_db` em Parquet, com uma opção
`privacy = "public"` que remove nomes/ids de dono antes de publicar em
host público (GitHub Pages).

------------------------------------------------------------------------

## 8. Técnicas empregadas

| Técnica | Onde | Por quê |
|---|---|---|
| Web scraping multi-fonte | `ffanalytics` (FFA) | agregar consenso de ~10 sites de projeção |
| Cliente REST autenticado | `httr2` (ESPN) | ler roster/standings/matchups direto da API oficial da liga |
| Modelagem relacional com PK/FK | pacote `{dm}` em toda ingestão | manter integridade referencial entre tabelas versionadas por tag/timestamp |
| Upsert incremental | `dm_rows_upsert()` | acumular histórico sem reprocessar tudo a cada ciclo |
| Bootstrap não-paramétrico de resíduos históricos, com fallback hierárquico por KNN | `simulate_player()` | gerar distribuição real de outcomes sem assumir Normalidade |
| *Folding* de distribuição degenerada | `apply_realized_points()` | tratar "jogo já decidido" com o mesmo pipeline, sem casos especiais |
| Simulação Monte Carlo pareada (draw a draw) | `simulate_matchup()` | win probability consistente entre os dois lados de um confronto |
| Otimização combinatória exata (branch-and-bound) | `optimize_lineup()` | ótimo garantido num espaço de busca pequeno, sem depender de solver externo |
| Matching bipartido máximo (Kuhn) | pin de titulares travados | travar apenas quem precisa, sem distorcer o resto da otimização |
| Ranking por delta | free agents / trades | comparar candidatos numa métrica comum (pontos esperados, win probability) |

------------------------------------------------------------------------

## 9. Outcomes esperados

Critérios de aceite por milestone (`docs/decision_engine_spec.md:1607-1701`):

- **M1** --- previsão por jogador: quantis sempre monótonos
  (`p05 ≤ p10 ≤ ... ≤ p95`).
- **M2** --- previsão por confronto: `win_probability` dos dois lados de
  um mesmo matchup sempre soma 1.
- **M3** --- lineup: pontos esperados e `P(win)` atual vs. ótimo por
  time, com substituições recomendadas.
- **M4** --- free agents: top ADD/DROP por delta de pontos esperados e
  de `P(win)`.
- **M5** --- trades: top trocas 1×1 mutuamente úteis por time,
  `recommendation_rank` reiniciando por time.

Gate de calibração manual (`R/decision/validate_model.R`, fora do ciclo
semanal): cobertura empírica de intervalo `P10--P90 ≈ 0.80`,
`P25--P75 ≈ 0.50`, `|bias| < 0.5` --- confirma que a incerteza reportada
bate com o erro real observado.

Exemplo de execução real registrado em
`docs/PIPELINE_RUNBOOK.md:195-201` (2026 semana 1, tag `preKickoff`):
563 linhas em `player_forecasts` (341 ensemble / 116 sparse / 106
single), quantis monótonos em 100% das linhas,
`cor(projection, sim_mean) = 0.986`, 7 matchups simulados com
probabilidades somando 1, 14 avaliações de lineup (7 times já no ótimo),
10 recomendações de troca de escalação, 10 de free agent, 6 de trade
1×1 --- `dm_examine_constraints(decision_db)` sem violações.

------------------------------------------------------------------------

## 10. O que é legado

Ver a lista completa e o porquê em `docs/PIPELINE_RUNBOOK.md:205-209`.
Resumo: pipeline NFL Fantasy (`R/pipeline/data_pipeline_nfl.R`,
`R/api/nfl_*.R`) e a primeira geração de simulação/otimização
(`R/snippets/simulation_machine.R`, `R/analysis/team_optimizer.R`,
`R/analysis/projection_ml.R`, `R/transformation/*`) --- superados pela
decision engine descrita acima, não fazem parte do ciclo atual.
