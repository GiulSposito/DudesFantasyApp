---

editor_options: 
  markdown: 
    wrap: 72
---

# Runbook --- ciclo semanal (ingestão → simulação → recomendações)

Manual operacional curto. Para o detalhe de cada estágio, ver `README.md`; para o desenho da decision engine, `docs/decision_engine_spec.md`; para a avaliação de correção do código, `docs/PIPELINE_REVIEW.md`.

------------------------------------------------------------------------

## Pré-requisitos

1.  **Working directory = raiz do projeto.** Todo caminho no código é relativo (`./data/...`, `./R/...`, `./config/...`). Abra `DudesApp.Rproj` no RStudio ou `setwd("/Users/gsposito/Projects/football/DudesApp")` antes de qualquer coisa. Nenhum script verifica isso --- rodar da pasta errada dá erro de arquivo não encontrado.
2.  **`config/config.yml`** com cookies ESPN válidos (`ESPN_S2`, `ESPN_SWID`, `ESPN_LEAGUEID`, `myTeamEspnId`). Os cookies expiram; se `espn_test_connection` abortar a ingestão, renove-os no navegador logado no ESPN Fantasy.
3.  **Pacotes R:** `tidyverse`, `dm`, `glue`, `lubridate`, `ffanalytics`, `httr2`, `jsonlite`, `yaml`. Instalados ad hoc com `install.packages()` (`ffanalytics` vem do GitHub --- ver `README.md`). Para o web bundle (passo 7): `nanoparquet`, e o CLI `quarto` para renderizar/publicar o site.

------------------------------------------------------------------------

## Sequência semanal

### 1. Parametrizar

Editar o bloco `# MASTER PARAMETERS ####` no topo de `R/pipeline/data_pipeline.R` (linhas 20-27):

``` r
.season <- 2026L
.week   <- 1L            # semana corrente da NFL
.tag    <- "preKickoff"  # ver "Vocabulário de tag" abaixo
```

### 2. Rodar a jornada semanal

``` r
source("R/pipeline/data_pipeline.R")
```

`data_pipeline.R` orquestra a jornada inteira com um único bloco de parâmetros:
**ingestão → decision engine → web bundle → publish**. Roda, em sequência:

- `importFfa()` --- scrape do `ffanalytics` (~10 sites: CBS, ESPN, FantasyPros, FFToday, FleaFlicker, FanDuel, NFL, RTSports, Walterfootball, ...), calcula as projeções de consenso com `config/score_settings.yml`, e faz upsert em `data/ffa_db.rds` (5 tabelas). Leva alguns minutos. **Falha de site é silenciosa e parcial** --- se uma fonte cair, o scrape continua sem ela; confira a contagem de `data_src` no fim.
  `config/score_settings.yml` precisa ter `kick$fg_0039: 3.0` (FG de 0–39 jardas): FFToday / FleaFlicker publicam só o total de FG e a ESPN só 0–39 / 40–49 / 50+; `.impute_k_fg()` (`R/api/ffa_projection.R`) joga esses FG em `fg_0039`. Sem a regra, o K projeta ~45% abaixo do real.
- `importEspn()` --- um snapshot combinado da liga + o pool de jogadores via API ESPN, upsert em `data/espn_db.rds` (15 tabelas, incl. times NFL + calendário de jogos via `proTeamSchedules_wl` + rank de defesa vs posição, `espn_pos_vs_opponent`). Guarda também as projeções semanais ESPN das 3 semanas seguintes, limitadas ao fim da temporada (`docs/horizon_projections.md`). **Para com erro se `.week` não for o scoring period atual da ESPN** (`status$latestScoringPeriod`): com a semana errada a ESPN devolve, sem avisar, o lineup histórico daquela semana. A exceção é a tag `"final"`, que fecha uma semana já passada.
- `run_decision_pipeline(.season, .week, .tag)` --- passo 4 abaixo; devolve `res`.
- `build_web_bundle(result = res, privacy = "public")` --- passo 7 abaixo.
- `quarto publish gh-pages web` --- render + push para `origin/gh-pages`. Pule com `.publish <- FALSE` no bloco de parâmetros.

Cache cru de cada resposta em `data/temp/*.rds` (permite reprocessar sem rede). ERDs em `export/ffa_db.png` e `data/temp/espn_db.png`.

**A ingestão grava sob a mesma `.tag`.** Se a semana já foi ingerida sob essa tag, o upsert atualiza as linhas daquele `timestamp` e adiciona um novo --- múltiplos snapshots da mesma `season/week/tag` coexistem; o consumo sempre pega `max(timestamp)`.

Para rodar um estágio isolado (re-simular sem re-scrape, republicar sem re-simular, etc.), chame a função do estágio direto --- ver passos 4 e 7.

### 3. `analytical_db` --- **não mexer no ciclo normal**

`data/analytical_db.rds` (histórico de projeções e resíduos ≤ 2025) é entrada da decision engine mas **não** é reconstruído toda semana. Só precisa ser refeito quando você quiser incorporar resultados reais de uma temporada encerrada à calibração. O builder (`R/analysis/build_historic_datasets.R`) é um script interativo que lê `historic/2020-2025/` e `historic/2021/`. Os pontos reais vêm só desses arquivos NFL legados, então **incorporar 2026 exige antes uma fonte nova de pontos reais** --- ver `docs/PIPELINE_REVIEW.md` §1.1.

### 4. Simulação + recomendações (a decision engine)

Já roda dentro do passo 2. Para rodar isolada (re-simular sobre snapshots já ingeridos):

``` r
source("R/decision/decision_pipeline.R")
res <- run_decision_pipeline(2026, 1, "preKickoff")   # season, week, tag
```

Defaults: `n_sim = 10000`, `seed = 1234`, `use_realized = TRUE`, e `matchups` / `lineups` / `free_agents` / `trades` todos `TRUE`. Free agents e trades usam `config$myTeamEspnId` (= 4) como time alvo.

**`use_realized = TRUE`** (spec §11.3): jogadores cujo jogo da NFL já travou (`lineup_locked` da ESPN) entram no Monte Carlo com os pontos reais como valor fixo, e ficam fora de troca de lineup / trade / add-drop. Sem nada travado (snapshot pré-jogos) o resultado é idêntico a `FALSE`. Requer um snapshot ESPN ingerido com o código que persiste `lineup_locked` (ingestões antigas não têm a coluna --- tratadas como nada travado).

O que roda, em ordem (as fases da spec):

| Fase | Produz |
|-------------------------------|-----------------------------------------|
| 1 seleção de snapshot | `ffa_snap`, `espn_snap` (`season/week/tag`, `max(timestamp)`) |
| 2 consenso atual | uma linha por jogador: `projection`, `n_sources`, `coverage_class` |
| 3 Monte Carlo do jogador | `projection + amostra(resíduos históricos centrados)`, 10k draws → `player_forecasts` (média, sd, quantis p05--p95, prob \> N) |
| 4 estado da liga | `current_players` --- roster ESPN + forecast + injury, com bridge ESPN→FFA |
| 5 simulação de matchup | `matchup_simulations` --- expected e win prob por confronto da semana |
| 6-7 lineup ótimo + avaliação de roster | `lineup_evaluations` (atual vs ótimo), `lineup_recommendations` (só as trocas) |
| 8 free agents | `free_agent_recommendations` --- top ADD/DROP por Δ expected, em 3 escopos (W0, W1..W3, W0..W3); Δ P(win) só reportado |
| 9 trades 1×1 | `trade_recommendations` --- top trocas mutuamente úteis, por time e escopo (`recommendation_rank`, `rank_future` e `rank_horizon` recomeçam em 1 por `my_team_id`) |
| 10 persistência | `data/decision_db.rds` (dm 9 tabelas, um `run_id` por execução, acumula) |

`run_decision_pipeline()` devolve (invisível) uma lista de 13 elementos --- ver "Onde olhar" abaixo.

Para pular estágios: `run_decision_pipeline(2026, 1, "preKickoff", trades = FALSE)` etc.

### 5. (Opcional) Gate de calibração

``` r
source("R/decision/validate_model.R")
validate_player_model(readRDS("data/analytical_db.rds")$consensus_error_history,
                      sample_frac = 0.25)
```

Backtest da distribuição do modelo de jogador. Alvos: cobertura P10--P90 ≈ 0.80, P25--P75 ≈ 0.50, `abs(bias) < 0.5`. É um gate manual --- **não** faz parte do pipeline.

### 6. (Opcional) Testes

``` r
source("tests/run_all.R")
```

31 arquivos `stopifnot` (15 em `tests/decision/`, 16 em `tests/web/`). `run_all.R` para na primeira falha. Verificado em 2026-11-06: 30/31 `PASS`.

**Falha conhecida:** `test_pipeline_integration.R` roda contra os `.rds` reais com contagens hardcoded para `2026 / w1 / "preview"` (99/149/313 por `coverage_class`). O snapshot ESPN dessa tag foi recapturado em 2026-10-20, já com pontos reais, e hoje a run dá 137/164/258, mais 2 linhas de previsão zero sem `coverage_class`. Esse é o 9º arquivo de `tests/decision/`, então a falha interrompe `run_all.R` antes dos 6 testes de decisão seguintes e de todos os testes web. Enquanto o teste não for corrigido, rode esses arquivos um a um com `source()`.

Lógica JS do site (ambos `PASS` em 2026-11-06):

``` bash
node tests/web/compare.check.mjs
node tests/web/trade-sim.check.mjs
```

### 7. Web bundle + publicação do cockpit

Já roda dentro do passo 2 (`build_web_bundle(result = res, privacy = "public")` + `quarto publish gh-pages web`). Esta seção é para republicar isolado.

A camada web (`web/`) é um site Quarto estático: as páginas são JavaScript e consultam o Parquet no navegador com DuckDB-Wasm. O bundle **não** re-simula --- lê os `dm` de `data/*.rds` e escreve Parquet + `manifest.json` em `web/data/`. Rodar depois do passo 4.

``` bash
# da raiz do projeto, com data/*.rds atualizados
Rscript -e 'source("R/web/build_web_bundle.R"); build_web_bundle(privacy = "public")'
```

- `build_web_bundle()` resolve o run mais recente da última semana em `data/decision_db.rds` (ou passe `run_id = "..."`), apaga e recria `web/data/`, escreve 25 datasets `.parquet` (`runs.parquet` + subpastas `dimensions/`, `current/`, `projections/`, `history/`, `draft/`; os marts por run empilham o run mais novo de cada semana, para o seletor de semana do site) + `web/data/manifest.json`, e roda `validate_web_bundle()` como gate --- `stop()` em qualquer violação do contrato (`docs/app_web_data_contract.md`).
- `privacy = "public"` remove `owner_name` / ids de owner. Use para qualquer host world-readable (GitHub Pages inclusive). `privacy = "private"` (default) só para deploy que não é público.
- Lê `data/decision_db.rds`, `data/espn_db.rds`, `data/ffa_db.rds`, `data/analytical_db.rds`. `web/data/` é gitignored; nenhum `.rds` nem cookie sai da máquina.

Preview local e publicação:

``` bash
quarto preview web                              # preview local (usa web/data/)
quarto render web                               # -> web/_site/
quarto publish gh-pages web                     # renderiza e empurra web/_site/ p/ branch gh-pages de origin (DudesFantasyApp)
```

Detalhe de deploy (Cloudflare Pages, Netlify, S3, offline vendoring): `web/DEPLOY.md`. Layout dos builders: `R/web/README.md`.

------------------------------------------------------------------------

## Vocabulário de tag

A `.tag` marca *quando* na semana os dados foram capturados. É parte da chave primária das tabelas temporais, então versões com tags diferentes coexistem no mesmo banco.

| tag | significado |
|---------------------|---------------------------------------------------|
| `preview` | projeções do começo da semana |
| `preWaivers` / `posWaivers` | antes / depois do processamento de waivers --- `preWaivers` é o mesmo marco de `preview` e é o usado no ciclo atual |
| `preKickoff` | snapshot logo antes do primeiro jogo (ad-hoc; usado a partir de 2026) |
| `preLondonGame` | antes de jogo internacional, quando ele é o primeiro da semana |
| `preTNF` / `posTNF` | antes / depois do jogo de quinta (Thursday Night Football) --- com `posTNF` alguns jogadores já entram com pontos reais (spec §11.3) |
| `preSunday` / `preSundayGames` | antes dos jogos de domingo |
| `preSNF` | antes do jogo de domingo à noite |
| `preMNF` | antes do jogo de segunda |
| `final` | depois de todos os jogos. Única tag aceita com `.week` diferente da semana corrente da ESPN, e o snapshot ESPN `final` marca a semana como fechada para os marts de histórico do site (`best_lineups`, `matchup_backtest`) |
| `season` | snapshot de nível temporada, gravado em `week = 0` |

**Tags não são validadas em lugar nenhum.** Um typo (`"preveiw"`) roda a ingestão inteira e cria uma partição órfã; a falha só aparece depois, quando `run_decision_pipeline` não acha o snapshot. Já aconteceu: `decision_db` tem um run com `preWaiver`, sem o "s". **Use exatamente o mesmo string na ingestão (passo 2) e no `run_decision_pipeline` (passo 4).**

------------------------------------------------------------------------

## Onde olhar os resultados

### O objeto `res` (na sessão R)

``` r
res$run_id                       # "2026-W01-preKickoff-<timestamp>"
res$player_forecasts             # projeção + distribuição por jogador
res$current_players              # roster de todo mundo + forecast + injury
res$matchup_simulations          # os confrontos da semana, com win prob
res$lineup_evaluations           # lineup atual vs ótimo, por time
res$lineup_recommendations       # só as trocas sugeridas (player_out → player_in)
res$free_agents                  # pool de free agents com forecast
res$free_agent_recommendations   # top ADD/DROP para o meu time
res$trade_recommendations        # top trades 1×1 de todos os times (filtre por my_team_id == 4)
res$consensus                    # consenso FFA da semana (entrada da fase 3)
res$simulation_runs              # 1 linha: metadados deste run
```

Inspeção típica: `dplyr::glimpse(res$player_forecasts)`, `res$matchup_simulations |> print(n = Inf)`, `res$lineup_recommendations |> filter(team_id == 4)`.

### O banco persistido

``` r
d <- readRDS("data/decision_db.rds")
names(d)                          # as 9 tabelas
d$simulation_runs                 # uma linha por run já executado (acumula)
dm::dm_examine_constraints(d)     # deve vir sem violações
```

Para comparar runs (ex. `preview` vs `preKickoff` da mesma semana), filtre cada tabela por `run_id`.

### As ações da semana (o que fazer com o time)

1.  `res$lineup_recommendations |> filter(team_id == 4)` --- trocas de escalação. Se vier vazio, o lineup atual já é o ótimo.
2.  `res$free_agent_recommendations` --- ordenado por `recommendation_rank`; olhe `delta_expected` e `delta_win_probability`. Para semanas futuras, use `rank_future` / `rank_horizon`.
3.  `res$trade_recommendations |> filter(my_team_id == 4)` --- trocas 1×1 com `my_delta_expected > 0` (a tabela cobre todos os times); priorize as com `their_delta_expected > 0` também (plausíveis para o outro manager). Colunas: `give_player_id` / `receive_player_id` (ids ESPN), `my_delta_expected`, `their_delta_expected`, `fairness` (= `-abs(my_delta − their_delta)`), `trade_score`, `partner_is_my_opponent`. Escopos futuros: `my_delta_future`, `my_delta_horizon`, `rank_future`, `rank_horizon`.

### Diagramas

`export/ffa_db.png`, `export/espn_db.png`, `export/analytical_db.png`, `data/temp/espn_db.png` --- ERDs dos `dm`. (O `analytical_db.png` hoje mostra o ERD errado --- ver REVIEW §1.1.)

------------------------------------------------------------------------

## Exemplo de saída (2026 w1 `preKickoff`, executado em 2026-09-08)

**Ingestão.** FFA: 2 061 linhas em `ffa_proj_source_points`, 6 fontes ativas (CBS, ESPN, FanDuel, FantasyPros, FFToday, FleaFlicker --- FantasySharks, NFL.com, RTSports e Walterfootball caíram/sem dados semanais), 1 682 linhas de consenso. Uma violação de FK conhecida (`ffa_players$id` 15540 sem entrada em `ffa_player_ids`). ESPN: 14 times, 630 vagas de roster, 378 titulares, 3 108 registros de status de lesão (543 não-ACTIVE), 294 linhas de matchup (calendário da temporada inteira; o snapshot filtra a semana). `dm_examine_constraints(espn_db)` sem violações.

**Decisão** (`run_decision_pipeline(2026, 1, "preKickoff")`, ~21 s): `run_id = 2026-W01-preKickoff-20260908T235138`; 563 linhas em `player_forecasts` (341 ensemble, 116 sparse, 106 single); quantis monótonos em todas as linhas; `cor(projection, sim_mean) = 0.986`; 7 matchups simulados (win prob soma 1 em todas); 14 avaliações de lineup (7 times já no ótimo, `n_substitutions` de 0 a 2); 10 recomendações de troca de escalação; 10 recomendações de free agent; 6 recomendações de trade 1×1. `dm_examine_constraints(decision_db)` sem violações; o `decision_db.rds` passou a conter os dois runs da semana (`preview` e `preKickoff`).

Warnings esperados: `92 consensus players without nfl_id mapping` (informativo), `4 consensus players without espn_id mapping`, `2 non-starter roster players unmapped to ffa_id`, `495 of 826 unrostered ESPN players dropped from the free agent pool`.

------------------------------------------------------------------------

## O que NÃO faz parte do ciclo

- **`archive/R/pipeline/data_pipeline_nfl.R`** e todo `archive/R/api/nfl_*.R` --- pipeline NFL legado, morto (sem `authToken` no config). Não rodar.
- **`archive/R/snippets/simulation_machine.R`**, **`archive/R/analysis/team_optimizer.R`**, **`archive/R/analysis/projection_ml.R`** --- geração de simulação "gen-1", superada pela decision engine e quebrada hoje. A "simulação" do ciclo é a fase 3 de `run_decision_pipeline`.
- **`archive/R/transformation/`**, **`archive/R/snippets/*` (demais)** --- análises ad-hoc e transformações que só alimentavam o gen-1. Cada uma lê os `.rds` e imprime/plota isoladamente.
- **`R/snippets/*`** --- análises ad-hoc que continuam em `R/`, avulsas, fora do pipeline.
