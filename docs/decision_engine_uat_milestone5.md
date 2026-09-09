# UAT — Decision Engine, Milestone 5 (1×1 Trade Recommender)

Roteiro de aceite. Caso de sucesso simples: rodar o pipeline para o snapshot real
`season = 2026`, `week = 1`, `tag = "preview"` e conferir as trocas 1×1
recomendadas para o time escolhido (`trade_recommendations`, spec §24–28/§43) e a
persistência num `dm` de 7 tabelas.

Tempo estimado: ~30 s (o motor de trades roda `evaluate_roster()` algumas centenas
de vezes; ~8 s a mais que o M4 com `n_sim = 10000`).

Pré-requisitos: iguais ao M1–M4 (working dir = raiz do projeto; `data/ffa_db.rds`,
`data/espn_db.rds`, `data/analytical_db.rds` presentes; `config/config.yml` com
`myTeamEspnId`). M5 não lê nenhuma tabela ESPN nova além das que o M2–M4 já usam.

---

## Passo 1 — Rodar o pipeline (trades ligado por padrão)

```r
source("R/decision/decision_pipeline.R")
res <- run_decision_pipeline(2026, 1, "preview")   # trades = TRUE por default
```

**Verificar no console:** termina sem erro (~30 s). Avisos esperados (não são
falha) são os mesmos do M2–M4:

```
91 consensus players without nfl_id mapping
4 consensus players without espn_id mapping
2 non-starter roster players unmapped to ffa_id
```

Na primeira run após o merge do M5, também aparece (esperado, igual a cada
milestone anterior):

```
decision_db schema changed (now: simulation_runs, player_forecasts,
matchup_simulations, lineup_evaluations, lineup_recommendations,
free_agent_recommendations, trade_recommendations); starting fresh run history
```

---

## Passo 2 — Tabela `trade_recommendations` (spec §28, §43)

```r
tr <- res$trade_recommendations
nrow(tr)                       #> 0..25  (só do time config$myTeamEspnId)
dplyr::glimpse(tr)
```

**Verificar:**

| item | esperado |
|---|---|
| colunas | `run_id, season, week, tag, my_team_id, other_team_id, give_player_id, give_ffa_id, receive_player_id, receive_ffa_id, give_position, receive_position, my_before_expected, my_after_expected, my_delta_expected, their_before_expected, their_after_expected, their_delta_expected, my_before_win_probability, my_after_win_probability, my_delta_win_probability, fairness, trade_score, partner_is_my_opponent, recommendation_rank` |
| `my_team_id` | todas as linhas == `config$myTeamEspnId` (4) |
| `other_team_id` | sempre `!= my_team_id` |
| `my_delta_expected` | **> 0** em toda linha (regra dura da spec §26) |
| `their_delta_expected` | **>= 0** em toda linha (default `min_their_delta = 0`) |
| `give_player_id` | sempre um jogador do meu roster; `receive_player_id` nunca |
| `recommendation_rank` | `1..nrow`, ordenado por `trade_score` desc |

Saída de referência (última execução — os números variam com o refresh dos dados):

```
 other_team_id give_ffa_id receive_ffa_id give_pos receive_pos my_before my_after my_delta their_delta trade_score partner_is_my_opponent rank
            14       16193          16188       WR         WR      118.6    120.2    1.65          0        1.65                  FALSE     1
             1       16193          15789       WR         WR      118.6    120.1    1.46          0        1.46                   TRUE     2
             5       16193          15768       WR         WR      118.6    119.4    0.82          0        0.82                  FALSE     3
             ...
```

Aqui o motor achou trocas em que dou um WR de banco meu (`ffa 16193`) por um WR de
banco do parceiro que preenche melhor minha vaga fina de WR — o parceiro fica
indiferente (`their_delta == 0`, troca de excedente).

---

## Passo 3 — Aritmética de `trade_score` e `fairness` (spec §27)

```r
with(tr, all(abs(trade_score -
  (my_delta_expected + pmin(my_delta_expected, their_delta_expected))) < 1e-9))   #> TRUE
with(tr, all(abs(fairness + abs(my_delta_expected - their_delta_expected)) < 1e-9))   #> TRUE
with(tr, all(abs((my_after_expected  - my_before_expected)  - my_delta_expected)  < 1e-9))   #> TRUE
with(tr, all(abs((their_after_expected - their_before_expected) - their_delta_expected) < 1e-9))   #> TRUE
```

`trade_score = my_delta + pmin(my_delta, their_delta)`: uma troca ruim para o
parceiro (`their_delta < 0`) é puxada para baixo pelo `pmin`, então trocas
mutuamente boas sobem no ranking sozinhas. `my_delta_win_probability` é
**reportado, não ordena** (ruído de Monte Carlo — mesma escolha do M3/M4).

---

## Passo 4 — `partner_is_my_opponent` (teto conhecido)

```r
dplyr::count(tr, partner_is_my_opponent)
```

Quando `TRUE`, o parceiro da troca é o meu adversário desta semana. Nessas linhas
`my_*_win_probability` fica **otimista**: o jogador recebido é contado nos dois
lados do meu matchup simulado (no meu lineup e no lineup fixo do adversário, spec
§41). `my_delta_expected` / `trade_score` / `recommendation_rank` **não** são
afetados (valor de lineup independe do adversário). Se a precisão de win
probability importar para essas linhas, filtre-as.

---

## Passo 5 — Reprodutibilidade

```r
a <- dplyr::select(res$trade_recommendations, -run_id)
res_b <- run_decision_pipeline(2026, 1, "preview", persist = FALSE)
all.equal(a, dplyr::select(res_b$trade_recommendations, -run_id))
#> TRUE                       # mesma seed -> trades idênticos (não há RNG novo no M5)
```

---

## Passo 6 — Persistência (`dm` de 7 tabelas)

```r
library(dm)
d <- readRDS("data/decision_db.rds")
names(d)
#> "simulation_runs" "player_forecasts" "matchup_simulations" "lineup_evaluations"
#> "lineup_recommendations" "free_agent_recommendations" "trade_recommendations"

dm_examine_constraints(d)
#> ℹ All constraints satisfied.

dm_get_all_pks(d)   |> dplyr::filter(table == "trade_recommendations")
#> trade_recommendations : run_id, other_team_id, give_player_id, receive_player_id

dm_get_all_fks(d)   |> dplyr::filter(child_table == "trade_recommendations")
#> trade_recommendations.run_id -> simulation_runs
```

Se existir um `data/decision_db.rds` antigo de 6 tabelas (rodou M4 antes do M5), a
primeira run M5 imprime `decision_db schema changed ...; starting fresh run
history` e sobrescreve — esperado, aquelas runs não tinham trades.

---

## Passo 7 — Testes unitários

```r
source("tests/decision/run_all.R")
```

**Verificar:** 13 arquivos, todos `PASS` (M1–M4 + `test_trades.R`; +
`test_pipeline_integration.R` com o bloco M5):

```
PASS test_trades.R
ALL DECISION TESTS DONE ( 13 files )
```

---

## Passo 8 — `trades = FALSE` desliga a etapa

```r
res_nt <- run_decision_pipeline(2026, 1, "preview", trades = FALSE, persist = FALSE)
is.null(res_nt$trade_recommendations)          #> TRUE
length(res_nt$decision_db)                     #> 6
```

---

## Passo 9 — Erro claro sem snapshot (inalterado)

```r
run_decision_pipeline(2026, 9, "preview")
#> Error: season/week/tag not found in ffa_db: 2026/9/preview
```

---

## Critérios de aceite (resumo)

| # | Critério | OK? |
|---|---|---|
| 1 | `run_decision_pipeline(2026, 1, "preview")` roda sem erro (~30 s) | ☐ |
| 2 | `trade_recommendations` com <= 25 linhas, schema completo, todas `my_team_id == config$myTeamEspnId` | ☐ |
| 3 | `my_delta_expected > 0` e `their_delta_expected >= 0` em toda linha | ☐ |
| 4 | `give_player_id` sempre no meu roster; `receive_player_id` nunca | ☐ |
| 5 | `trade_score == my_delta + pmin(my_delta, their_delta)`; `fairness == -abs(my_delta - their_delta)` | ☐ |
| 6 | `recommendation_rank` sequencial, ordenado por `trade_score` desc | ☐ |
| 7 | `partner_is_my_opponent` entendido (teto de win probability) | ☐ |
| 8 | Mesma seed → trades idênticos (menos `run_id`) | ☐ |
| 9 | `data/decision_db.rds` é `dm` de 7 tabelas, `dm_examine_constraints` limpo, PK/FK de `trade_recommendations` corretas | ☐ |
| 10 | 13 testes unitários com `PASS` | ☐ |
| 11 | `trades = FALSE` → `res$trade_recommendations` é `NULL`, `dm` de 6 tabelas | ☐ |
