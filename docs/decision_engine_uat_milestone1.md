# UAT — Decision Engine, Milestone 1

> **Nota (M2 mergeado):** `run_decision_pipeline()` agora também roda a simulação de
> matchups por padrão (`matchups = TRUE`), então `data/decision_db.rds` tem **3
> tabelas** (não 2) e a run precisa de um snapshot ESPN válido. Para rodar só as
> previsões de jogador use `run_decision_pipeline(2026, 1, "preview", matchups = FALSE)`.
> A UAT do M2 está em `docs/decision_engine_uat_milestone2.md`.

Roteiro de aceite de usuário. Caso de sucesso simples: rodar o pipeline de decisão
para um snapshot real (`season = 2026`, `week = 1`, `tag = "preview"`), conferir as
previsões geradas, a persistência e a calibração.

Tempo estimado: ~3 minutos (passos 1–8) + ~30 s (passo 9, gate de calibração) +
~10 s (passo 10, testes).

---

## Pré-requisitos

1. Diretório de trabalho = raiz do projeto. No RStudio, abrir `DudesApp.Rproj`. Fora dele:

   ```r
   setwd("/Users/gsposito/Projects/football/DudesApp")
   ```

2. Os três bancos de entrada existem em `data/` (já atualizados pelo pipeline operacional):

   ```r
   file.exists(c("data/ffa_db.rds", "data/espn_db.rds", "data/analytical_db.rds"))
   #> TRUE TRUE TRUE
   ```

3. Pacotes: `tidyverse`, `dm`, `glue`, `lubridate` instalados.

4. (Opcional) Começar limpo: se quiser ver a primeira run "do zero", apague o banco de saída.
   Ele é recriado pelo pipeline.

   ```r
   file.remove("data/decision_db.rds")   # opcional
   ```

---

## Passo 1 — Carregar o pipeline

```r
source("R/decision/decision_pipeline.R")
```

**Verificar:** nenhum erro. Ficam disponíveis as funções `run_decision_pipeline()`,
`select_ffa_snapshot()`, `build_current_consensus()`, `simulate_players()`, etc.

---

## Passo 2 — Rodar o pipeline (caso de sucesso)

```r
res <- run_decision_pipeline(
  season = 2026,
  week   = 1,
  tag    = "preview"
)
# n_sim = 10000, seed = 1234 (defaults)
```

**Verificar no console:**

- Termina sem erro (retorna em ~2 s).
- Aparecem **avisos** (`warning` / `message`), que são **esperados e não são falha**:

  ```
  91 consensus players without nfl_id mapping
  4 consensus players without espn_id mapping
  ```

  São jogadores irrelevantes (kickers/defesas/reservas profundos) sem id cruzado.
  O spec manda apenas reportar, não abortar.

---

## Passo 3 — `run_id`

```r
res$run_id
#> "2026-W01-preview-20260908T161947"   (o timestamp final varia a cada execução)
```

**Verificar:** casa com o padrão `AAAA-Wss-tag-AAAAMMDDThhmmss`:

```r
grepl("^\\d{4}-W\\d{2}-preview-\\d{8}T\\d{6}$", res$run_id)
#> TRUE
```

---

## Passo 4 — Tabela `player_forecasts`

```r
fc <- res$player_forecasts
nrow(fc)
#> 561

dplyr::count(fc, coverage_class)
#> # A tibble: 3 × 2
#>   coverage_class     n
#>   <chr>          <int>
#> 1 ensemble         313
#> 2 single            99
#> 3 sparse           149
```

**Verificar:**

| item | esperado |
|---|---|
| linhas | **561** (um por jogador do snapshot FFA) |
| `coverage_class` | **313 ensemble / 149 sparse / 99 single** |
| colunas | 28: `run_id, season, week, tag, ffa_id, espn_id, pos, projection, n_sources, coverage_class, source_sd, source_mad, sim_mean, sim_sd, p05, p10, p25, p50, p75, p90, p95, prob_gt_10, prob_gt_15, prob_gt_20, prob_gt_25, prob_gt_30, residual_pool_level, residual_pool_n` |

---

## Passo 5 — Inspecionar um jogador (spec §39)

```r
fc |>
  dplyr::filter(pos == "WR") |>
  dplyr::arrange(dplyr::desc(projection)) |>
  dplyr::slice(1) |>
  dplyr::glimpse()
```

Saída aproximada (o WR mais bem projetado da semana):

```
$ pos                 <chr> "WR"
$ projection          <dbl> 21.6
$ n_sources           <int> 5
$ coverage_class      <chr> "ensemble"
$ sim_mean            <dbl> 22.4
$ sim_sd              <dbl> 8.9
$ p05                 <dbl> 10.4
$ p10                 <dbl> 11.8
$ p25                 <dbl> 15.8
$ p50                 <dbl> 21.3
$ p75                 <dbl> 27.4
$ p90                 <dbl> 34.4
$ p95                 <dbl> 41.4
$ prob_gt_20          <dbl> 0.57
$ residual_pool_level <int> 1
```

**Verificar:**

1. **Quantis monótonos** em todas as linhas:

   ```r
   with(fc, all(p05 <= p10 & p10 <= p25 & p25 <= p50 &
                p50 <= p75 & p75 <= p90 & p90 <= p95))
   #> TRUE
   ```

2. **Probabilidades decrescentes** (`prob_gt_10 ≥ prob_gt_15 ≥ … ≥ prob_gt_30`):

   ```r
   with(fc, all(prob_gt_10 >= prob_gt_15 & prob_gt_15 >= prob_gt_20 &
                prob_gt_20 >= prob_gt_25 & prob_gt_25 >= prob_gt_30))
   #> TRUE
   ```

3. **`sim_mean ≈ projection`, mas não idêntico.** A diferença é o viés histórico do
   consenso (pequeno para `ensemble`, maior para `single`/`sparse`). Isto é intencional —
   **não é bug**. Ordem de grandeza:

   ```r
   fc |>
     dplyr::mutate(vies = sim_mean - projection) |>
     dplyr::summarise(vies_medio = mean(vies), .by = coverage_class)
   #> ensemble  ~ +0.3 a +1
   #> sparse    ~  maior em módulo
   #> single    ~  maior em módulo
   ```

4. **`residual_pool_n >= 100`** em todas as linhas (o fallback nunca entrega um pool menor):

   ```r
   min(fc$residual_pool_n)
   #> 100  (ou mais)

   dplyr::count(fc, residual_pool_level)
   #> nível 1: ~552   nível 2: ~9   (K/DST sparse com pouco histórico caem para o nível 2)
   ```

---

## Passo 6 — Tabela `simulation_runs`

```r
res$simulation_runs |> dplyr::glimpse()
```

**Verificar:**

| campo | esperado |
|---|---|
| linhas | **1** |
| `season`, `week`, `tag` | `2026`, `1`, `"preview"` |
| `ffa_timestamp` | `2026-09-07 10:18:16` (timestamp do snapshot FFA consumido) |
| `espn_timestamp` | `2026-09-07 10:10:25` (só bookkeeping no Milestone 1) |
| `model_version` | `"player-mc-v2"` |
| `n_sim`, `seed` | `10000`, `1234` |

---

## Passo 7 — Persistência (`data/decision_db.rds`)

```r
library(dm)
db <- readRDS("data/decision_db.rds")
db
```

**Verificar:**

```r
names(db)
#> "simulation_runs" "player_forecasts"

dm_get_all_pks(db)
#> simulation_runs   : run_id
#> player_forecasts  : run_id, ffa_id, pos

dm_get_all_fks(db)
#> player_forecasts.run_id -> simulation_runs.run_id

nrow(db$player_forecasts)
#> 561   (linhas da run que acabou de rodar)
```

- O arquivo `data/decision_db.rds` existe e é um objeto `dm` com **2 tabelas**, PKs e a FK acima.
- **Draws não são persistidos** (só mean/sd/quantis/probabilidades) — confirme que
  `db$player_forecasts` não tem coluna de lista.

---

## Passo 8 — Reprodutibilidade e acúmulo

**8a. Mesma seed → previsões idênticas** (spec §38):

```r
res_b <- run_decision_pipeline(2026, 1, "preview")   # mesma seed default

a <- dplyr::select(res$player_forecasts,   -run_id)
b <- dplyr::select(res_b$player_forecasts, -run_id)
all.equal(a, b)
#> TRUE
```

**8b. O banco acumula runs** (não sobrescreve):

```r
db2 <- readRDS("data/decision_db.rds")
nrow(db2$simulation_runs)
#> 2         (uma linha por execução)
nrow(db2$player_forecasts)
#> 1122      (561 × 2)

db2$simulation_runs$run_id
#> dois run_id distintos
```

---

## Passo 9 — Gate de calibração (spec §37)

O objetivo do modelo V2 é uma **distribuição calibrada**, não só um MAE baixo. Rodar o
backtest sobre o histórico (`analytical_db$consensus_error_history`, ~28,8 mil player-weeks),
com `sample_frac = 0.25` para ficar rápido (~30 s):

```r
source("R/decision/validate_model.R")
val <- validate_player_model(
  readRDS("data/analytical_db.rds")$consensus_error_history,
  sample_frac = 0.25
)
```

Imprime uma tabela por `pos × coverage_class` + uma linha `ALL / ALL`.

**Verificar a linha `ALL`:**

| métrica | alvo | aceite |
|---|---|---|
| `cov_p10_p90` | 0.80 | entre **0.78 e 0.82** |
| `cov_p25_p75` | 0.50 | entre **0.47 e 0.53** |
| `bias` | 0 | `abs(bias) < 0.5` |

Valores de referência da última execução: `cov_p10_p90 = 0.801`, `cov_p25_p75 = 0.504`,
`bias = +0.04`, `mae = 4.45`, `rmse = 5.98`.

Por célula, esperar coberturas na mesma faixa (algumas células `sparse` têm `n` pequeno e
oscilam mais — aceitável).

---

## Passo 10 — Testes unitários

```r
source("tests/decision/run_all.R")
```

**Verificar:** as 5 linhas `PASS` e o rodapé:

```
PASS test_consensus.R
PASS test_pipeline_integration.R
PASS test_residual_pool.R
PASS test_simulation_repro.R
PASS test_snapshot.R

ALL DECISION TESTS DONE ( 5 files )
```

Qualquer `Error` / `stopifnot` interrompe o `source()` → falha.

---

## Passo 11 — Mensagem de erro clara (spec §35)

Pedir um snapshot inexistente e confirmar que a falha é explícita, não um erro obscuro:

```r
run_decision_pipeline(2026, 9, "preview")
#> Error: season/week/tag not found in ffa_db: 2026/9/preview
```

---

## Critérios de aceite (resumo)

| # | Critério | OK? |
|---|---|---|
| 1 | `run_decision_pipeline(2026, 1, "preview")` roda sem erro | ☐ |
| 2 | `run_id` no padrão `AAAA-Wss-tag-timestamp` | ☐ |
| 3 | `player_forecasts` com 561 linhas, coverage 313/149/99 | ☐ |
| 4 | Quantis monótonos e probabilidades decrescentes em todas as linhas | ☐ |
| 5 | `sim_mean` próximo mas não idêntico a `projection` (viés histórico) | ☐ |
| 6 | `residual_pool_n ≥ 100` em todas as linhas | ☐ |
| 7 | `simulation_runs` com 1 linha por execução, `n_sim`/`seed`/timestamps corretos | ☐ |
| 8 | `data/decision_db.rds` é um `dm` com 2 tabelas, PKs e FK | ☐ |
| 9 | Mesma seed → previsões idênticas; banco acumula runs | ☐ |
| 10 | Gate de calibração: `cov_p10_p90 ≈ 0.80`, `cov_p25_p75 ≈ 0.50` | ☐ |
| 11 | 5 testes unitários com `PASS` | ☐ |
| 12 | Snapshot inexistente → erro com mensagem clara | ☐ |
