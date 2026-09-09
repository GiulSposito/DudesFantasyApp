Sim. Pelo catálogo, você já tem quase toda a camada analítica necessária para um cockpit bastante sofisticado. O ponto mais importante é que **eu não faria um “dashboard que consulta RDS” nem colocaria Shiny como requisito inicial**. Faria um **data app static-first**: o pipeline R continua calculando tudo, gera um pequeno pacote de arquivos Parquet/JSON, e o browser faz apenas seleção, filtragem, drill-down e visualização.

Isso combina bem com o que você já tem: o `decision_db` já persiste forecasts probabilísticos, simulações dos matchups, avaliação de lineup, recomendações de lineup, free agents e trades; cada resultado é rastreável por `run_id`.  O `espn_db` fornece times, standings, roster, injuries, matchups e draft.  E o `analytical_db` já oferece histórico de projeção × realizado, erro por fonte e dispersão do consenso. 

No benchmark, eu juntaria três ideias: **FantasyPros**, que coloca matchup + Start/Sit + Waiver + Trade no dashboard principal; ([FantasyPros][1]) **Dynasty Daddy**, que enfatiza power rankings, simulação de temporada e efeito hipotético de trades; ([Dynasty Daddy][2]) e **ffwrapped**, que adiciona expected wins, playoff odds, roster strength e história da liga. ([ffwrapped][3]) A filosofia visual/social e compacta do Sleeper também é uma boa referência de UX. ([Centro de Suporte Sleeper][4])

Algumas referências visuais desses padrões:

![Image](https://support.fantasypros.com/hc/article_attachments/30283162643995)

![Image](https://images.openai.com/static-rsc-4/3t669jMCmXe25Q7bgYVMldGNIyvCsIRznpUbfqVU41QzD5gcvqWO8tvTkf3wagQ8ZeqxGQMOuMXSKUJHBiqxArj7bOrEytBPwDH8FFp_NznX_AbyeJCIbFKS6S0uIAsKJjwDlA1_na2eAZOrdaA54LT_7oCoKwVxYZIvSS1qtOTuavblaVj885_FihBePytO?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/QO-87pEE3dF2LwocLvS7EYxfBaWfrTsa8q3opEcxItPLkdUdkzyvZe8LxaZBr6ikeZrSEz-HUujsOT8QN5uPTokw_E3RYofqcAmzHaGs_7GmYyJWMEwcgVl27iFxn0kyCcoNdrLpqJbg0u5RaowNQaUSp8NXvk81A19YysJl_hSatDaFXW71B2BbhIrMuJge?purpose=fullsize)

# SPEC — Fantasy Football Analytical Cockpit

**Working name:** `Dudes Fantasy Cockpit`
**Tipo:** static analytical web application
**Objetivo:** transformar os resultados do pipeline de fantasy em uma interface que responda rapidamente às perguntas:

> **Como está minha semana? O que devo mudar? Quem devo adicionar? Quem posso trocar? Quão forte é meu time? Quem são os melhores jogadores disponíveis? Em que posso confiar nas projeções?**

---

## 1. Princípio de produto

O cockpit não deve funcionar como uma coleção de gráficos.

Ele deve funcionar como um **decision cockpit**.

A ordem mental deve ser:

**Situação → risco/oportunidade → recomendação → evidência → exploração.**

A home deve ser capaz de responder em menos de 20 segundos:

* quem estou enfrentando;
* minha chance de vitória;
* minha pontuação esperada;
* quanto posso melhorar meu lineup;
* quais mudanças devo fazer;
* melhor waiver disponível;
* melhor oportunidade de trade;
* quais jogadores estão causando maior risco;
* qual a qualidade das projeções que embasam essas decisões.

---

# 2. Arquitetura recomendada

## 2.1 Static-first

```text
                 ┌──────────────────────┐
                 │ APIs / FFA / ESPN    │
                 └──────────┬───────────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │   Pipeline R atual   │
                 │                      │
                 │ ffa_db               │
                 │ espn_db              │
                 │ analytical_db        │
                 │ decision_db          │
                 └──────────┬───────────┘
                            │
                    build_web_data.R
                            │
                            ▼
              ┌────────────────────────────┐
              │ web/data/                  │
              │                            │
              │ manifest.json              │
              │ league.parquet             │
              │ rosters.parquet            │
              │ forecasts.parquet          │
              │ matchups.parquet           │
              │ recommendations.parquet    │
              │ history.parquet            │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │     STATIC WEBSITE         │
              │                            │
              │ HTML / CSS / JS            │
              │ DuckDB-Wasm                │
              │ Plotly / ECharts           │
              └────────────────────────────┘

        GitHub Pages / Cloudflare Pages /
             nginx / localhost
```

**Nenhum banco, API ou runtime R é necessário em produção.**

Quarto pode publicar dashboards interativos como páginas estáticas sem servidor especial e suporta Plotly, htmlwidgets e Observable JS. ([Quarto][5]) DuckDB-Wasm roda totalmente dentro do browser e consulta Parquet local/remoto sem que os dados precisem ir para um servidor de banco. Ele inclusive consegue evitar ler partes desnecessárias do Parquet. ([DuckDB][6])

### Stack que eu usaria

| Camada                  | Tecnologia                            |
| ----------------------- | ------------------------------------- |
| Analytics               | R, mantendo pipeline atual            |
| Export                  | `arrow::write_parquet()` + `jsonlite` |
| Site                    | **Quarto Website/Dashboard**          |
| Client queries          | **DuckDB-Wasm**                       |
| Visualização principal  | **Plotly.js**                         |
| Visualizações especiais | ECharts opcional                      |
| Tabelas                 | DataTables/Tabulator                  |
| Styling                 | SCSS/CSS customizado                  |
| Hosting                 | Cloudflare Pages ou GitHub Pages      |
| Backend                 | **nenhum**                            |

Eu evitaria Shiny inicialmente. Quarto já pode ser estático; adicionar Shiny só se futuramente houver cálculos que realmente precisem ser executados no servidor. ([Quarto][5])

---

# 3. Não expor os `.rds` diretamente

O catálogo deixa claro que o armazenamento atual é centrado em objetos R/`dm`. 

Adicionar uma **Web Presentation Layer**:

```text
R/web/
├── build_web_bundle.R
├── build_current_state.R
├── build_player_view.R
├── build_league_view.R
└── validate_web_bundle.R

web/
├── _quarto.yml
├── index.qmd
├── matchup.qmd
├── lineup.qmd
├── waivers.qmd
├── trades.qmd
├── league.qmd
├── players.qmd
├── projections.qmd
├── draft.qmd
├── history.qmd
├── data-health.qmd
│
├── js/
├── css/
└── data/
    ├── manifest.json
    ├── current/
    └── history/
```

O browser recebe **views prontas para consumo**, não o modelo relacional cru.

---

# 4. Manifesto da execução

Arquivo pequeno obrigatório:

```json
{
  "season": 2026,
  "week": 1,
  "tag": "preview",
  "run_id": "2026-W01-preview-20260908T161947",
  "created_at": "...",
  "model_version": "player-mc-v2",
  "n_sim": 10000,
  "ffa_timestamp": "...",
  "espn_timestamp": "...",
  "my_team_id": 7
}
```

Isso aproveita exatamente os metadados já mantidos em `simulation_runs`. 

O header de todas as telas deve mostrar algo como:

**2026 · Week 1 · Preview · Model player-mc-v2 · atualizado há 37 min**

---

# 5. Shell global

Layout desktop:

```text
┌───────────────────────────────────────────────────────────────────────┐
│ DUDES   Week 1 ▼   My Team ▼     🔍 Player      Updated 07:28       │
├───────────────┬───────────────────────────────────────────────────────┤
│ OVERVIEW      │                                                       │
│ Matchup       │                                                       │
│ Lineup        │                                                       │
│ Waivers       │                  CONTENT                              │
│ Trades        │                                                       │
│ League        │                                                       │
│ Players       │                                                       │
│ Projections   │                                                       │
│ Draft         │                                                       │
│ History       │                                                       │
│ Data Health   │                                                       │
└───────────────┴───────────────────────────────────────────────────────┘
```

Filtros persistentes:

`Season | Week | Run | Fantasy Team | Position`

Seleções ficam em `localStorage` e/ou URL:

```text
/lineup/?season=2026&week=1&team=7
```

Isso permite compartilhar diretamente uma análise.

---

# 6. Tela 1 — Command Center

Esta deve ser a página mais importante.

## Hero

```text
┌──────────────────────────────────────────────────────────────┐
│ WEEK 1                                                      │
│                                                              │
│      YOUR TEAM                         OPPONENT               │
│        121.8                              116.3               │
│                                                              │
│           ████████████████████░░░░░                         │
│                    WIN 63%                                   │
│                                                              │
│   P10 101 ─────── P50 122 ─────── P90 143                  │
└──────────────────────────────────────────────────────────────┘
```

Os dados já existem em `matchup_simulations`: expected score, P10/P50/P90 e win probability para os dois lados. 

## KPIs

```text
WIN PROB.        EXPECTED       OPTIMAL        UPSIDE
   63%            121.8          127.4          +5.6

BEST WAIVER      BEST TRADE     BENCH VALUE    SOURCES
  +4.8 pts        +3.6 pts         54.3           7
```

### Bloco "What should I do?"

Ordenar ações por impacto:

```text
⚡ ACTION CENTER

1. START  Jordan Addison → bench Deebo Samuel
   +4.1 expected points
   +7.8pp win probability

2. ADD    Player X → drop Player Y
   +3.7 expected points
   +5.4pp win probability

3. TRADE  Player A → receive Player B
   You       +3.2 pts
   Partner   +0.9 pts
   Trade score 4.1
```

Esse bloco é praticamente uma projeção visual direta das três tabelas:

* `lineup_recommendations`
* `free_agent_recommendations`
* `trade_recommendations`

todas já existentes. 

---

# 7. Tela 2 — Matchup Center

Referência conceitual: scoreboard simples como Sleeper, mas com a camada probabilística do seu modelo.

## Cabeçalho

```text
YOUR TEAM                      OPPONENT
121.8 Expected               116.3 Expected
     63%  ███████████░░░  37%
```

## Visualização principal

**Uncertainty range chart**

```text
                    p10     p50     p90
My Team             ├━━━━━━━●━━━━━━━┤
Opponent               ├━━━━●━━━━━━━┤
```

É muito mais informativo do que mostrar apenas "121.8 × 116.3".

## Player Contribution

Waterfall/bar:

```text
QB    +21.4
RB1   +18.6
RB2   +14.2
WR1   +17.3
WR2   +11.9
TE     +8.7
FLEX  +15.0
DST    +7.3
K      +7.4
```

Cada barra deve permitir hover com:

```text
Player
Projection: 15.8
Simulation mean: 16.5
P10–P90: 8.2–25.1
P(>20): 34%
Sources: 7
Coverage: ensemble
```

`player_forecasts` já contém esses quantis, probabilidades de ultrapassar thresholds, dispersão e coverage class. 

## Bottom panel

**All league matchups**

```text
Team A  72% ███████░░ 28% Team B
Team C  51% █████░░░░ 49% Team D
Team E  18% ██░░░░░░░ 82% Team F
...
```

---

# 8. Tela 3 — Lineup Lab

Esta é a versão mais analítica do Start/Sit.

## Current × Optimal

```text
                 CURRENT      OPTIMAL        Δ

Expected          121.8        127.4        +5.6
P10                98.4        102.1        +3.7
Median            122.1        128.0        +5.9
P90               143.3        148.7        +5.4
Win Prob.          63.0%        70.8%        +7.8pp
```

Essas métricas estão explicitamente disponíveis em `lineup_evaluations`. 

## Roster board

Inspirado em depth chart:

```text
STARTERS
──────────────────────────────────────────────────────────
QB   Josh Allen       23.4    14.1 ━━━●━━━━ 33.7
RB   ...
RB
WR
WR
TE
FLEX
K
DST

BENCH
──────────────────────────────────────────────────────────
WR   Player X         16.2       ↑ START
RB   Player Y          9.7
...
```

Visualmente:

* starter = card principal;
* bench = card secundário;
* troca recomendada = ligação/arrow;
* OUT/IR = alerta;
* bye = estado especial;
* `ensemble/sparse/single` = indicador de confiança.

## Opportunity map

Scatter:

**X:** `sim_mean`
**Y:** `sim_sd`

Quadrantes:

```text
            HIGH UPSIDE / HIGH RISK
                    │
                    │
LOW VALUE ──────────┼──────── HIGH VALUE
                    │
                    │
             HIGH FLOOR
```

Excelente para visualizar FLEX/bench.

---

# 9. Tela 4 — Waiver Wire Center

O FantasyPros usa exatamente a lógica "quem adicionar + quem dropar + quanto o time melhora", que é um bom padrão. ([FantasyPros][7])

Seu pipeline já calculou algo mais interessante: **ganho esperado do time e ganho de probabilidade de vitória**, não simplesmente ranking do jogador. 

## Visualização principal

Scatter:

```text
              WIN PROBABILITY GAIN
                      ↑
                      │          ● Must Add
                ●     │     ●
                      │
──────────────────────┼────────────────→ EXPECTED POINTS GAIN
                      │
                      │
```

Cada ponto = uma operação ADD/DROP.

Tooltip:

```text
ADD: Player A
DROP: Player B

Expected:
123.3 → 128.1
+4.8 pts

Win probability:
61.7 → 68.4%
+6.7pp
```

## Recommendation table

| Rank | Add      | Drop     | Pos | Δ Points | Δ Win Prob |         |
| ---: | -------- | -------- | --- | -------: | ---------: | ------- |
|    1 | Player A | Player X | RB  |     +4.8 |     +6.7pp | Analyze |
|    2 | Player B | Player Y | WR  |     +3.9 |     +4.9pp | Analyze |

## Player comparison drawer

Ao clicar:

```text
                    DROP                 ADD
                    Player X             Player A

Projection             8.4                13.7
Simulation mean         8.1                14.2
P10                     2.1                 5.8
P50                     7.7                13.5
P90                    15.9                23.4
P(>15)                  11%                 43%
```

---

# 10. Tela 5 — Trade Center

Aqui há bastante espaço para diferenciação.

O Dynasty Daddy é uma boa referência porque combina fairness, impacto no roster e simulação da alteração no power ranking. ([Dynasty Daddy][8])

Seu decision engine já possui:

```text
my_delta_expected
their_delta_expected
my_delta_win_probability
fairness
trade_score
```

e restringe os candidatos a operações positivas para ambos os times. 

## Trade Opportunity Map

Este talvez seja o gráfico mais interessante do cockpit.

```text
         THEIR Δ EXPECTED
                 ↑

 win-win         │        win-win
 partner wins    │        ★ IDEAL
                 │
─────────────────┼──────────────────→ MY Δ EXPECTED
                 │
                 │
```

Cada bolha = trade possível.

Tamanho:

`trade_score`

Tooltip:

```text
YOU GIVE
Player X

YOU GET
Player Y

You:       +3.8 expected
Partner:   +1.2 expected
Win prob:  +4.3pp
Fairness:  -2.6
Trade score: 5.0
```

## Trade partner matrix

```text
                 BEST AVAILABLE TRADE

Team A      +4.8 ██████████████
Team B      +3.7 ███████████
Team C      +3.1 █████████
Team D      +2.2 ██████
...
```

Clique no time → lista de oportunidades.

## Fairness meter

```text
YOU WIN                FAIR                 THEY WIN
───────────────●──────────────────────────────────
```

Não deve substituir os números; apenas resumir.

### Warning obrigatório

Quando:

```text
partner_is_my_opponent == TRUE
```

mostrar:

> ⚠ Win probability may be optimistic because this manager is your current-week opponent.

Essa limitação está explicitamente documentada no catálogo. 

---

# 11. Tela 6 — League Analyzer

Aqui o sistema deixa de ser apenas "meu time" e vira cockpit da liga.

## Standings × Strength

Visualização:

```text
               ROSTER STRENGTH
                     ↑

     unlucky         │     dominant
                     │
        ●            │          ●
─────────────────────┼──────────────→ STANDINGS
                     │
     bad             │      lucky
```

Roster strength inicial:

```text
rank(optimal_expected)
```

Não criaria um score esotérico na primeira versão.

Mostrar lado a lado:

```text
Record Rank
Points For Rank
Projected Strength Rank
Optimal Lineup Rank
Bench Depth Rank
```

## Position Heatmap

```text
               QB      RB      WR      TE     FLEX
Team A        +1.2    +0.8    -1.1    +0.4    +0.3
Team B        -0.4    +2.1    +0.2    -1.4    +1.1
Team C        ...
```

Valores normalizados contra média da liga.

Resposta instantaneamente:

> Quem é forte/fraco em cada posição?

## Roster construction

Stacked bar por time:

```text
QB | RB | WR | TE | DST | Bench
```

Baseado em `sim_mean`.

## Matchup probability board

Grid de todos os sete confrontos da semana.

---

# 12. Schedule Luck / Expected Wins

Muito útil e relativamente barato de gerar.

Com matchups finalizados:

para cada semana:

1. pegar pontos do time;
2. comparar com os outros 13 scores;
3. calcular quantos times ele venceria;
4. converter para expected/all-play wins.

Exemplo:

```text
Actual record       4–1
All-play expected   2.9–2.1

Luck index          +1.1 wins
```

Scatter:

```text
Actual Wins
     ↑
     │         Lucky
     │       ●
─────┼────────────────→ Expected Wins
     │
     │ ●
     │ Unlucky
```

O conceito aparece como componente importante em analyzers modernos de liga, junto com power rankings e playoff odds. ([ffwrapped][3])

---

# 13. Tela 7 — Player Explorer

O catálogo já tem mais de 500 player forecasts por execução. 

Criar uma experiência próxima de terminal financeiro:

```text
PLAYER EXPLORER

Search: [________________]

ALL  QB  RB  WR  TE  K  DST

Player        Proj   Sim   P10   P50   P90   >20   Sources
──────────────────────────────────────────────────────────
Player A      19.2  20.1  10.4  19.7  31.4   48%      7
Player B      18.8  17.1   6.2  16.5  30.8   37%      3
...
```

## Player detail page

Hero:

```text
PLAYER A · WR · BUF

Simulation Mean        18.7
Projection             17.4
Historical Bias        +1.3

5%   10%    25%    50%    75%    90%   95%
─────┼───────┼══════●══════┼──────┼─────
```

### Current projection sources

As projeções por fonte existem em `ffa_proj_source_points`, enquanto o consenso mantém média/robust/weighted. 

Chart:

```text
FantasyPros    19.2 ●
ESPN           17.8 ●
CBS            16.4 ●
NFL            18.3 ●
NumberFire     20.1 ●

Consensus      18.4 ━━━━━
```

### Historical performance

Line chart:

```text
Week       Projection ─────
           Actual     ●────
```

---

# 14. Tela 8 — Projection Lab

Essa tela é uma vantagem competitiva grande em relação a dashboards tradicionais.

O `analytical_db` contém erro por fonte, posição e temporada — bias, MAE, RMSE e N — além do histórico do consenso. 

## Expert/Source Accuracy

Heatmap:

```text
             QB       RB       WR       TE
ESPN         5.2      4.9      5.7      4.3
CBS          5.5      4.2      5.3      4.8
NFL          ...
```

Toggle:

`MAE | RMSE | Bias`

Filter:

`Season`

## Accuracy trend

```text
RMSE
 ↑
 │ ESPN ─────────
 │ CBS  ──╲______
 │ NFL    ───────
 └────────────────→ Season
```

## Source bias

Diverging bars:

```text
underprojection ←── 0 ──→ overprojection

CBS        ━━━━━|
ESPN            |━━━
NFL        ━━|
```

## Consensus uncertainty

Scatter:

```text
source_sd × |actual - projection|
```

Isso permite investigar:

> quando as fontes discordam, o erro realmente aumenta?

Uma ótima validação empírica do próprio ensemble.

---

# 15. Coverage / Confidence

O catálogo já classifica:

```text
single     = 1 source
sparse     = 2–3
ensemble   = 4+
```



Use consistentemente:

```text
● HIGH     ensemble
● MEDIUM   sparse
● LOW      single
```

Não esconder incerteza.

Ela deve ser componente visual de primeira classe.

---

# 16. Tela 9 — Draft Review

O ESPN database possui o draft completo, com `overall_pick`, `round`, `round_pick`, `team_id` e `player_id`. 

Criar board:

```text
             TEAM 1   TEAM 2   TEAM 3    ... TEAM 14
Round 1      WR       RB       RB
Round 2      RB       WR       QB
Round 3      ...
```

Cor = posição.

Hover:

```text
Pick #28
Player
WR / BUF
Projected positional rank
Current season performance
```

## Draft retrospect

Quando houver dados suficientes:

```text
Draft pick value × realized points
```

e:

```text
Best Pick
Worst Pick
Best Late Round Pick
Best Team Draft
```

---

# 17. Tela 10 — History

Separaria dois tipos de histórico.

### Model history

Muito sólido porque o `analytical_db` cobre várias temporadas. Atualmente há projeções históricas entre 2020–2025, embora existam gaps específicos, inclusive 2021 praticamente só com week 1. 

Visualizações:

* MAE ao longo das temporadas;
* projection vs actual;
* positional accuracy;
* fonte mais precisa por ano;
* evolução da dispersão;
* maiores misses;
* boom/bust histórico.

### League history

Só habilitar quando a continuidade de identidade dos times/managers entre a antiga NFL Fantasy API e a atual ESPN for validada.

O catálogo **não garante essa identidade longitudinal**, portanto eu não assumiria que um `teamId` histórico corresponde automaticamente ao atual `team_id`.

---

# 18. Tela 11 — Data & Model Health

Muito valiosa para um cockpit analítico.

```text
DATA HEALTH

ESPN snapshot           ✓ 07:21
FFA projections         ✓ 06:58
Decision run            ✓ 07:24

Players forecast        561
Mapped starters         126 / 126
Coverage ensemble       55.8%
Coverage sparse         26.6%
Coverage single         17.6%

Model                   player-mc-v2
Monte Carlo draws       10,000
```

## Bridge diagnostics

Mostrar:

```text
exact ESPN id      84%
DST offset          2%
name + position    13%
manual override     1%
```

A ponte ESPN→FFA já registra `bridge_method` e o decision pipeline falha se um starter não tiver bridge/forecast. 

## Histórico de runs

```text
Run                         Tag       Players   Time
2026-W01-preview-0724       preview      561
2026-W01-preview-0612       preview      560
...
```

Permitir trocar entre runs.

Isso é muito interessante para ver como projeções e decisões mudaram ao longo da semana.

---

# 19. "What Changed?"

Eu colocaria esta funcionalidade já no MVP.

Comparar run atual com run anterior.

```text
SINCE LAST RUN

↑ Player A     +3.8 projected pts
↓ Player B     -4.1 projected pts

⚠ Player C     injury status changed
↑ Matchup      win probability 58% → 64%

NEW RECOMMENDATION
Start X over Y
```

É uma forma extremamente eficiente de transformar snapshots acumulados em informação útil.

Seu schema foi desenhado justamente para acumular runs em vez de sobrescrevê-los. 

---

# 20. Visualizações que eu priorizaria

| Problema             | Visual                                 |
| -------------------- | -------------------------------------- |
| Chance de vitória    | probability split bar                  |
| Score previsto       | P10/P50/P90 interval                   |
| Jogadores            | dot + uncertainty interval             |
| Start/Sit            | before/after roster board              |
| Waivers              | Δ expected × Δ win probability scatter |
| Trades               | my delta × their delta scatter         |
| Trade fairness       | diverging meter                        |
| League strength      | team × position heatmap                |
| Power ranking        | bump chart                             |
| Standings vs quality | quadrant scatter                       |
| Projection sources   | dot plot                               |
| Source accuracy      | heatmap                                |
| Projection error     | residual distribution                  |
| Draft                | snake draft grid                       |
| Change between runs  | slopegraph                             |
| Season standings     | bump chart                             |
| Injuries             | compact status cards                   |

Eu evitaria excesso de gauges, donuts e "speedometers". Probabilidade e comparação ficam melhores em barras, intervalos e slopes.

---

# 21. Duas novas tabelas que valem muito a pena

Embora os 10 mil draws não sejam persistidos por design,  isso impede algumas visualizações mais sofisticadas.

Não salvaria os draws.

Salvaria **histogramas agregados**.

### `matchup_distribution_bins`

```text
run_id
matchup_id
team_id
bin_min
bin_max
probability
```

Com 40 bins:

```text
14 teams × 40 = 560 linhas/run
```

Praticamente nada.

Isso permite visualizar:

```text
            YOUR TEAM
            █
          ████
        ███████
──────██████████────────────────
               ███████
                 ████
                  █
               OPPONENT
```

sem salvar 140 mil draws.

### `player_distribution_bins`

Somente para jogadores rosterados / top-N:

```text
run_id
ffa_id
bin_min
bin_max
probability
```

Permite violins/densidades reais.

---

# 22. Outra extensão altamente recomendada: Season Simulator

É a principal lacuna funcional em relação aos melhores benchmarks.

Dynasty Daddy simula temporadas inteiras para calcular probabilidades de playoffs e campeonato. ([Dynasty Daddy][2])

Adicionar posteriormente:

```text
season_simulations

run_id
team_id

expected_wins
p10_wins
p50_wins
p90_wins

playoff_probability
bye_probability
championship_probability

seed_1_probability
seed_2_probability
...
```

Então surge uma tela:

```text
PLAYOFF RACE

Team             Playoffs    Bye      Title
Team A              91%      43%       22%
Team B              78%      24%       15%
Team C              64%       9%       10%
...
```

Isso seria **M6** natural para o decision engine.

---

# 23. Capacidade atual × feature

| Feature                               | Hoje                     |
| ------------------------------------- | ------------------------ |
| Player forecast probabilístico        | ✅ direto                 |
| Weekly matchup simulation             | ✅ direto                 |
| Win probability                       | ✅ direto                 |
| Current vs optimal lineup             | ✅ direto                 |
| Start/Sit recommendations             | ✅ direto                 |
| Waiver add/drop                       | ✅ direto                 |
| Trade recommendations                 | ✅ direto                 |
| Trade fairness                        | ✅ direto                 |
| Player uncertainty                    | ✅ direto                 |
| Projection-source analysis            | ✅ direto                 |
| Historical source accuracy            | ✅ direto                 |
| Draft board                           | ✅ direto                 |
| League standings                      | ✅ direto                 |
| Positional team strengths             | 🟡 derivado              |
| Power rankings                        | 🟡 derivado              |
| All-play/expected wins                | 🟡 derivado              |
| Schedule luck                         | 🟡 derivado              |
| What changed since last run           | 🟡 derivado              |
| Matchup densities                     | 🟡 pequeno novo artifact |
| Season/playoff simulation             | 🔵 novo milestone        |
| Arbitrary interactive trade simulator | 🔵 novo milestone        |
| Arbitrary add/drop simulator          | 🔵 novo milestone        |
| News                                  | ❌ fonte ausente          |
| Weather                               | ❌ fonte ausente          |
| True live scoring                     | ❌ requer refresh/rebuild |

---

# 24. Static data bundle

Eu criaria algo assim:

```text
web/data/
└── 2026/
    ├── manifest.json
    │
    ├── dimensions/
    │   ├── players.parquet
    │   └── teams.parquet
    │
    ├── current/
    │   ├── standings.parquet
    │   ├── rosters.parquet
    │   ├── matchups.parquet
    │   ├── forecasts.parquet
    │   ├── lineup.parquet
    │   ├── lineup_recommendations.parquet
    │   ├── free_agents.parquet
    │   ├── waiver_recommendations.parquet
    │   └── trade_recommendations.parquet
    │
    ├── projections/
    │   ├── sources.parquet
    │   └── source_accuracy.parquet
    │
    ├── history/
    │   ├── player_points.parquet
    │   └── projection_errors.parquet
    │
    └── draft/
        └── draft.parquet
```

---

# 25. Preferir "presentation marts"

Não obrigaria o frontend a conhecer toda a ontologia do `dm`.

Por exemplo, `rosters.parquet` deveria vir pronto:

```text
season
week
team_id
team_name

player_id
ffa_id
player_name
position
nfl_team

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
prob_gt_25

n_sources
coverage_class

is_optimal_starter
```

Assim o frontend não precisa reconstruir cinco joins.

**R continua sendo a camada semântica.
JS é apenas apresentação.**

---

# 26. Performance

Os volumes são muito pequenos para DuckDB-Wasm.

Por exemplo, o catálogo fala de aproximadamente 561 player forecasts, 7 matchups e 14 lineup evaluations por run.  Mesmo o histórico analítico tem ordens de grandeza de dezenas/centenas de milhares de linhas, não dezenas de milhões. 

DuckDB-Wasm é adequado para esse tipo de uso e roda integralmente no browser, embora tenha limitações de memória e threading que seriam relevantes para datasets muito maiores. ([DuckDB][6])

Portanto não existe justificativa, neste momento, para:

* PostgreSQL;
* API REST;
* container em produção;
* Shiny Server;
* Redis;
* serviço Node;
* autenticação de API;
* scheduler web.

---

# 27. Deploy mínimo

Pipeline:

```text
Rscript R/pipeline/data_pipeline_espn.R
        ↓
Rscript R/decision/decision_pipeline.R
        ↓
Rscript R/web/build_web_bundle.R
        ↓
quarto render web/
        ↓
_site/
```

Publicação:

```text
_site/
```

pode ir diretamente para:

```text
GitHub Pages
Cloudflare Pages
Netlify
S3 static hosting
nginx
```

---

# 28. Modo completamente local

Também suportaria:

```bash
quarto preview web
```

ou qualquer static HTTP server.

Assim você pode ter:

```text
localhost:8000
```

com toda a aplicação, sem mandar dados da liga para nenhum serviço.

DuckDB-Wasm roda no próprio browser e não precisa enviar as queries nem os dados para um servidor. ([DuckDB][6])

---

# 29. Segurança

Há uma consequência importante da arquitetura static-first:

> **Tudo que estiver em `/data/*.parquet` pode ser baixado por quem tiver acesso ao site.**

Portanto:

### site privado/local

Pode conter nomes dos donos/times.

### site público

Criar opção:

```r
build_web_bundle(
    privacy = "public"
)
```

removendo:

```text
member real names
owner ids
internal identifiers
```

Não colocar credenciais ESPN nem tokens no frontend em hipótese alguma.

---

# 30. Design direction

Eu adotaria um look:

**Sleeper × Bloomberg terminal × modern sports broadcast**

Características:

* dark-first;
* alta densidade de informação;
* cards com pouco chrome;
* typography forte para score;
* números tabulares;
* posição do jogador codificada visualmente;
* probabilidades sempre acompanhadas de intervalos;
* mínimo de texto decorativo;
* micro-sparklines;
* hover rico;
* transições rápidas;
* sticky headers;
* painel lateral de player detail;
* mobile com bottom navigation.

Não copiaria a interface do Sleeper; usaria apenas o padrão visual de **sports app moderno, escuro, compacto e orientado a card**.

---

# 31. Home ideal — wireframe

```text
┌──────────────────────────────────────────────────────────────────────┐
│ DUDES                           WEEK 1                UPDATED 07:24  │
├──────────┬───────────────────────────────────────────────────────────┤
│          │  MY TEAM                    OPPONENT                     │
│ OVERVIEW │      121.8            63%       116.3                    │
│ MATCHUP  │  P10 98 ━━━ 122 ━━━ 143    P10 95 ━ 115 ━ 139         │
│ LINEUP   ├──────────────┬──────────────┬──────────────┬─────────────┤
│ WAIVERS  │ OPTIMAL      │ LINEUP EDGE  │ BEST WAIVER  │ BEST TRADE  │
│ TRADES   │   127.4      │    +5.6      │    +4.8      │    +3.6     │
│ LEAGUE   ├─────────────────────────────┴──────────────┴─────────────┤
│ PLAYERS  │                                                         │
│ MODELS   │  ACTION CENTER                 WEEK MATCHUPS             │
│ DRAFT    │                                                         │
│ HISTORY  │  ↑ START Player A              A ███████░ B             │
│          │    bench Player B              C █████░░░ D             │
│          │    +4.1 pts                    E ███░░░░░ F             │
│          │                                                         │
│          │  + ADD Player X                                           │
│          │    drop Player Y                                         │
│          │    +3.7 pts                                              │
│          ├─────────────────────────────┬────────────────────────────┤
│          │ MY ROSTER                  │ LEAGUE STRENGTH            │
│          │ QB ███████████             │ Team A ████████████        │
│          │ RB █████████               │ Team B ███████████         │
│          │ WR ████████████            │ MyTeam ██████████         │
│          │ TE ███████                 │ ...                        │
└──────────┴─────────────────────────────┴────────────────────────────┘
```

---

# 32. MVP

Eu não começaria implementando as onze telas inteiras.

### MVP 1

```text
1. Command Center
2. Matchup Center
3. Lineup Lab
4. Waiver Center
5. Trade Center
6. League Analyzer
7. Player Explorer
```

Com:

```text
manifest
run selector
week selector
team selector
player search
responsive layout
static Parquet/JSON bundle
```

Isso já aproveita praticamente todo o `decision_db`.

### MVP 1.1

Adicionar:

```text
What Changed?
Projection Lab
Draft Review
Data Health
```

### MVP 2

Adicionar ao pipeline:

```text
matchup_distribution_bins
season_simulations
playoff probabilities
```

---

# 33. Ordem de construção

Eu faria exatamente nesta sequência:

```text
M0  Web export layer
    ↓
M1  Global shell + player components
    ↓
M2  Command Center
    ↓
M3  Matchup + Lineup
    ↓
M4  Waiver + Trade
    ↓
M5  League Analyzer
    ↓
M6  Player Explorer
    ↓
M7  Projection Lab
    ↓
M8  What Changed
    ↓
M9  Season Simulator
```

O motivo é importante: **o verdadeiro primeiro produto não é o frontend; é o `web_bundle` estável**.

Depois que o contrato dos dados estiver bem resolvido, cada nova tela vira predominantemente trabalho de visualização.

---

# 34. Critérios de aceite

O cockpit MVP só está pronto quando:

1. É possível renderizar o site sem R, Python ou Node no servidor.
2. Toda informação analítica pode ser rastreada para `run_id`.
3. O usuário consegue trocar semana/time sem reload completo.
4. O matchup mostra expected score + uncertainty + win probability.
5. Current lineup e optimal lineup podem ser comparados visualmente.
6. Recomendações de lineup mostram impacto esperado.
7. Waivers mostram `ADD → DROP → Δexpected → ΔwinProbability`.
8. Trades mostram impacto para **os dois times**.
9. Qualquer jogador pode ser pesquisado.
10. Projeção sempre diferencia point estimate de uncertainty.
11. Coverage (`single/sparse/ensemble`) é visível.
12. Site funciona em desktop e mobile.
13. Site funciona totalmente com arquivos estáticos.
14. Nenhuma credencial/API key aparece no bundle.
15. Ausência ou desatualização de dados aparece explicitamente.

---

## Minha recomendação final de arquitetura

Eu seguiria com:

```text
R pipeline existente
        +
R/web/build_web_bundle.R
        ↓
Parquet + JSON
        ↓
Quarto static website
        +
custom CSS/JS
        +
DuckDB-Wasm
        +
Plotly
```

Esse desenho fica **muito menor do que uma arquitetura tradicional de analytics web**, mas não sacrifica praticamente nada na experiência. Quarto foi explicitamente desenhado para dashboards estáticos interativos, ([Quarto][5]) enquanto DuckDB-Wasm torna Parquet uma espécie de **database serverless do browser**. ([DuckDB][6])

E há um detalhe particularmente bom no seu caso: **o decision engine já fez a parte computacionalmente cara**. O frontend não precisa ser inteligente. Ele precisa ser excelente em **explicar visualmente o que o engine descobriu**.

Eu chamaria a home de **Command Center**, não de Dashboard. O diferencial do produto deveria ser: *não mostrar apenas estatísticas de fantasy, mas mostrar probabilidades, incerteza, consequências e a próxima melhor decisão*.

[1]: https://support.fantasypros.com/hc/en-us/articles/360018746693-What-is-the-My-Playbook-Dashboard-NFL?utm_source=chatgpt.com "What is the My Playbook Dashboard? (NFL) – FantasyPros"
[2]: https://staging.dynasty-daddy.com/?utm_source=chatgpt.com "Dynasty Daddy - Fantasy Football Tools and Rankings"
[3]: https://ffwrapped.com/?utm_source=chatgpt.com "Fantasy Football Team & League Analyzer | ffwrapped"
[4]: https://support.sleeper.com/en/articles/1876010-intro-to-sleeper-fantasy-football?utm_source=chatgpt.com "Intro to Sleeper Fantasy Football | Sleeper Support Center"
[5]: https://quarto.org/docs/dashboards/?utm_source=chatgpt.com "Quarto Dashboards – Quarto"
[6]: https://duckdb.org/docs/current/clients/wasm/overview?utm_source=chatgpt.com "DuckDB Wasm Client – DuckDB"
[7]: https://support.fantasypros.com/hc/en-us/articles/22745637384987-What-is-Waiver-Central?utm_source=chatgpt.com "What is Waiver Central? – FantasyPros"
[8]: https://www.dynasty-daddy.com/help/trade-calculator?utm_source=chatgpt.com "Dynasty Daddy - Fantasy Football Tools and Rankings"
