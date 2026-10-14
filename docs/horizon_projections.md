# Projeções de horizonte (W0–W3) para trocas e waivers

Análise exploratória feita na semana 6 de 2026 (snapshot `posWaivers`). Nada foi
implementado ainda; este documento registra o que foi verificado, a estratégia
escolhida e as decisões já tomadas.

## Objetivo

Hoje trocas (`R/decision/trades.R`) e waivers (`R/decision/free_agents.R`) são
avaliados só pela semana atual. Isso distorce decisões que são, por natureza,
de várias semanas: um jogador em bye vale 0 nesta semana e por isso é excluído
à mão das recomendações (`bye_ffa`), e uma troca boa a partir da semana que vem
não aparece. A ideia é dar ao motor de decisão uma visão de 4 semanas.

## Decisões tomadas

- **Horizonte = W0..W3**: a semana atual (W0) mais as 3 seguintes (W1, W2, W3).
- **Filtro de ranking nas trocas (e waivers)**: três escopos selecionáveis no site:
  - **Semana atual**: só W0 (comportamento de hoje);
  - **Futuro**: W1..W3;
  - **Ambos**: W0..W3.

## O que foi verificado

### ffanalytics não serve para semanas futuras

Teste com `scrape_data(pos = "QB", season = 2026, week = 8)` contra `week = 6`:

| Fonte       | Resultado para week 8                                             |
|-------------|-------------------------------------------------------------------|
| CBS         | devolve a semana atual (valores idênticos; ffanalytics usou o cache da chamada da week 6) |
| FleaFlicker | idem                                                              |
| FanDuel     | devolve a semana atual (valores idênticos)                        |
| FFToday     | HTTP 403                                                          |
| FantasyPros | respeita a semana, mas devolve só 10 jogadores por posição        |

Ou seja, não existe consenso multi-fonte para semanas futuras. (O corte de 10
jogadores/posição do FantasyPros também aparece no snapshot normal da semana 6 e
merece investigação à parte.)

### A ESPN entrega projeção semanal futura

`espn_player_pool(client, week = N)` (endpoint `kona_player_info` com
`scoringPeriodId = N`) devolve, para N futuro, registros `stat_source_id = 1`,
`stat_split_type_id = 1`, `scoring_period_id = N`. As projeções são reais:
zeram na semana de bye e variam com o adversário.

```
             S6    S7    S8    S9   S10  bye
Josh Allen  25.1   0.0  23.9  20.0  22.6   7
McCaffrey   22.2  20.9   0.0  22.2  21.8   8
J. Taylor   18.9  14.9  14.5  20.6  20.3  13
```

Custo: uma chamada extra ao mesmo endpoint/cliente já usado por `importEspn()`
para cada semana futura (3 chamadas para W1..W3).

Nota: o filtro `filterStatsForTopScoringPeriodIds` com códigos de período futuro
não funcionou (devolveu só realizados das semanas passadas). O caminho que
funciona é o `scoringPeriodId` da query.

### A projeção ESPN de resto de temporada (ROS) já está guardada

Em `espn_db$espn_players_points`, `week = 0`:

- `stat_source_id = 1, stat_split_type_id = 0`: projeção **rest-of-season** (cai a
  cada semana: Josh Allen 346 → 301 → 294 → 285 → 269 das semanas 1 a 5);
- `stat_source_id = 1, stat_split_type_id = 2`: projeção de pré-temporada, congelada;
- `stat_source_id = 0, stat_split_type_id = 0`: pontos reais acumulados na temporada.

O site já usa o ROS na lente "season" do simulador de trocas
(`R/web/utils/season_stats.R`, `web/js/trade-sim.js`).

## Princípio de modelagem

**A semana-alvo é um atributo dentro do snapshot, nunca um snapshot próprio.**

O snapshot continua sendo `(season, week = semana atual, tag, timestamp)` e todo
`run_id` pertence à semana atual. As semanas W1..W3 são linhas *dentro* desse
snapshot, identificadas por uma semana-alvo (`target_week`) e um
`horizon = target_week - week` (0..3).

Duas coisas a **não** fazer:

1. **Não gravar semanas futuras em `ffa_proj_source_points` com `week = 8`.**
   `select_ffa_snapshot()` ignora a tag e pega `max(timestamp)` da semana; se o
   scrape da week 8 falhar lá na frente, ela usaria em silêncio a projeção velha
   feita na week 6.
2. **Não rodar o pipeline com `.week` futuro para "ver" o futuro.** Isso cria um
   run "Semana 8" no `decision_db` e no seletor de semanas do site, exatamente a
   confusão que se quer evitar.

## Desenho proposto

### 1. Dados (`importEspn()`): sem mudança de schema

Em `espn_players_points` a coluna `week` já é o período de pontuação do
registro, não a semana da execução (comentário em
`R/pipeline/data_pipeline_espn.R:202`); a identidade do snapshot é tag +
timestamp. Logo, basta `importEspn()` buscar `espn_player_pool(week = w + h)`
para h = 1..3 e anexar só as linhas `stat_source_id = 1, stat_split_type_id = 1,
week = w + h` com o mesmo tag/timestamp do snapshot. ~650 jogadores × 3 semanas
por snapshot.

A PK `(season, week, tag, timestamp, player_id, stat_source_id,
stat_split_type_id)` já comporta isso sem colisão (o snapshot da week 7 terá seu
próprio timestamp).

Consumidores atuais da tabela conferidos — nenhum é afetado:

- `R/decision/snapshot.R` — só `stat_source_id == 0` (realizados);
- `R/web/bundle/best_lineups.R` — só `stat_source_id == 0, split 1`;
- `R/web/utils/season_stats.R` — só `week == 0`.

### 2. Motor de decisão

- **W0**: inalterado — consenso FFA + bootstrap de resíduos históricos
  (`player_simulation.R`).
- **W1..W3**: projeção semanal ESPN, ligada por `espn_id` (que
  `current_players` já carrega), sem passar de novo pela ponte ESPN→FFA. Bye
  vira 0 naturalmente.
- **Valor de horizonte de um elenco** (a `evaluate_roster_ros()` já prevista na
  spec, §23): para cada semana-alvo, `optimize_lineup()` com `sim_mean`
  substituído pela projeção daquela semana; soma dos pontos esperados do lineup
  ótimo. Só médias, sem Monte Carlo — barato.
- **Probabilidade de vitória**: continua só para W0 (adversário e lineups
  futuros são desconhecidos).

#### Escopos de ranking (filtro Semana atual / Futuro / Ambos)

Cada candidato de troca/waiver passa a ter três deltas para o meu time (e três
para o parceiro, nas trocas):

| Escopo        | Semanas  | Coluna sugerida            |
|---------------|----------|----------------------------|
| Semana atual  | W0       | `my_delta_expected` (atual) |
| Futuro        | W1..W3   | `my_delta_future`           |
| Ambos         | W0..W3   | `my_delta_horizon`          |

Consequências:

- **Pool de candidatos**: hoje GIVE/RECEIVE são escolhidos por `sim_mean`
  (semana atual). Para o escopo Futuro/Ambos isso perderia trocas boas só a
  partir da semana que vem (ex.: receber alguém em bye agora). O pool deve ser
  a união dos melhores por W0 e por valor de horizonte.
- **Filtro de corte**: manter o candidato se o delta for positivo em *qualquer*
  escopo; o ranking e o `top_n` são feitos por escopo. Ou três colunas de rank
  (`rank_week`, `rank_future`, `rank_horizon`) na mesma linha, ou uma coluna
  `scope` com uma linha por escopo — a primeira mantém a PK atual
  `(run_id, my_team_id, other_team_id, give_player_id, receive_player_id)` e é a
  preferida.
- **Exclusão de bye**: hoje `bye_ffa` tira jogadores em bye das trocas/waivers
  porque, numa visão de uma semana, dar alguém em bye parece custo zero. Nos
  escopos Futuro/Ambos o bye é só um zero dentro da soma, então a exclusão deixa
  de ser necessária; manter apenas para o ranking do escopo Semana atual.

### 3. Persistência (`decision_db`): armadilha

`.update_decision_db()` (`R/decision/decision_db.R`) **apaga todo o histórico
de runs** quando o conjunto de tabelas muda ("starting fresh run history"), e o
seletor de semanas do site depende desse histórico. Portanto:

- preferir **colunas novas** nas tabelas existentes (`trade_recommendations`,
  `free_agent_recommendations`, `current_players`, `free_agents`) — a
  reconciliação de colunas (`.reconcile_dm_cols`) já trata isso; ou
- se uma tabela nova for necessária (ex.: `horizon_forecasts`: `run_id,
  espn_id, target_week, horizon, projection, is_bye`), antes corrigir
  `.update_decision_db()` para semear tabelas novas, como `updateDB()` já faz em
  `R/pipeline/data_pipeline_ffa.R`.

### 4. Site

Regras para não confundir o horizonte com snapshots de outras semanas:

- **Seletor de semana inalterado**: uma entrada por semana atual (run). O
  horizonte nunca gera entrada no seletor.
- **Rotulagem**: todo número futuro aparece como "S8 · visto da S6", com estilo
  atenuado e selo "ESPN" (fonte única); W0 continua com selo "consenso".
- **Trocas**: filtro de escopo `[Semana atual] [Futuro] [Ambos]` controlando o
  ranking da lista, e uma faixa W0..W3 por jogador com o bye marcado:

  ```
  Recebe: CMC    S6 22.2 │ S7 20.9 │ S8 BYE  │ S9 22.2    Σ 65.3
  Dá:     Allen  S6 25.1 │ S7 BYE  │ S8 23.9 │ S9 20.0    Σ 69.0
  Escopo: [Semana atual] [Futuro] [Ambos]
  ```

  No simulador de trocas (`web/js/trade-sim.js`), uma lente nova de horizonte
  ao lado de Semana / Temporada / Desempenho, na mesma unidade (pontos por
  semana), entrando nos pesos.
- **Waivers**: o mesmo filtro de escopo (streaming = Semana atual; segurar =
  Futuro/Ambos) e coluna com a faixa W0..W3.
- **Bundle**: mart novo `current/horizon_projections.parquet`
  (`run_id, player_id, target_week, horizon, projection, is_bye`), empilhado por
  run como os demais marts `current/`. Ao abrir uma semana antiga, mostra o
  horizonte como era visto naquela semana (dá para sobrepor o realizado depois).
  Validar em `R/web/validate_web_bundle.R`.

## Evoluções posteriores

- **Calibração de escala**: fator por jogador `consenso FFA ÷ ESPN` em W0,
  encolhido para 1 e limitado, aplicado a W1..W3 para alinhar a escala ESPN ao
  consenso.
- **Incerteza por horizonte**: não há histórico de projeção futura ESPN. Gravando
  a partir de agora (item 1), ao fim da temporada há resíduos reais por h = 1..3
  para dar distribuição (e probabilidade de vitória) às semanas futuras.
- **Fallback sem chamada extra**: ROS ÷ jogos restantes × máscara de bye ×
  multiplicador de adversário (`espn_pos_vs_opponent`) — menos preciso, só se a
  chamada por semana futura quebrar.

## Ordem sugerida

1. `importEspn()`: buscar e gravar W1..W3 em `espn_players_points`.
2. Motor: valor de horizonte por elenco + três deltas/ranks em trocas e waivers;
   remover exclusão de bye fora do escopo Semana atual; cuidar da persistência.
3. Web: mart `horizon_projections`, filtro de escopo, faixa W0..W3, lente nova.
4. Calibração de escala e de incerteza.
