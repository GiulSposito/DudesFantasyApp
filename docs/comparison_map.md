# Mapa de comparação de jogadores (projeção × incerteza × realizado)

Análise exploratória feita na semana 6 de 2026. Este documento registra a
ideia, o que foi verificado nos dados e o desenho proposto. Relaciona-se com
[`horizon_projections.md`](horizon_projections.md) (lente "Próx. 4").

## Status: implementado (itens 1–3 da ordem sugerida)

- **Mart** `history/player_weeks.parquet` (contrato 26.4,
  `R/web/bundle/history.R::build_player_weeks()`): por jogador × semana fechada
  da temporada, a **última previsão feita antes do jogo travar** (as runs por
  semana que o bundle guarda são pós-jogo, com P10 = P90 = realizado, então não
  servem) + o realizado do snapshot ESPN mais novo da semana.
- **Lógica** em `web/js/compare.js` (pura, `tests/web/compare.check.mjs`);
  bloco em `web/js/compare-map.js`; gráficos `compareMap()` / `weeklyBands()`
  em `web/js/charts.js`.
- **Lineup**: o scatter média × desvio saiu; entrou o Mapa de comparação do
  elenco, com chips de slot e **[Todos]** (sem linha "a superar").
- **Waivers**: Mapa de comparação (slot inicial = FLEX, lente inicial
  `Próx. 4` quando há horizonte), elegíveis ao slot + 10 melhores FA; o add #1
  do escopo atual ganha o anel ciano.
- **Gaveta**: comparação por slot (time do cabeçalho + 3 melhores FA, linha "a
  superar") e bloco "Realizado × projetado" (faixa semanal, viés, taxa dentro
  de P10–P90, acima do P90 / abaixo do P10).

Decisões tomadas na implementação:

- Lente **Semana** = barras P10–P90 (forest), não scatter; `Próx. 4` e
  `Realizado` são scatters com a diagonal y = x.
- **"Titular" = lineup ótimo** (`is_optimal_starter` / `optimal_slot`), o mesmo
  que define a linha "a superar"; a linha fica fixa no lineup ótimo da semana
  atual em todas as lentes.
- Na lente Realizado os FA entram pelo total de pontos reais (um jogo isolado
  não passa à frente de um titular constante).
- **Volatilidade por jogador (item 4) não foi feita.**

Primeira leitura do mart (S1–S5/2026): ~70% dos realizados caem dentro de
P10–P90 (esperado ≈ 80%), com ~23% abaixo do P10 e ~7% acima do P90 — a
simulação está otimista na cauda de baixo.

## A ideia original

Ao escolher um substituto (waiver) ou montar o lineup, ver um scatterplot com a
pontuação projetada num eixo e a incerteza dessa projeção no outro, destacando o
jogador analisado frente às alternativas (titulares × banco, elenco × free
agents). Variações pedidas: o mesmo gráfico com pontos realizados e sua
variação, e com a projeção de 4 semanas (W0..W3).

## Verificação: na projeção, o desvio é quase função da média

No `web/data/current/forecasts.parquet` da semana 6 (jogadores não realizados,
`sim_mean > 3`), regressão `sim_sd ~ sim_mean` por posição:

| Posição | n   | cor(média, sd) | R²   |
|---------|-----|----------------|------|
| QB      | 36  | 0,93           | 0,86 |
| RB      | 69  | 0,90           | 0,81 |
| WR      | 131 | 0,92           | 0,84 |
| TE      | 78  | 0,92           | 0,84 |
| DST     | 28  | 0,90           | 0,81 |
| K       | 29  | 0,50           | 0,25 |

Motivo: `get_residual_pool()` (`R/decision/player_simulation.R`) sorteia
resíduos históricos escolhidos por **posição + faixa de projeção** (+ classe de
cobertura), não por jogador. Logo a incerteza projetada é "incerteza do balde",
não do jogador: um scatter média × desvio vira uma diagonal e o eixo y repete o
eixo x.

Esse gráfico já existe: é o "Mapa de oportunidade: valor x risco" da página
Lineup (`opportunityScatter()` em `web/js/charts.js`).

## É o jeito certo de comparar jogadores?

Em parte.

- **Comparar contra as alternativas reais está certo**: o titular que o jogador
  substituiria, o banco e os melhores free agents.
- **Um scatter só se justifica quando os dois eixos são independentes.** Dois
  cruzamentos respondem perguntas de decisão:
  1. **Agora × depois** — x = projeção W0, y = média de W1..W3. Quadrantes:
     *titular firme* (alto/alto), *streaming* (alto agora, baixo depois),
     *stash* (baixo agora por bye/lesão, alto depois), *descartável*
     (baixo/baixo). Diagonal = jogador estável. É o gráfico de waivers e trocas.
  2. **Projetado × realizado** — x = projeção média por semana na temporada,
     y = pontos realizados por jogo. Acima da diagonal = entregando mais que o
     projetado. Tamanho do ponto = nº de jogos (amostra pequena).
- **Para escolher entre poucos candidatos** (start/sit, 2–6 jogadores), uma
  lista de barras P10–P90 com a mediana marcada lê melhor que um scatter. A
  gaveta do jogador já tem esse formato (`comparison()` em
  `web/js/player-drawer.js`).
- **A incerteza pesa pouco no start/sit.** Ela só importa quando a partida está
  desequilibrada: azarão quer teto (P90), favorito quer piso (P10). Fora disso a
  média decide, e é isso que o otimizador já maximiza.

### Se quisermos um eixo de incerteza que diga algo do jogador

A mudança é no **modelo**, não no gráfico: estimar a volatilidade própria de
cada jogador a partir do `consensus_history` (2023–2026), encolhida para a da
posição, e usá-la para escalar os resíduos sorteados em `simulate_players()`.
Só então média × volatilidade separaria um WR "boom/bust" de um WR constante.
Fica como evolução opcional do motor.

## Métricas de realizado × projeção

Para a gaveta do jogador:

- **Gráfico semana a semana**: faixa P10–P90 projetada em cada semana (como foi
  vista naquela semana) + ponto do realizado. Mostra viés e acerto de uma vez.
- **Viés médio** (realizado − projetado), sempre com o nº de jogos. O mart de
  forecasts já tem a coluna `historical_bias`.
- **Taxa dentro da faixa P10–P90** (calibração; esperado ≈ 80%).
- **Booms / busts**: nº de jogos acima do P90 e abaixo do P10.
- **Evitar o desvio do realizado com poucos jogos**: com 5 jogos o erro de
  amostra do desvio é de ~±35%. Mostrar os pontos de cada jogo (strip) em vez de
  resumir num desvio.

## Onde fica na interface

Sem tela nova. Um componente reutilizável, o **"Mapa de comparação"**, em três
contextos:

| Contexto            | Formato                         | Conjunto comparado                                        |
|---------------------|---------------------------------|-----------------------------------------------------------|
| Lineup              | scatter (substitui o atual)     | meu elenco                                                |
| Waivers             | scatter                         | meus jogadores elegíveis ao slot + ~10 melhores FA        |
| Gaveta do jogador   | barras P10–P90 + gráfico semanal | elegíveis ao mesmo slot + 3 melhores FA                   |

A gaveta é estreita demais para um scatter legível; lá ficam as barras e o
gráfico realizado × projetado.

Seletor de lente em chips, com o vocabulário do simulador de trocas
(`web/js/trade-sim.js`): `[Semana] [Próx. 4] [Realizado]`.

## Como manter simples

- **Cor** = posição (`POS_COLOR` existente).
- **Forma**: cheio = meu titular; contorno = meu banco; cinza = free agent.
- **Jogador selecionado**: anel ciano + nome; os demais só no hover.
- **No máximo 15–20 pontos** por gráfico.
- **Linha tracejada "a superar"**: o valor do titular mais fraco que o jogador
  poderia substituir. É a principal ajuda de leitura: tudo à direita dela é
  ganho esperado.

```
 Próx. 3 (méd/sem)
  20 │  stash          ┊      ● titular firme
     │      ○ (bye)    ┊   ◉ selecionado
  15 │ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─
     │   ○ FA          ┊      ● streaming
  10 │  descartável    ┊ a superar (FLEX)
     └─────────────────┊──────────────── Semana atual
```

## FLEX

Comparar **por slot, não por posição**. O conjunto é formado pelos jogadores
elegíveis ao slot (`eligible_slot_ids`, já presente nos marts de rosters e free
agents).

- No FLEX desta liga (RB/WR, conforme `web/js/trade-sim.js`), RB e WR entram no
  mesmo gráfico: pontos são a mesma moeda, e essa é exatamente a decisão do FLEX.
- A linha "a superar" é quem ocupa o FLEX no lineup ótimo (`optimal_slot` no
  mart de rosters), ou seja, o último RB/WR titular.
- Regra legível: um RB ou WR entra no time se superar o FLEX; um TE só se
  superar o TE titular.

## Dados necessários

| Lente / métrica                     | Situação                                                                                      |
|-------------------------------------|-----------------------------------------------------------------------------------------------|
| Semana (W0)                         | já existe (`current/rosters`, `current/free_agents`: `sim_mean`, `p10`, `p90`, …)             |
| Próx. 4 (W0..W3)                    | depende de [`horizon_projections.md`](horizon_projections.md)                                 |
| Projeção feita em cada semana       | já existe: `current/forecasts.parquet` empilha uma run por semana                             |
| Realizado semanal de 2026           | está no `espn_db` (`espn_players_points`, `stat_source_id = 0`, `stat_split_type_id = 1`), mas não há mart; `history/player_points` vai só até 2025 (vem do `analytical_db`) |
| Volatilidade por jogador (opcional) | `history/consensus_history` (2023–2025) já está no bundle                                     |

## Ordem sugerida

1. **Gaveta**: comparação por slot (incluindo FA) + gráfico semanal realizado ×
   projetado. Só falta o mart de realizado semanal de 2026.
2. **Agora × depois** em Waivers e Lineup, depois que o horizonte W0..W3 existir.
3. **Lineup**: trocar o scatter média × desvio pelo Mapa de comparação.
4. (Opcional) Volatilidade por jogador no motor, para dar sentido a um eixo de
   incerteza.
