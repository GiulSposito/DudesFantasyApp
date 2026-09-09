A spec abaixo já está em formato que você pode colocar no repositório, por exemplo em `docs/DECISION_ENGINE_SPEC.md` ou referenciar pelo `CLAUDE.md`.

# Fantasy Decision Engine — Implementation Spec

## 1. Objetivo

Construir uma camada de decisão para Fantasy NFL, totalmente em **R**, utilizando os bancos existentes:

* `data/ffa_db.rds`
* `data/espn_db.rds`
* `data/analytical_db.rds`

A execução recebe obrigatoriamente:

```text
season
week
tag
```

e produz previsões, simulações e recomendações para o snapshot correspondente.

O sistema deverá suportar progressivamente:

1. projeção probabilística de pontos por jogador;
2. simulação Monte Carlo de matchups;
3. recomendação de escalação;
4. recomendação de Add/Drop usando Free Agents;
5. recomendação de trades entre times;
6. persistência dos resultados para relatórios e dashboards.

O sistema **não deve refazer scraping/importação**. Assume que `ffa_db` e `espn_db` já foram atualizados pelo pipeline operacional antes da execução.

---

# 2. Princípios de arquitetura

Manter a solução simples.

Stack principal:

```r
R
tidyverse
dm
```

Usar os arquivos `.rds` existentes como persistência.

Não introduzir:

```text
DuckDB
SQLite
Postgres
Spark
serviços externos
microservices
orquestradores
```

sem necessidade futura comprovada.

Separar claramente:

```text
INGESTÃO
  ffa_db / espn_db

HISTÓRICO E CALIBRAÇÃO
  analytical_db

DECISÃO
  decision_db
```

O `analytical_db` já contém projeções históricas source-level, consensus e histórico de resíduos necessários para a calibração. 

O `espn_db` contém o estado operacional atual da liga: times, jogadores, rosters, matchups, injury status, scoring rules e demais fatos relevantes. 

---

# 3. Premissa de scoring

O scoring utilizado pela ESPN e pela FFA já é compatível.

Existe previamente:

```text
score_rules.yaml
```

utilizado pelo motor de cálculo ESPN.

Portanto:

```text
FFA projected fantasy points
```

e:

```text
ESPN actual/projected fantasy points
```

devem ser tratados como pertencentes à mesma escala de fantasy points.

A implementação desta spec **não deve recalcular ou reinterpretar scoring rules**.

---

# 4. Interface principal

Criar uma função/orquestrador:

```r
build_decision_db(
  season,
  week,
  tag,
  n_sim = 10000,
  seed = 1234
)
```

Exemplo:

```r
build_decision_db(
  season = 2026,
  week = 2,
  tag = "preview"
)
```

A função deve:

```text
1. carregar os bancos
2. selecionar os snapshots
3. construir projections atuais
4. simular jogadores
5. construir estado da liga
6. simular matchups
7. otimizar lineups
8. avaliar Free Agents
9. avaliar trades
10. persistir decision_db.rds
```

As etapas devem continuar disponíveis como funções independentes.

---

# 5. Seleção de snapshot

## 5.1 FFA

Selecionar no `ffa_db` o snapshot correspondente a:

```text
season
week
tag
```

Como o FFA usa `timestamp` como parte da chave do scrape, pode existir mais de uma execução para a mesma combinação. O banco mantém snapshots acumulados. 

Dentro da combinação:

```text
season + week + tag
```

selecionar:

```r
max(timestamp)
```

e usar **todas as projeções daquele timestamp**.

Nunca selecionar o último timestamp individualmente por jogador/source.

A unidade do snapshot é:

```text
season + week + tag + timestamp
```

Depois recuperar desse snapshot:

```text
ffa_proj_source_points
ffa_projtable
ffa_players
ffa_player_ids
```

A base FFA já possui tanto projeções por source quanto consensus `average / robust / weighted`. 

---

## 5.2 ESPN

Aplicar a mesma lógica:

```text
season
week
tag
```

e selecionar o maior `timestamp` disponível para esse snapshot.

Recuperar pelo menos:

```text
espn_players
espn_rosters
espn_matchups
espn_player_injury_status
espn_teams
espn_roster_slots
```

O ESPN DB possui explicitamente roster, starters/bench/IR, injuries e matchups. 

---

# 6. Identidade de jogador

Internamente utilizar preferencialmente:

```text
ffa_id
espn_id
```

com o crosswalk:

```text
analytical_db$player_ids
```

ou:

```text
ffa_db$ffa_player_ids
```

O catálogo registra que `ffa_player_ids$espn_id` é a ponte FFA → ESPN. 

Criar uma função:

```r
build_current_player_xref()
```

que retorne:

```text
ffa_id
espn_id
nfl_id
numfire_id
```

Não usar nomes como chave primária.

---

# 7. STEP 1 — Current consensus

Criar:

```r
build_current_consensus()
```

Entrada:

```text
FFA snapshot atual
```

Saída:

```text
current_consensus
```

Granularidade:

```text
1 linha = season × week × ffa_id × pos
```

Schema mínimo:

```text
season
week
tag
ffa_id
pos

n_sources
sources

projection

source_median
source_sd
source_mad
source_min
source_max
source_range

coverage_class
```

Calcular:

```r
projection = mean(proj_points)
```

```r
source_median = median(proj_points)
```

```r
source_sd = sd(proj_points)
```

```r
source_mad = mad(proj_points)
```

```r
source_range = source_max - source_min
```

Para:

```text
n_sources < 2
```

usar:

```text
source_sd    = NA
source_mad   = NA
source_range = NA
```

Definir inicialmente:

```r
coverage_class = case_when(
  n_sources == 1 ~ "single",
  n_sources <= 3 ~ "sparse",
  TRUE           ~ "ensemble"
)
```

O `analytical_db` utiliza exatamente essa definição histórica de coverage. 

---

# 8. STEP 2 — Player Monte Carlo V2

Criar:

```r
simulate_player()
```

Responsabilidade:

> transformar uma projeção atual pontual em uma distribuição preditiva baseada nos erros históricos observados.

Fonte histórica:

```text
analytical_db$consensus_error_history
```

A tabela possui:

```text
projection
actual_points
residual
coverage_class
position
source_sd
source_mad
...
```

e cerca de 28,8 mil player-weeks históricos. 

---

## 8.1 Residual

Definição existente:

```text
residual =
actual_points - projection
```

Portanto:

```text
actual_points =
projection + residual
```

A simulação seguirá exatamente essa identidade.

---

# 9. Seleção do residual pool

Para um jogador atual:

```text
position = WR
projection = 15.4
coverage_class = ensemble
```

selecionar primeiro:

```r
filter(
  pos == current_pos,
  coverage_class == current_coverage
)
```

Em seguida calcular:

```r
distance =
  abs(projection - current_projection)
```

Ordenar por `distance`.

Usar inicialmente:

```text
k = 300
```

observações históricas.

Criar:

```r
get_residual_pool(
  pos,
  projection,
  coverage_class,
  history,
  k = 300
)
```

---

## 9.1 Fallbacks

É obrigatório existir fallback para pools pequenos.

Hierarquia:

```text
LEVEL 1
position + coverage + projection neighborhood

LEVEL 2
position + projection neighborhood

LEVEL 3
position

LEVEL 4
all historical residuals
```

Nunca falhar apenas porque determinada combinação possui histórico insuficiente.

Definir:

```text
min_pool_size = 100
```

como default inicial.

---

# 10. Simulação do jogador

Para cada jogador:

```r
simulated_points <-
  current_projection +
  sample(
    residual_pool,
    size = n_sim,
    replace = TRUE
  )
```

Aplicar:

```r
set.seed(seed)
```

em nível de execução, e não individualmente dentro de cada função.

Não assumir distribuição Normal.

Não usar:

```text
source_sd
```

como SD da distribuição de fantasy points.

`source_sd` mede disagreement entre sources; o residual histórico mede erro real da projeção.

---

# 11. Output do player simulation

Gerar duas representações.

## 11.1 Draws

Em memória:

```text
player_simulation_draws
```

Schema:

```text
simulation_id
ffa_id
espn_id
points
```

Esses draws serão usados para compor os matchups.

Não é obrigatório persistir todos os draws.

---

## 11.2 Summary

Persistir:

```text
player_forecasts
```

Schema:

```text
season
week
tag

ffa_id
espn_id
pos

projection

n_sources
coverage_class
source_sd
source_mad

sim_mean
sim_sd

p05
p10
p25
p50
p75
p90
p95

prob_gt_10
prob_gt_15
prob_gt_20
prob_gt_25
prob_gt_30
```

---

# 12. STEP 3 — Current League State

Criar:

```r
build_current_league_state()
```

Entrada:

```text
espn_db snapshot
current player forecasts
```

Construir uma visão integrada:

```text
current_players
```

Granularidade:

```text
1 jogador ESPN
```

Campos:

```text
season
week
team_id

espn_id
ffa_id

player_name
position
nfl_team

lineup_slot
is_starter
is_bench
is_ir

injury_status
injured
active

projection
sim_mean
sim_sd
quantiles...
```

---

# 13. Identificação de Free Agents

Criar:

```r
get_free_agents()
```

Regra:

```text
espn_players
ANTI JOIN
espn_rosters
```

para o snapshot corrente.

Gerar:

```text
current_free_agents
```

com:

```text
player_id
ffa_id
position
projection
sim_mean
p10
p50
p90
```

Não considerar jogadores IR/inativos automaticamente como Free Agents se ainda estiverem rostered.

---

# 14. STEP 4 — Matchup Simulation

Criar:

```r
simulate_matchup()
```

Entrada:

```text
home roster
away roster
player draws
```

Inicialmente utilizar o lineup atualmente marcado como starter pela ESPN.

Para cada Monte Carlo iteration:

```r
home_points =
  sum(draw[player starters home])

away_points =
  sum(draw[player starters away])
```

Comparar:

```r
home_points > away_points
```

---

# 15. Matchup output

Persistir:

```text
matchup_simulations
```

Schema:

```text
season
week
tag

matchup_id

home_team_id
away_team_id

home_expected
away_expected

home_p10
home_p50
home_p90

away_p10
away_p50
away_p90

home_win_probability
away_win_probability
tie_probability

n_sim
```

Não persistir inicialmente cada uma das 10 mil draws de matchup.

---

# 16. STEP 5 — Lineup Optimizer

Criar:

```r
optimize_lineup()
```

Responsabilidade:

> encontrar o melhor lineup legal possível para um roster.

Regras dos slots devem vir de:

```text
espn_roster_slots
```

e do formato atual da liga.

Nunca hard-code a quantidade de:

```text
QB
RB
WR
TE
FLEX
...
```

se essa informação puder ser obtida do ESPN DB.

---

## 16.1 Primeira função objetivo

Implementar primeiro:

```text
maximize expected fantasy points
```

Formalmente:

```text
maximize
sum(sim_mean[player])
```

sujeito às regras dos slots.

Isso gera:

```text
optimal_expected_lineup
```

---

## 16.2 Segunda função objetivo

Após a implementação básica funcionar, permitir:

```text
maximize win probability
```

Nesse modo:

1. gerar lineups candidatos;
2. simular cada lineup contra o adversário atual;
3. selecionar o de maior:

```text
P(win)
```

---

# 17. Lineup Recommendation

Criar:

```r
recommend_lineup()
```

Comparar:

```text
current ESPN lineup
```

versus:

```text
optimized lineup
```

Persistir apenas as diferenças.

Schema:

```text
season
week
tag
team_id

player_out
player_in
slot

current_expected
optimized_expected
delta_expected

current_win_probability
optimized_win_probability
delta_win_probability

recommendation_rank
```

---

# 18. STEP 6 — Roster Evaluator

Criar uma abstração central:

```r
evaluate_roster()
```

Entrada:

```text
roster
week
opponent
player forecasts
```

Output:

```text
optimal_lineup
expected_points
p10
p50
p90
win_probability

bench_value
```

Esta função será utilizada por:

```text
Lineup
Free Agents
Trades
```

A função deve ser determinística dado:

```text
inputs
seed
n_sim
```

---

# 19. STEP 7 — Free Agent Recommendations

Criar:

```r
recommend_free_agents()
```

Objetivo:

> descobrir quais movimentos ADD/DROP aumentam o valor do roster.

Para cada jogador elegível do roster:

```text
DROP player A
```

e cada Free Agent candidato:

```text
ADD player B
```

construir:

```text
candidate_roster
```

e calcular:

```text
before =
evaluate_roster(current_roster)

after =
evaluate_roster(candidate_roster)
```

---

# 20. FA objective

MVP:

```text
delta_expected_points
```

e:

```text
delta_win_probability
```

para a semana corrente.

Calcular:

```text
delta_expected =
after_expected - before_expected
```

```text
delta_win_probability =
after_pwin - before_pwin
```

---

# 21. FA candidate pruning

Evitar explosão combinatória desnecessária.

Na primeira versão:

* excluir IR/inactive como candidatos a ADD;
* respeitar restrições de roster;
* descartar jogadores sem projection;
* considerar apenas Free Agents com projeção minimamente relevante;
* testar prioritariamente jogadores da mesma posição ou posições compatíveis;
* depois permitir alterações cross-position quando o roster continuar válido.

---

# 22. FA output

Persistir:

```text
free_agent_recommendations
```

Schema:

```text
season
week
tag

team_id

drop_player_id
drop_ffa_id

add_player_id
add_ffa_id

drop_position
add_position

before_expected
after_expected
delta_expected

before_win_probability
after_win_probability
delta_win_probability

recommendation_rank
```

---

# 23. Evolução futura do FA

O MVP é week-specific.

Depois adicionar horizonte:

```text
next_4_weeks
rest_of_season
```

Futura função:

```r
evaluate_roster_ros()
```

Não implementar no primeiro milestone.

---

# 24. STEP 8 — Trade Engine

Criar:

```r
recommend_trades()
```

Objetivo:

> identificar trocas que melhoram o roster do time alvo e que tenham valor não-negativo ou positivo para o outro time.

---

# 25. Primeiro universo de trade

Implementar apenas:

```text
1 jogador × 1 jogador
```

Para cada adversário:

```text
my_player
x
their_player
```

Construir:

```text
my_roster_after

their_roster_after
```

Calcular:

```r
my_before     <- evaluate_roster(my_roster)
my_after      <- evaluate_roster(my_roster_after)

their_before  <- evaluate_roster(their_roster)
their_after   <- evaluate_roster(their_roster_after)
```

Então:

```text
delta_me =
my_after - my_before
```

```text
delta_them =
their_after - their_before
```

---

# 26. Trade filtering

Primeira regra:

```text
delta_me > 0
```

Preferencialmente:

```text
delta_them >= 0
```

Priorizar:

```text
delta_me > 0
AND
delta_them > 0
```

porque esses são trades estruturalmente plausíveis para ambos os managers.

---

# 27. Trade ranking

Criar inicialmente:

```r
trade_score =
  delta_me +
  pmin(delta_me, delta_them)
```

ou manter ranking multidimensional:

```text
delta_me
delta_them
fairness
```

Evitar inventar um algoritmo excessivamente complexo antes de validar os resultados.

---

# 28. Trade output

Persistir:

```text
trade_recommendations
```

Schema:

```text
season
week
tag

my_team_id
other_team_id

give_player_id
give_ffa_id

receive_player_id
receive_ffa_id

my_value_before
my_value_after
my_delta

their_value_before
their_value_after
their_delta

fairness
trade_score

recommendation_rank
```

---

# 29. Evolução futura de Trades

Somente depois do `1 × 1` funcionar:

```text
2 × 1
1 × 2
```

Não implementar:

```text
2 × 2
3 × 2
...
```

no MVP.

---

# 30. Persistência — decision_db.rds

Criar:

```text
data/decision_db.rds
```

como objeto `{dm}`.

Tabelas propostas:

```text
simulation_runs
player_forecasts
matchup_simulations
lineup_recommendations
free_agent_recommendations
trade_recommendations
```

---

# 31. simulation_runs

Todo processamento gera um:

```text
run_id
```

Schema:

```text
run_id
created_at

season
week
tag

ffa_timestamp
espn_timestamp

model_version
n_sim
seed
```

Exemplo:

```text
run_id =
2026-W02-preview-20260908T153000
```

Todas as tabelas de decisão devem possuir:

```text
run_id
```

---

# 32. Persistência dos draws

Default:

```text
NÃO persistir
```

os 10 mil draws individuais.

Persistir:

```text
mean
sd
quantiles
probabilities
```

Draws ficam em memória durante a execução.

Opcionalmente permitir:

```r
persist_draws = FALSE
```

para debug/backtest.

---

# 33. Estrutura de código sugerida

```text
R/
├── decision/
│   ├── snapshot.R
│   ├── current_consensus.R
│   ├── player_simulation.R
│   ├── league_state.R
│   ├── matchup_simulation.R
│   ├── lineup_optimizer.R
│   ├── roster_evaluator.R
│   ├── free_agents.R
│   ├── trades.R
│   ├── decision_db.R
│   └── decision_pipeline.R
```

Evitar criar classes ou abstrações complexas sem benefício claro.

Funções simples retornando `tibble` são preferíveis.

---

# 34. Pipeline principal

Criar:

```r
run_decision_pipeline(
  season,
  week,
  tag,
  n_sim = 10000,
  seed = 1234
)
```

Fluxo:

```text
load databases
       │
       ▼
select snapshots
       │
       ▼
build_current_consensus()
       │
       ▼
simulate_players()
       │
       ▼
build_current_league_state()
       │
       ├─────────────────────┐
       │                     │
       ▼                     ▼
simulate_matchups()    optimize_lineups()
                             │
                             ▼
                      evaluate_rosters()
                             │
                   ┌─────────┴─────────┐
                   │                   │
                   ▼                   ▼
          recommend_free_agents   recommend_trades
                   │                   │
                   └─────────┬─────────┘
                             ▼
                     build_decision_db()
                             │
                             ▼
                  data/decision_db.rds
```

---

# 35. Validações obrigatórias

Cada execução deve falhar com mensagem clara se:

### FFA snapshot não existir

```text
season/week/tag not found in ffa_db
```

### ESPN snapshot não existir

```text
season/week/tag not found in espn_db
```

### ID mapping insuficiente

Reportar:

```text
FFA players sem ESPN mapping
ESPN players sem FFA mapping
```

Não necessariamente falhar para jogadores irrelevantes.

Falhar apenas se starters ou candidatos relevantes não puderem ser mapeados.

---

# 36. Data quality checks

Antes da simulação verificar:

```text
1 linha por FFA source/player/week/snapshot

1 consensus por player/week

1 ESPN roster assignment por team/player

no duplicated starter slot

all lineup slots accounted for

all projected starters have forecast
```

---

# 37. Monte Carlo validation

Antes de usar o modelo para recomendação, criar uma função:

```r
validate_player_model()
```

que execute backtest usando:

```text
analytical_db$consensus_error_history
```

Avaliar principalmente:

```text
P10-P90 expected coverage ≈ 80%

P25-P75 expected coverage ≈ 50%

bias

MAE

RMSE
```

O objetivo principal da V2 é calibrar a **distribuição**, não apenas reduzir MAE.

---

# 38. Tests mínimos

Criar tests para:

```text
snapshot selection
consensus calculation
single-source handling
residual pool selection
fallback pools
Monte Carlo reproducibility
roster slot legality
lineup optimization
FA roster validity
trade roster validity
```

---

# 39. Critérios de aceite — Milestone 1

Antes de implementar FA ou trades, o sistema deve conseguir:

```r
result <- run_decision_pipeline(
  season = 2026,
  week = 2,
  tag = "preview"
)
```

e gerar para cada jogador algo equivalente a:

```text
Player             WR X
Projection         15.8
Sources               7
Coverage        ensemble

Sim Mean           15.1
Sim SD              9.0

P10                 4.8
P25                 8.7
P50                14.3
P75                20.6
P90                28.4
```

---

# 40. Critérios de aceite — Milestone 2

Para cada matchup ESPN:

```text
Home expected
Away expected

Home P10/P50/P90
Away P10/P50/P90

Home win probability
Away win probability
```

---

# 41. Critérios de aceite — Milestone 3

Para cada time:

```text
Current lineup expected points
Optimal lineup expected points

Current P(win)
Optimal P(win)

Recommended substitutions
```

---

# 42. Critérios de aceite — Milestone 4

Para o time escolhido:

```text
Top ADD/DROP candidates

delta expected points
delta P(win)
```

---

# 43. Critérios de aceite — Milestone 5

Para cada time da liga (ou apenas o time indicado, se `team_id` for passado):

```text
Top mutually useful 1×1 trades

my delta
their delta
trade score
```

`recommendation_rank` recomeça em 1 para cada `my_team_id`. O padrão do pipeline
(`trade_team_id = NULL`) roda para todos os times.

---

# 44. Ordem obrigatória de implementação

Não implementar todas as funções simultaneamente.

Seguir:

```text
PHASE 1
snapshot selection

PHASE 2
current consensus

PHASE 3
player Monte Carlo

PHASE 4
league state

PHASE 5
matchup simulation

PHASE 6
lineup optimizer

PHASE 7
roster evaluator

PHASE 8
FA recommendations

PHASE 9
trade recommendations

PHASE 10
decision_db persistence
```

Cada fase deve ser validada antes da seguinte.

---

# 45. Não implementar ainda

Manter fora do MVP:

```text
player correlation models
QB/WR stacking correlations
game-environment latent factors
weather
betting lines
Vegas totals
multi-week injury probabilities
complex Bayesian models
machine-learning source weighting
2×2 or larger trades
playoff probability
schedule simulation
```

Esses elementos podem ser introduzidos depois de termos um baseline calibrado e validado.

---

# 46. Definição conceitual final

A arquitetura deve manter uma separação rigorosa:

```text
FFA DB
=
o que as fontes projetam agora

ESPN DB
=
qual é o estado atual da liga

ANALYTICAL DB
=
como as projeções erraram historicamente

DECISION DB
=
o que o modelo concluiu e recomendou
```

Fluxo conceitual:

```text
CURRENT FFA CONSENSUS
          +
HISTORICAL CONSENSUS RESIDUALS
          │
          ▼
PLAYER PREDICTIVE DISTRIBUTION
          │
          ▼
MATCHUP SIMULATION
          │
          ▼
LINEUP / ROSTER VALUE
          │
       ┌──┴──┐
       ▼     ▼
      FA   TRADES
          │
          ▼
      DECISION DB
```

O princípio estatístico fundamental é:

$$
FantasyPoints_{sim}
=
CurrentConsensus
+
Sample(HistoricalConsensusResidual)
$$

e **não**:

$$
FantasyPoints_{sim}
\sim Normal(
CurrentConsensus,
SourceSD
)
$$

`source_sd` e `source_mad` são características de disagreement entre fontes. A variabilidade de performance é derivada empiricamente do `consensus_error_history`.

Essa distinção deve permanecer explícita em todo o código.

Eu começaria o Claude Code pedindo para implementar **somente até o Milestone 1** (`snapshot → consensus → player Monte Carlo → `player_forecasts`) e criar os testes correspondentes. Isso reduz bastante o risco de ele misturar otimização de roster com problemas ainda não resolvidos de calibração.
