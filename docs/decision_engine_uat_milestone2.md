# UAT — Decision Engine, Milestone 2 (Matchup Simulation)

Roteiro de aceite. Caso de sucesso simples: rodar o pipeline para o snapshot real
`season = 2026`, `week = 1`, `tag = "preview"` e conferir o estado da liga
(`current_players`), a ponte de ids ESPN→FFA, as 7 simulações de confronto
(`matchup_simulations`) e a persistência num `dm` de 3 tabelas.

Tempo estimado: ~2 minutos.

Pré-requisitos: iguais ao M1 (working dir = raiz do projeto; `data/ffa_db.rds`,
`data/espn_db.rds`, `data/analytical_db.rds` presentes). M2 usa também
`espn_db$espn_rosters` / `espn_matchups` / `espn_player_injury_status` do snapshot.

---

## Passo 1 — Rodar o pipeline (matchups ligado por padrão)

```r
source("R/decision/decision_pipeline.R")
res <- run_decision_pipeline(2026, 1, "preview")   # matchups = TRUE por default
```

**Verificar no console:** termina sem erro (~2 s). Avisos esperados (não são falha):

```
91 consensus players without nfl_id mapping
4 consensus players without espn_id mapping
2 non-starter roster players unmapped to ffa_id
```

O terceiro é novo no M2: 2 jogadores de **banco** sem `ffa_id` — só warning
(spec §35 só falha se faltar **starter**).

---

## Passo 2 — Estado da liga (`current_players`, spec §12)

```r
cp <- res$current_players
nrow(cp)                          #> 210  (todos os jogadores rosterados)
sum(cp$is_starter)                #> 126  (14 times × 9 titulares)
```

**Verificar:**

| item | esperado |
|---|---|
| linhas | **210** |
| titulares | **126** |
| todo titular tem forecast | `cp |> dplyr::filter(is_starter, is.na(sim_mean)) |> nrow()` → **0** |
| `pos` normalizado | `"D/ST"` da ESPN vira `"DST"` |
| colunas | inclui `team_id, espn_id, ffa_id, bridge_method, lineup_slot, is_starter/is_bench/is_ir, injury_status, injured, active, projection, sim_mean, sim_sd, p10, p50, p90` |

---

## Passo 3 — Ponte de ids ESPN → FFA

```r
dplyr::count(cp, bridge_method)
```

Esperado (210 jogadores rosterados):

```
  bridge_method     n
1 dst_offset       14      # defesas (id ESPN negativo -> 44000 - id)
2 espn_id         165      # match direto no crosswalk
3 name_pos         29      # nome normalizado + posição
4 <NA>              2      # 2 de banco não mapeados (ok)
```

**Verificar:** os **126 titulares** estão todos mapeados —

```r
cp |> dplyr::filter(is_starter) |> dplyr::count(bridge_method)
#>   dst_offset 14 / espn_id 96 / name_pos 16   (total 126, nenhum NA)
```

Se um titular não mapear, o pipeline **para** com o nome do jogador. Correção
rápida sem mexer em código: criar `data/decision_espn_ffa_overrides.rds` —

```r
saveRDS(tibble::tibble(player_id = <id ESPN>, ffa_id = <id FFA>),
        "data/decision_espn_ffa_overrides.rds")
```

A estratégia 0 (esse arquivo) é consultada antes das outras 3.

---

## Passo 4 — Simulações de confronto (`matchup_simulations`, spec §15)

```r
res$matchup_simulations |>
  dplyr::select(matchup_id, home_team_id, away_team_id,
                home_expected, away_expected,
                home_p10, home_p50, home_p90,
                home_win_probability, away_win_probability, tie_probability) |>
  print(n = 7)
```

Saída de referência:

```
 matchup_id home away   home_exp away_exp  p10  p50  p90   home_win away_win  tie
          1   14    6      116.2    115.2   90  115  144      0.517    0.483    0
          2    9    7      116.5    119.5   91  116  143      0.461    0.539    0
          3    2    3      107.9    119.8   83  107  134      0.339    0.661    0
          4    4    1      117.7    115.3   92  117  145      0.529    0.471    0
          5    8   12      120.1    116.9   94  119  147      0.552    0.448    0
          6    5   11      121.8    119.9   95  121  150      0.524    0.476    0
          7   15   16      118.6    113.6   92  118  146      0.568    0.432    0
```

**Verificar:**

| item | esperado |
|---|---|
| linhas | **7** (14 times / 2) |
| pares `(home, away)` | (14,6)(9,7)(2,3)(4,1)(8,12)(5,11)(15,16) |
| probabilidades somam 1 | `with(ms, all(abs(home_win_probability + away_win_probability + tie_probability - 1) < 1e-9))` → **TRUE** |
| quantis monótonos | `home_p10 < home_p50 < home_p90` em toda linha |
| `tie_probability` | ≈ 0 (somas de resíduos reamostrados quase nunca empatam exato) |
| `home_win_probability` em `[0, 1]` | sim |

---

## Passo 5 — Sanidade dos totais de time

```r
es <- readRDS("data/espn_db.rds")
mp <- es$espn_matchups |>
  dplyr::filter(season == 2026, week == 1, tag == "preview", matchup_period_id == 1)
res$matchup_simulations |>
  dplyr::select(matchup_id, home_expected, away_expected) |>
  dplyr::left_join(dplyr::select(mp, matchup_id, home_projected_points, away_projected_points),
                   by = "matchup_id")
```

**Esperado / entender:** `home_expected` ≈ **110–125**, contra a projeção da própria
ESPN de **~97–106**. A diferença (~+15) é legítima e vem de duas fontes:

1. **~+3** — as fontes do FFA projetam um pouco acima da ESPN (consenso ≈ 106 vs ESPN ≈ 102).
2. **~+11** — o *uplift* empírico dos resíduos históricos: o consenso **subprojeta
   sistematicamente** algumas posições. O maior efeito é **kicker** (`sim_mean` ≈ 9 vs
   `projection` ≈ 5.2): historicamente um K projetado para ~5 pts marca ~8.5 na média
   (`analytical_db$consensus_error_history`, K ensemble, proj 4–6: 757 amostras, resíduo
   médio +3.4). QB (+1.4) e TE (+1.2) também contribuem.

Isso é o modelo fazendo exatamente o que a spec §46 manda
(`actual = projection + sample(residual_histórico)`), não um bug do M2. Se incomodar,
é uma questão de calibração das projeções de kicker do FFA — território do M1
(`validate_player_model`), não do motor de matchup.

Bloqueio real só se `home_expected` sair de **(70, 160)**.

---

## Passo 6 — Persistência (`dm` de 3 tabelas)

```r
library(dm)
d <- readRDS("data/decision_db.rds")
names(d)
#> "simulation_runs" "player_forecasts" "matchup_simulations"

dm_examine_constraints(d)
#> ℹ All constraints satisfied.

dm_get_all_pks(d)
#> simulation_runs      : run_id
#> player_forecasts     : run_id, ffa_id, pos
#> matchup_simulations  : run_id, matchup_id

dm_get_all_fks(d)
#> player_forecasts.run_id     -> simulation_runs
#> matchup_simulations.run_id  -> simulation_runs

nrow(d$matchup_simulations)   #> 7
```

Se existir um `data/decision_db.rds` antigo de 2 tabelas (rodou M1 com
`persist = TRUE` antes do M2), a primeira run M2 imprime
`decision_db schema changed ...; starting fresh run history` e sobrescreve —
esperado, aquelas runs não tinham matchups.

---

## Passo 7 — Reprodutibilidade e acúmulo

```r
a <- dplyr::select(res$matchup_simulations, -run_id)
res_b <- run_decision_pipeline(2026, 1, "preview", persist = FALSE)
all.equal(a, dplyr::select(res_b$matchup_simulations, -run_id))
#> TRUE                       # mesma seed -> matchups idênticos (não há RNG novo no M2)

d2 <- readRDS("data/decision_db.rds")
nrow(d2$simulation_runs)      #> 2
nrow(d2$matchup_simulations)  #> 14
```

---

## Passo 8 — Testes unitários

```r
source("tests/decision/run_all.R")
```

**Verificar:** 8 arquivos, todos `PASS` (M1: consensus, residual_pool, simulation_repro,
snapshot; M2: espn_bridge, league_state, matchup_sim; + pipeline_integration):

```
ALL DECISION TESTS DONE ( 8 files )
```

---

## Passo 9 — Erro claro sem snapshot ESPN

```r
run_decision_pipeline(2026, 9, "preview")
#> Error: season/week/tag not found in espn_db: 2026/9/preview
```

(Antes do M2 o snapshot ESPN era um stub que devolvia `NA`; agora falha explícito,
spec §35.)

---

## Critérios de aceite (resumo)

| # | Critério | OK? |
|---|---|---|
| 1 | `run_decision_pipeline(2026, 1, "preview")` roda sem erro | ☐ |
| 2 | `current_players` com 210 linhas, 126 titulares, todos com `sim_mean` | ☐ |
| 3 | 126 titulares mapeados a `ffa_id` (`bridge_method` sem `NA` entre titulares) | ☐ |
| 4 | `matchup_simulations` com 7 linhas, pares corretos | ☐ |
| 5 | `home_win + away_win + tie == 1` (±1e-9) em toda linha; quantis monótonos | ☐ |
| 6 | `home_expected`/`away_expected` em (70, 160); drift vs ESPN entendido (kicker/QB/TE uplift) | ☐ |
| 7 | `data/decision_db.rds` é `dm` de 3 tabelas, `dm_examine_constraints` limpo | ☐ |
| 8 | Mesma seed → matchups idênticos; banco acumula runs (2 runs → 14 linhas) | ☐ |
| 9 | 8 testes unitários com `PASS` | ☐ |
| 10 | Snapshot ESPN inexistente → erro com mensagem clara | ☐ |
