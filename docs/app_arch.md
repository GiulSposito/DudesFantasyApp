# Fantasy Football Analytical Cockpit

## Mini Architecture Spec

### 1. Objetivo

Construir um **cockpit analítico web para Fantasy Football**, orientado a decisão, capaz de apresentar:

* situação da rodada;
* probabilidade de vitória;
* projeções probabilísticas de jogadores;
* matchup simulations;
* avaliação e otimização de lineup;
* recomendações de start/sit;
* recomendações de waiver/add-drop;
* recomendações de trades;
* análise de força dos times;
* exploração de jogadores;
* qualidade e incerteza das projeções;
* histórico das execuções do decision engine.

O sistema deve privilegiar **infraestrutura mínima**, preferencialmente funcionando como **website estático**, sem banco de dados ou backend permanente.

---

# 2. Princípios arquiteturais

1. **R permanece como Analytics Engine.**
2. O browser não executa regras complexas de negócio nem simulações.
3. O frontend consome **artefatos analíticos já processados**.
4. Os `.rds` e objetos `dm` continuam sendo a camada operacional interna.
5. Uma nova **Web Presentation Layer** converte os dados em Parquet/JSON.
6. O website deve poder ser hospedado em GitHub Pages, Cloudflare Pages, Netlify, S3 ou servidor HTTP simples.
7. Toda informação de decisão deve ser rastreável ao `run_id` do decision engine.
8. O frontend deve tratar **incerteza e distribuição**, e não apenas projeções pontuais.

O `decision_db` já fornece a maior parte da camada de decisão necessária: forecasts probabilísticos, matchup simulations, lineup evaluations, lineup recommendations, free-agent recommendations e trade recommendations.

---

# 3. Arquitetura lógica

```text
┌───────────────────────────────────────────────┐
│                DATA SOURCES                   │
│                                               │
│ ESPN Fantasy · FFA · NFL · Historical Data   │
└───────────────────────┬───────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────┐
│              ANALYTICS LAYER                  │
│                        R                      │
│                                               │
│ ffa_db                                        │
│ espn_db                                       │
│ analytical_db                                 │
│ decision_db                                   │
│                                               │
│ projections                                   │
│ historical errors                             │
│ Monte Carlo                                   │
│ lineup optimization                           │
│ waivers                                       │
│ trades                                        │
└───────────────────────┬───────────────────────┘
                        │
                build_web_bundle.R
                        │
                        ▼
┌───────────────────────────────────────────────┐
│          WEB PRESENTATION DATA                │
│                                               │
│ manifest.json                                 │
│ dimensions/*.parquet                          │
│ current/*.parquet                             │
│ history/*.parquet                             │
│ projections/*.parquet                         │
└───────────────────────┬───────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────┐
│                STATIC WEB APP                 │
│                                               │
│ Quarto                                        │
│ JavaScript                                    │
│ DuckDB-Wasm                                   │
│ Plotly                                        │
│ CSS/SCSS                                      │
└───────────────────────────────────────────────┘
```

---

# 4. Componentes

## 4.1 Analytics Layer

Continua sendo implementada em R.

Principais bases:

```text
ffa_db
    projeções individuais e consenso

espn_db
    liga, times, rosters, standings,
    jogadores, injuries, matchups e draft

analytical_db
    projeção × realizado
    histórico de erros
    qualidade das fontes

decision_db
    resultados do decision engine
```

O `espn_db` contém liga, membros, times, roster slots, jogadores, standings, rosters, matchups e draft.

O `analytical_db` contém projeções históricas, pontos realizados, erros por fonte e histórico do consenso.

---

# 5. Web Presentation Layer

Adicionar:

```text
R/web/
├── build_web_bundle.R
├── build_dimensions.R
├── build_current_state.R
├── build_history.R
├── build_projection_views.R
└── validate_web_bundle.R
```

Responsabilidades:

```text
RDS / dm
   ↓
joins
   ↓
normalização
   ↓
enriquecimento
   ↓
presentation marts
   ↓
Parquet / JSON
```

O frontend **não deve reconstruir o modelo relacional original**.

Os arquivos publicados devem representar diretamente conceitos usados pelas telas.

Exemplo:

```text
rosters.parquet

season
week
run_id

team_id
team_name

player_id
ffa_id
player_name
position

lineup_slot
is_starter
is_bench
is_ir
injury_status

projection
sim_mean
sim_sd

p10
p25
p50
p75
p90

prob_gt_10
prob_gt_15
prob_gt_20

coverage_class
n_sources

is_optimal_starter
```

---

# 6. Estrutura do bundle

```text
web/data/

manifest.json

dimensions/
├── teams.parquet
├── players.parquet
└── roster_slots.parquet

current/
├── standings.parquet
├── rosters.parquet
├── forecasts.parquet
├── matchups.parquet
├── lineup_evaluations.parquet
├── lineup_recommendations.parquet
├── free_agents.parquet
├── waiver_recommendations.parquet
└── trade_recommendations.parquet

projections/
├── source_projections.parquet
└── source_accuracy.parquet

history/
├── player_points.parquet
├── consensus_history.parquet
└── projection_errors.parquet

draft/
└── draft.parquet
```

---

# 7. Manifest

Cada build gera:

```json
{
  "season": 2026,
  "week": 1,
  "tag": "preview",
  "run_id": "2026-W01-preview-20260908T161947",
  "model_version": "player-mc-v2",
  "created_at": "...",
  "ffa_timestamp": "...",
  "espn_timestamp": "...",
  "n_sim": 10000
}
```

Esses metadados já existem em `simulation_runs`.

O `run_id` é a chave de rastreabilidade entre:

```text
dados
→ modelo
→ recomendação
→ interface
```

---

# 8. Frontend

Stack preferencial:

```text
Quarto
   │
   ├── HTML/CSS
   ├── JavaScript
   ├── Plotly.js
   └── DuckDB-Wasm
```

Responsabilidades do frontend:

* carregar datasets;
* aplicar filtros;
* realizar queries simples;
* controlar navegação;
* atualizar visualizações;
* comparar jogadores;
* fazer drill-down;
* trocar week/run/team;
* renderizar gráficos e tabelas.

Não são responsabilidades do frontend:

* executar Monte Carlo;
* otimizar lineup;
* calcular recomendações;
* reconstruir projeções;
* acessar ESPN;
* acessar APIs externas.

---

# 9. Navegação principal

```text
Command Center

Matchup
Lineup
Waivers
Trades

League
Players
Projections

Draft
History
Data Health
```

### Command Center

Funciona como landing page e sintetiza:

```text
Current matchup

Expected Score
Win Probability
P10 / P50 / P90

Optimal Lineup Gain
Best Waiver
Best Trade

Action Center
League Matchups
Roster Strength
```

---

# 10. Modelo de interação

Filtros globais:

```text
Season
Week
Run
Team
Position
```

Estado preferencialmente persistido em URL:

```text
/?season=2026
 &week=1
 &run=latest
 &team=7
```

e opcionalmente em `localStorage`.

Isso permite:

* bookmark;
* compartilhamento de análise;
* navegação consistente entre telas.

---

# 11. Consulta de dados no browser

Usar DuckDB-Wasm para consultas sobre Parquet.

Exemplo conceitual:

```sql
SELECT *
FROM forecasts
WHERE
    run_id = $run
    AND pos = 'WR'
ORDER BY sim_mean DESC
```

Portanto:

```text
Parquet
   ↓
DuckDB-Wasm
   ↓
dataframe JS
   ↓
Plotly / Table
```

Evitar transformar o frontend em uma segunda camada analítica.

---

# 12. Atualização

Pipeline de publicação:

```text
data pipeline
      ↓
decision pipeline
      ↓
build_web_bundle.R
      ↓
quarto render
      ↓
_site/
      ↓
static hosting
```

Exemplo:

```bash
Rscript R/pipeline/data_pipeline_espn.R
Rscript R/decision/decision_pipeline.R
Rscript R/web/build_web_bundle.R

quarto render web/
```

Nenhum serviço precisa permanecer executando após o build.

---

# 13. Modelo de deploy

## Desenvolvimento

```text
localhost
+
quarto preview
```

## Produção

```text
_site/
   ↓
GitHub Pages
```

ou:

```text
Cloudflare Pages
Netlify
S3
nginx
```

Arquitetura inicial:

```text
Database       NONE
REST API       NONE
Application    NONE
R Server       NONE
Node Server    NONE
Cache Server   NONE
```

---

# 14. Extensões analíticas

Algumas visualizações podem exigir pequenos novos marts.

### Matchup distributions

Não persistir os 10.000 draws.

O próprio catálogo documenta que os draws individuais não são armazenados pelo decision engine.

Em vez disso:

```text
matchup_distribution_bins

run_id
matchup_id
team_id
bin_min
bin_max
probability
```

Permite desenhar densidades/histogramas com poucas centenas de linhas.

---

# 15. Evolução futura

Arquitetura deve suportar um novo módulo:

```text
Season Simulator
```

Produzindo:

```text
team_id
expected_wins

p10_wins
p50_wins
p90_wins

playoff_probability
bye_probability
championship_probability
```

Esse módulo permanece no Analytics Layer em R.

O frontend apenas consome seus resultados.

---

# 16. Data Quality

O frontend deve tornar explícitos problemas de qualidade.

Exibir:

```text
last ESPN snapshot
last FFA snapshot
last simulation run

player mapping coverage
forecast coverage
source coverage

single / sparse / ensemble
```

A classificação de coverage já existe no histórico e no forecast probabilístico.

A ponte ESPN → FFA também já possui múltiplas estratégias e `bridge_method`.

---

# 17. Segurança

Arquitetura static-first implica:

```text
qualquer dado publicado
=
potencialmente acessível ao cliente
```

Nunca publicar:

```text
API keys
cookies ESPN
credentials
tokens
raw authenticated payloads
```

Opcionalmente suportar:

```r
build_web_bundle(
  privacy = "private"
)

build_web_bundle(
  privacy = "public"
)
```

O modo público remove nomes reais e identificadores desnecessários.

---

# 18. Decisão arquitetural central

A separação fundamental é:

```text
               COMPLEXIDADE

                    R
                    │
                    │
              analytics
              simulation
              optimization
              decisions
                    │
                    ▼
            presentation marts
                    │
                    ▼
               browser
                    │
              visualization
              interaction
              filtering
```

Ou, de forma resumida:

> **R pensa; Parquet transporta; DuckDB seleciona; JavaScript apresenta.**

O frontend deve permanecer deliberadamente simples.

---

# 19. MVP arquitetural

Para a primeira implementação são necessários apenas quatro blocos:

```text
1. build_web_bundle.R

2. Parquet/JSON presentation marts

3. Quarto static application

4. Plotly + DuckDB-Wasm
```

Primeiras páginas:

```text
Command Center
Matchup
Lineup
Waivers
Trades
League
Players
```

O schema atual já fornece diretamente os elementos centrais dessas páginas: forecasts, simulações de matchup, avaliação e recomendação de lineup, add/drop e trades.

---

# 20. Architectural North Star

A arquitetura deve preservar esta propriedade:

```text
git clone
+
dados gerados pelo pipeline
+
build
=
aplicação completa
```

Sem provisionamento de infraestrutura.

O cockpit é essencialmente:

> **uma aplicação analítica pré-computada, distribuída como website estático interativo.**

Isso mantém a infraestrutura mínima, reduz acoplamento entre análise e UI e deixa o pipeline R como única fonte de verdade para toda lógica de Fantasy Football.
