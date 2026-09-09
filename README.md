# Dudes Football Analytics App

[![R](https://img.shields.io/badge/R-4.0+-blue.svg)](https://www.r-project.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> Trabalhando com Claude Code ou outro agente? Comece por **[`CLAUDE.md`](CLAUDE.md)** —
> mapa dos diretórios, fluxo de dados e o que está defasado neste README.

## 📋 Sumário

- [Sobre](#sobre)
- [Funcionalidades](#funcionalidades)
- [Arquitetura](#arquitetura)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Pipeline de Dados](#pipeline-de-dados)
- [Simulações e Projeções](#simulações-e-projeções)
- [Otimização de Times](#otimização-de-times)
- [Instalação](#instalação)
- [Configuração](#configuração)
- [Uso](#uso)
- [Modelos de Dados](#modelos-de-dados)
- [Análises Disponíveis](#análises-disponíveis)

---

## 🎯 Sobre

O **Dudes Football Analytics App** é uma plataforma completa de análise e otimização para Fantasy Football da NFL, desenvolvida em R. O sistema integra múltiplas fontes de dados, implementa simulações estatísticas avançadas e oferece ferramentas de otimização de escalação baseadas em dados históricos e projeções.

### Objetivo Principal

Fornecer uma vantagem competitiva em ligas de Fantasy Football através de:
- Agregação inteligente de múltiplas fontes de projeções
- Simulações Monte Carlo com 15+ estratégias diferentes
- Otimização matemática de escalações
- Análise histórica de performance vs. potencial
- Machine Learning para previsão de pontuação

---

## ✨ Funcionalidades

### 🔄 Pipeline Automatizado de Dados
- Coleta semanal de projeções de 11+ fontes especializadas
- Integração com API oficial da NFL Fantasy
- Atualização automática de estatísticas, rosters e matchups
- Sistema de cache para reprocessamento e auditoria

### 📊 Motor de Simulação Avançado
- **15 estratégias de simulação** diferentes incluindo:
  - Projeções simples (média, robusta, ponderada)
  - Monte Carlo com dados históricos
  - Sampling por densidade de probabilidade
  - Modelos com correção de erros históricos
  - Combinações balanceadas de múltiplas fontes
- Geração de 1000+ cenários por jogador
- Análise de quantis (5%, 15%, 30%, 50%, 70%, 85%, 95%)

### 🎯 Otimizador de Escalação
- Seleção automática dos melhores jogadores por posição
- Consideração de slots fixos (QB, RB, WR, TE, K, DEF)
- Otimização de slot FLEX (WR/RB)
- Análise de performance realizada vs. potencial máximo
- Comparação de cenários alternativos

### 🤖 Machine Learning
- Modelos preditivos de pontuação usando `tidymodels`
- Feature engineering com variáveis históricas
- Análise de importância de variáveis
- Cross-validation e métricas de performance

### 📈 Análises e Insights
- Weekly trophies (melhores performances)
- Análise de distribuição de pontos
- Comparação de rankings e consensos
- Status de lesões e impacto no desempenho
- Análise de matchups e dificuldade

---

## 🏗️ Arquitetura

O sistema segue uma arquitetura em camadas:

```
┌─────────────────────────────────────────────────────────────┐
│                    ANÁLISES & INSIGHTS                      │
│  (Weekly Trophies, ML Predictions, Team Optimization)      │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│                  TRANSFORMAÇÃO & SIMULAÇÃO                  │
│  (15 Simulation Strategies, Error Calculation, Sampling)   │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│                      PIPELINE DE DADOS                      │
│      (Data Collection, Aggregation, Storage as DM)          │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│                        CAMADA DE API                        │
│   (NFL API, FFAnalytics Scraping, 11+ Data Sources)        │
└─────────────────────────────────────────────────────────────┘
```

### Princípios de Design

1. **Modularidade**: Cada camada é independente e reutilizável
2. **Data Models (DM)**: Uso extensivo do pacote `dm` para relacionamentos entre tabelas
3. **Reproducibilidade**: Sistema de cache com timestamps para auditoria
4. **Versionamento**: Suporte a tags (preview, final) para diferentes momentos da semana

---

## 📁 Estrutura do Projeto

```
DudesApp/
│
├── R/                              # Código-fonte principal
│   ├── api/                        # Integrações com APIs externas
│   │   ├── nfl_api.R              # Core da API da NFL
│   │   ├── nfl_league.R           # Endpoints de liga (teams, matchups, standings)
│   │   ├── nfl_players.R          # Endpoints de jogadores
│   │   ├── nfl_game.R             # Endpoints de estatísticas de jogos
│   │   └── ffa_projection.R       # Web scraping com FFAnalytics
│   │
│   ├── transformation/             # Transformação e processamento de dados
│   │   ├── simulation.R           # Cálculo de erros e aplicação em projeções
│   │   └── missing_player_ids.R   # Mapeamento de IDs entre sistemas
│   │
│   ├── pipeline/                   # Pipelines de ETL
│   │   ├── data_pipeline.R        # Pipeline principal (MASTER)
│   │   ├── data_pipeline_old.R    # Versão legacy
│   │   └── data_pipeline_*_playground.R  # Ambientes de teste
│   │
│   ├── analysis/                   # Análises avançadas
│   │   ├── team_optimizer.R       # Otimização de escalação de times
│   │   └── projection_ml.R        # Modelos de Machine Learning
│   │
│   └── snippets/                   # Scripts de análise ad-hoc
│       ├── simulation_machine.R   # Gerador de múltiplas estratégias de simulação
│       ├── weekly_trophies.R      # Análise de melhores performances
│       ├── distribution_analysis.R # Análise de distribuições de pontos
│       └── player_simulation_analysis.R  # Análise de resultados de simulação
│
├── data/                           # Banco de dados (arquivos RDS)
│   ├── ffa_db.rds                 # Projeções do FFAnalytics
│   ├── nfl_players_db.rds         # Informações de jogadores
│   ├── nfl_teams_db.rds           # Times e owners da liga
│   ├── nfl_stats_db.rds           # Estatísticas por semana
│   ├── nfl_round_db.rds           # Matchups e rosters por semana
│   ├── nfl_recap_db.rds           # Recaps semanais
│   ├── dudes_simulation_db.rds    # Resultados de simulações
│   └── temp/                      # Cache de respostas API para reprocessamento
│
├── config/                         # Configurações
│   ├── config.yml                 # Auth token, league ID
│   ├── score_settings.yml         # Regras de pontuação da liga
│   └── leagues.json               # Informações de ligas disponíveis
│
├── export/                         # Outputs e relatórios
│
└── DudesApp.Rproj                 # Projeto RStudio

```

---

## 🔄 Pipeline de Dados

O pipeline principal (`R/pipeline/data_pipeline.R`) executa 6 etapas sequenciais:

### 1️⃣ Coleta de Projeções (FFAnalytics)

```r
# Scraping de 11+ fontes de projeções
Sources: CBS, ESPN, FantasyPros, FantasySharks, FFToday,
         FleaFlicker, NumberFire, FantasyFootballNerd, NFL,
         RTSports, Walterfootball
Posições: QB, RB, WR, TE, K, DST
```

**Output**: `ffa_db.rds`
- `ffa_scrape`: Raw data do scraping
- `ffa_player_ids`: Mapeamento de IDs
- `ffa_projtable`: Projeções agregadas (average, robust, weighted)
- `ffa_proj_source_points`: Projeções por fonte

### 2️⃣ Atualização de Times

```r
# GET /v2/league/teams
```

**Output**: `nfl_teams_db.rds`
- `nfl_teams`: Informações dos times da liga
- `nfl_owners`: Proprietários dos times

### 3️⃣ Atualização de Jogadores

```r
# GET /v2/league/players
```

**Output**: `nfl_players_db.rds`
- `nfl_players`: Dados cadastrais dos jogadores
- `nfl_player_injury_status`: Status de lesões com histórico temporal

### 4️⃣ Estatísticas de Jogos

```r
# GET /v2/league/stats
# Coleta estatísticas de todas as semanas até a atual
```

**Output**: `nfl_stats_db.rds`
- `nfl_players_points`: Pontuação por jogador/semana
- `nfl_players_stats`: Estatísticas detalhadas por categoria

### 5️⃣ Matchups e Rosters

```r
# GET /v2/league/matchups
```

**Output**: `nfl_round_db.rds`
- `matchups_games`: Confrontos da semana
- `nfl_teams_rosters`: Escalações dos times
- `nfl_teams_week_stats`: Estatísticas semanais dos times
- `nfl_teams_season_stats`: Estatísticas acumuladas da temporada

### 6️⃣ Recaps (Apenas para tag="final")

```r
# GET /v2/league/team/matchuprecap
# Coleta narrativas e highlights dos confrontos
```

**Output**: `nfl_recap_db.rds`

---

## 🎲 Simulações e Projeções

O arquivo `R/snippets/simulation_machine.R` implementa 15 estratégias diferentes de simulação:

### Estratégias de Simulação

#### 📌 Projeções Simples (1 valor)
1. **NFL**: Projeção oficial da NFL
2. **proj_table_average**: Média simples de todas as fontes
3. **proj_table_robust**: Média robusta (resistente a outliers)
4. **proj_table_weighted**: Média ponderada por acurácia histórica

#### 🎯 Monte Carlo (N valores)
5. **proj_src**: Todas as projeções das fontes disponíveis
6. **proj_src_errors**: Projeções com erros históricos aplicados
7. **proj_src_w_errors**: Combinação de projeções originais + com erros
8. **hist_data**: Dados históricos completos do jogador
9. **current_season_his**: Performance apenas da temporada atual
10. **proj_src_w_errors_balanced**: Balanceamento de representatividade entre fontes

#### 📊 Sampling por Densidade (N valores)
11. **proj_src_density**: Sampling da densidade das projeções
12. **proj_src_errors_density**: Sampling da densidade das projeções com erros
13. **proj_src_w_errors_density**: Sampling da densidade combinada
14. **hist_data_density**: Sampling da densidade de dados históricos
15. **current_season_his_density**: Sampling da densidade da temporada atual
16. **proj_src_w_error_current_season_density**: Mix de todas as densidades

### Como Funciona

```r
# Para cada jogador, cada estratégia gera "seeds"
dudes_players_seeds
├── season, week, id, playerId, pos
├── simType: tipo de estratégia
└── seeds: vetor de valores possíveis

# Resampling para gerar 1000 simulações
dudes_players_simulations
├── simulation: 1000 valores amostrados
└── simQuantiles: quantis (5%, 15%, 30%, 50%, 70%, 85%, 95%)
```

### Tratamento de Erros Históricos

```r
# R/transformation/simulation.R

calcProjectionErrors()
  # Calcula erro = pontos_reais - pontos_projetados
  # Para cada fonte, semana e jogador

applyErrorToProjection()
  # Aplica distribuição de erros históricos
  # Às projeções atuais
```

---

## 🎯 Otimização de Times

O arquivo `R/analysis/team_optimizer.R` implementa otimização de escalação:

### Slots da Liga

```r
QB:  1 slot
WR:  2 slots
RB:  2 slots
TE:  1 slot
K:   1 slot
DEF: 1 slot
FLEX: 1 slot (WR ou RB)
```

### Algoritmo de Seleção

```r
selectBestPlayers()
  1. Para cada posição fixa:
     - Seleciona top N jogadores por pontuação
  2. Para slot FLEX:
     - Dos jogadores restantes elegíveis (WR/RB)
     - Seleciona o melhor disponível
  3. Retorna escalação otimizada
```

### Métricas Calculadas

- **totalPts**: Pontuação real obtida pelos starters
- **potencialPts**: Pontuação máxima possível com o roster disponível
- **Eficiência**: `totalPts / potencialPts` (% do potencial alcançado)

### Análise de Cenários

O otimizador compara todos os pares de jogadores da mesma posição:
- Simula 1000 cenários para cada combinação
- Calcula probabilidade de vitória em cada cenário
- Identifica a melhor escalação probabilística

---

## 📦 Instalação

### Requisitos

- R >= 4.0
- RStudio (recomendado)

### Pacotes Necessários

```r
# Manipulação de dados
install.packages(c("tidyverse", "dm", "lubridate", "glue"))

# APIs e Web Scraping
install.packages(c("httr", "jsonlite", "ffanalytics"))

# Machine Learning
install.packages(c("tidymodels", "vip", "broom"))

# Visualização
install.packages(c("skimr", "ggplot2"))

# Utilities
install.packages(c("purrr", "yaml", "cli"))
```

---

## ⚙️ Configuração

### 1. Configuração da Liga

> **Migração NFL → ESPN.** A liga migrou para o ESPN Fantasy. Hoje há dois pipelines
> independentes: `R/pipeline/data_pipeline.R` (NFL Fantasy + `ffanalytics`, ainda a
> única fonte de `ffa_db` e dos bancos `nfl_*`) e `R/pipeline/data_pipeline_espn.R`
> (ESPN, via `R/api/espn_fantasy_client.R`, gera `data/espn_db.rds`). O bridge entre
> os `player_id` do ESPN e os ids do `ffanalytics` que o código downstream usa ainda
> não foi feito.

Edite `config/config.yml` (arquivo é gitignored):

```yaml
ESPN_LEAGUEID: 342842788
myTeamEspnId: 4
season: 2026
week: 0
ESPN_SWID: "{...}"     # cookie de sessão ESPN
ESPN_S2: "..."         # cookie de sessão ESPN (já URL-encoded)
```

**Como obter os cookies (ESPN):**
1. Acesse ESPN Fantasy logado no navegador
2. DevTools (F12) > Application > Cookies > `fantasy.espn.com`
3. Copie os valores de `SWID` e `espn_s2`

### 2. Regras de Pontuação

Edite `config/score_settings.yml` conforme as regras da sua liga:

```yaml
pass:
  pass_yds: 0.04      # 1 ponto a cada 25 jardas
  pass_tds: 4.0       # 4 pontos por TD
  pass_int: -2.0      # -2 pontos por interceptação

rush:
  rush_yds: 0.1       # 1 ponto a cada 10 jardas
  rush_tds: 6.0       # 6 pontos por TD

rec:
  rec: 1.0            # PPR (Point Per Reception)
  rec_yds: 0.1
  rec_tds: 6.0

# ... (ver arquivo completo para todas as regras)
```

### 3. Parâmetros do Pipeline

Edite `R/pipeline/data_pipeline.R`:

```r
# MASTER PARAMETERS  (bloco no final de R/pipeline/data_pipeline.R)
.season <- 2026L      # Temporada atual
.week   <- 0L         # Semana atual (0 = pré-temporada)
.tag    <- "season"   # "preview" | "final" | "season"
```

> Estes valores são a fonte da verdade — este README pode estar defasado. Sempre
> confira o bloco `# MASTER PARAMETERS ####` no script antes de rodar.

---

## 🚀 Uso

### Executar Pipeline Completo

```r
# Abra o projeto no RStudio
# Execute o script principal:
source("R/pipeline/data_pipeline.R")
```

O pipeline irá:
1. Fazer scraping de todas as fontes de projeções
2. Atualizar dados da NFL via API
3. Salvar/atualizar todos os databases
4. Gerar visualizações do modelo de dados

### Executar Pipeline ESPN

```r
source("R/pipeline/data_pipeline_espn.R")
```

Lê `.season` / `.week` de `config/config.yml`, busca um snapshot da liga no ESPN
(1 request combinado) mais o pool de jogadores e suas projeções/pontos, e faz
upsert de um único objeto `dm` com 12 tabelas `espn_*` em `data/espn_db.rds`:
`espn_league`, `espn_members`, `espn_teams`, `espn_team_standings`,
`espn_roster_slots`, `espn_scoring_rules`, `espn_players`,
`espn_player_injury_status`, `espn_players_points` (projetado + real via
`stat_source_id`), `espn_rosters`, `espn_matchups`, `espn_draft`. Falha com erro
claro se rodado antes do draft. Não toca em nada `ffa_*` / `nfl_*`.

### Gerar Simulações

```r
source("R/snippets/simulation_machine.R")
```

Este script:
- Lê os databases existentes
- Gera seeds para 15 estratégias de simulação
- Executa 1000 simulações por jogador
- Salva em `data/dudes_simulation_db.rds`

### Otimizar Escalação

```r
source("R/analysis/team_optimizer.R")
```

Analisa:
- Melhor escalação possível por time
- Performance vs. potencial
- Cenários alternativos probabilísticos

### Análises Ad-hoc

```r
# Melhores performances da semana
source("R/snippets/weekly_trophies.R")

# Análise de distribuição de pontos
source("R/snippets/distribution_analysis.R")

# Machine Learning de projeções
source("R/analysis/projection_ml.R")
```

---

## 📊 Modelos de Dados

### Diagrama de Relacionamentos

```
ffa_db
├── ffa_scrape (PK: season, week, tag, timestamp)
├── ffa_player_ids (PK: id)
├── ffa_projtable (PK: season, week, id, pos, avg_type, tag, timestamp)
│   └── FK: id → ffa_player_ids
└── ffa_proj_source_points (PK: season, week, id, pos, data_src, tag, timestamp)
    └── FK: id → ffa_player_ids

nfl_teams_db
├── nfl_teams (PK: teamId)
│   └── FK: ownerUserId → nfl_owners
└── nfl_owners (PK: ownerUserId)

nfl_players_db
├── nfl_players (PK: playerId)
└── nfl_player_injury_status (PK: playerId, timestamp)
    └── FK: playerId → nfl_players

nfl_stats_db
├── nfl_players_points (PK: season, week, playerId)
└── nfl_players_stats (PK: season, week, playerId, statId)
    └── FK: season, week, playerId → nfl_players_points

nfl_round_db
├── matchups_games (PK: season, week, matchupId)
├── nfl_teams_rosters (PK: season, week, teamId, playerId, tag, timestamp)
├── nfl_teams_week_stats (PK: season, week, teamId, tag, timestamp)
└── nfl_teams_season_stats (PK: season, week, teamId, tag, timestamp)

dudes_simulation_db
├── dudes_players_seeds (PK: season, week, id, playerId, pos, simType)
└── dudes_players_simulations (PK: season, week, id, playerId, pos, simType)
```

---

## 📈 Análises Disponíveis

### 1. Weekly Trophies
**Arquivo**: `R/snippets/weekly_trophies.R`

Identifica:
- Melhor jogador da semana
- Melhor performance por posição
- Jogador mais subestimado (superou projeções)
- Maior decepção (não atingiu projeções)

### 2. Distribution Analysis
**Arquivo**: `R/snippets/distribution_analysis.R`

Analisa:
- Distribuições de pontuação por posição
- Modelos probabilísticos (Normal, Log-Normal, Gamma)
- Ajuste de parâmetros por MLE
- Comparação de estratégias de simulação

### 3. Projection ML
**Arquivo**: `R/analysis/projection_ml.R`

Implementa:
- Regressão linear com `tidymodels`
- Feature engineering (PCA, correlações)
- Imputação de missing values
- Validação cruzada
- Análise de importância de variáveis

### 4. Team Simulation
**Arquivo**: `R/snippets/team_sim.R`

Simula:
- Outcomes de matchups
- Probabilidades de vitória
- Distribuição de pontuação por time
- Análise de risco vs. upside

### 5. Player Simulation Analysis
**Arquivo**: `R/snippets/player_simulation_analysis.R`

Compara:
- Acurácia das diferentes estratégias de simulação
- Calibração de intervalos de confiança
- RMSE por estratégia e posição

### 6. Rank Analysis
**Arquivo**: `R/snippets/analysis_tier_rank_ecr.R`

Analisa:
- Expert Consensus Rankings (ECR)
- Tier breaks (agrupamentos de jogadores)
- Divergências entre rankings
- Value picks (ADP vs. projeções)

### 7. Injury Impact Analysis
**Arquivo**: `R/snippets/analysis_injuryGameStatus.R`

Estuda:
- Impacto de status de lesão na performance
- Histórico de jogadores "questionable" vs. "probable"
- Decisões de start/sit baseadas em status

---

## 🔧 Funcionalidades Técnicas

### Sistema de Cache
Todas as respostas de API são salvas em `data/temp/` com timestamp:
```r
saveTempResp(obj, name, season, week, tag, timestamp)
# Permite reprocessamento sem novas chamadas à API
```

### Versionamento de Dados
Suporte a tags para diferentes momentos da semana:
- `"preview"`: Projeções iniciais (segunda/terça)
- `"final"`: Dados finais (após todos os jogos)

### Upsert Automático
```r
updateDB(new_db, db_file)
# Merge inteligente: atualiza registros existentes, insere novos
```

### Data Models (dm)
Uso extensivo do pacote `dm`:
- Definição de PKs e FKs
- Validação de integridade referencial
- Visualização de ERDs
- Joins automáticos e type-safe

---

## 📝 Workflow Típico Semanal

### Segunda/Terça (Preview)
```r
.week <- 18L
.tag <- "preview"
source("R/pipeline/data_pipeline.R")
source("R/snippets/simulation_machine.R")
source("R/analysis/team_optimizer.R")
# Analisa projeções iniciais e define escalação
```

### Domingo (Durante os jogos)
```r
# Monitora performance em tempo real
source("R/snippets/weekly_trophies.R")
```

### Segunda seguinte (Final)
```r
.week <- 18L
.tag <- "final"
source("R/pipeline/data_pipeline.R")
# Coleta estatísticas finais e recaps
# Avalia acurácia das projeções
source("R/transformation/simulation.R")
# Atualiza erros históricos para próxima semana
```

---

## 🤝 Contribuindo

Sugestões de melhorias:

1. **Novos Modelos de Simulação**
   - Adicionar estratégias em `simulation_machine.R`
   - Implementar novos métodos de sampling

2. **Machine Learning**
   - Testar outros algoritmos (Random Forest, XGBoost)
   - Feature engineering com estatísticas avançadas

3. **Visualizações**
   - Dashboards interativos com Shiny
   - Gráficos de evolução temporal

4. **Automação**
   - Integração com GitHub Actions para pipeline automático
   - Notificações via Telegram/Slack

---

## 📄 Licença

Este projeto é de uso pessoal para fins educacionais e de pesquisa.

---

## 🙏 Agradecimentos

- **[ffanalytics](https://github.com/FantasyFootballAnalytics/ffanalytics)**: Package R para scraping de projeções
- **NFL Fantasy API**: Dados oficiais da NFL
- **tidyverse & dm**: Ecossistema de pacotes R

---

## 📧 Contato

Para dúvidas ou sugestões sobre este projeto, abra uma issue no repositório.

---

**Última atualização**: Temporada 2026 - pré-temporada (migração NFL → ESPN)
