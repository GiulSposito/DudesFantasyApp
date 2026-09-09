# WEB_MVP_IMPLEMENTATION_PLAN.md

## 1. Purpose

Este documento transforma:

* `app_arch.md`
* `app_web_data_contract.md`

em um plano incremental de implementação do **Fantasy Football Analytical Cockpit**.

Objetivo:

> Construir um cockpit analítico web static-first sobre o pipeline R existente, sem introduzir backend permanente e sem duplicar lógica analítica no frontend.

O MVP deve consumir principalmente os resultados já persistidos no `decision_db`, que contém:

* `simulation_runs`
* `player_forecasts`
* `matchup_simulations`
* `lineup_evaluations`
* `lineup_recommendations`
* `free_agent_recommendations`
* `trade_recommendations`

---

# 2. Target Architecture

```text
Existing R Pipeline
        │
        ▼
ffa_db
espn_db
analytical_db
decision_db
        │
        ▼
R/web/build_web_bundle.R
        │
        ▼
web/data/
Parquet + JSON
        │
        ▼
Quarto Static Website
        │
        ├── DuckDB-Wasm
        ├── Plotly
        ├── JavaScript
        └── CSS/SCSS
        │
        ▼
_site/
```

The production application MUST NOT require:

```text
Shiny Server
PostgreSQL
REST API
Node server
Python service
Redis
Docker runtime
```

A simple static HTTP server must be sufficient.

---

# 3. Implementation Principles

## 3.1 Preserve existing domain logic

Do not rewrite in `R/web/`:

* ESPN → FFA matching;
* historical residual sampling;
* player simulation;
* lineup optimization;
* free-agent evaluation;
* trade evaluation.

Reuse existing functions or persisted outputs.

The existing decision engine already performs ESPN→FFA bridging and stores the mapping method.

---

## 3.2 R owns analytics

```text
R
=
calculation
simulation
optimization
recommendation
semantic joins
```

Frontend:

```text
JS / DuckDB
=
filter
sort
search
simple aggregation
presentation
interaction
```

---

## 3.3 Build vertically

Do not implement every backend dataset first and only later start the UI.

Prefer vertical slices:

```text
data contract
      ↓
one presentation mart
      ↓
one page
      ↓
validation
      ↓
next feature
```

---

## 3.4 Current run first

The first usable version should focus on:

```text
current season
current week
current run
```

Historical navigation is secondary.

---

# 4. Target Repository Structure

Add:

```text
R/
└── web/
    ├── build_web_bundle.R
    │
    ├── bundle/
    │   ├── runs.R
    │   ├── dimensions.R
    │   ├── forecasts.R
    │   ├── standings.R
    │   ├── rosters.R
    │   ├── matchups.R
    │   ├── lineup.R
    │   ├── free_agents.R
    │   ├── trades.R
    │   ├── projections.R
    │   └── data_health.R
    │
    └── utils/
        ├── schema.R
        ├── parquet.R
        ├── privacy.R
        └── validation.R
```

Frontend:

```text
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
├── data-health.qmd
│
├── components/
│   ├── player-card.html
│   ├── metric-card.html
│   ├── action-card.html
│   └── uncertainty-bar.html
│
├── js/
│   ├── app.js
│   ├── state.js
│   ├── data.js
│   ├── charts.js
│   ├── format.js
│   └── pages/
│       ├── command-center.js
│       ├── matchup.js
│       ├── lineup.js
│       ├── waivers.js
│       ├── trades.js
│       ├── league.js
│       └── players.js
│
├── css/
│   ├── theme.scss
│   ├── components.scss
│   └── dashboard.scss
│
└── data/
```

---

# 5. Milestone Overview

```text
M0   Foundation
 ↓
M1   Web Data Bundle
 ↓
M2   Application Shell
 ↓
M3   Command Center + Matchups
 ↓
M4   Lineup Lab
 ↓
M5   Waivers + Trades
 ↓
M6   League + Player Explorer
 ↓
M7   Projection Lab + Data Health
 ↓
M8   Polish + Static Deployment
```

Every milestone should leave the project in a working state.

---

# 6. M0 — Foundation

## Objective

Create the minimum project structure and establish contracts before implementing features.

---

## Create

```text
ARCHITECTURE.md
WEB_DATA_CONTRACT.md
WEB_MVP_IMPLEMENTATION_PLAN.md

R/web/
web/
```

---

## Dependencies

R packages:

```r
arrow
dplyr
tidyr
purrr
stringr
jsonlite
lubridate
dm
```

Frontend dependencies should remain minimal.

Required:

```text
Quarto
Plotly.js
DuckDB-Wasm
```

Avoid introducing frontend frameworks such as React/Vue/Svelte in MVP unless an implementation blocker appears.

---

## Deliverables

Create:

```text
web/_quarto.yml
web/index.qmd
web/css/theme.scss
```

Initial page may simply display:

```text
Fantasy Football Analytical Cockpit

No data bundle loaded.
```

---

## Acceptance

```text
quarto preview web
```

must open successfully.

---

## Suggested commit

```text
feat(web): scaffold static analytical cockpit
```

---

# 7. M1 — Web Data Bundle

## Objective

Implement the stable interface between R analytics and frontend.

This is the most important architectural milestone.

---

# 7.1 Resolve run

Implement:

```r
resolve_run <- function(decision_db, run_id = NULL)
```

Behavior:

```text
run_id supplied
    → select exact run

run_id NULL
    → select most recent run
```

Return:

```text
run_id
season
week
tag
created_at
ffa_timestamp
espn_timestamp
model_version
n_sim
seed
```

`simulation_runs` already carries these execution metadata.

---

# 7.2 runs.parquet

Build directly from:

```text
decision_db$simulation_runs
```

Add:

```text
is_current
```

---

# 7.3 dimensions

Implement:

```text
teams.parquet
players.parquet
roster_slots.parquet
```

Sources:

```text
espn_teams
espn_members
espn_players
espn_roster_slots
ffa_player_ids
ffa_players
```

The ESPN source already contains teams, players, roster slots and league configuration.

---

# 7.4 forecasts

Implement:

```text
current/forecasts.parquet
```

Source:

```text
decision_db$player_forecasts
```

Enrich only with presentation fields such as:

```text
player_name
nfl_team
historical_bias
```

Do not recompute forecasts.

`player_forecasts` already stores quantiles, source coverage, probability thresholds and residual-pool diagnostics.

---

# 7.5 matchups

Implement:

```text
current/matchups.parquet
```

Source:

```text
decision_db$matchup_simulations
```

Enrich:

```text
home_team_name
away_team_name
is_my_matchup
```

---

# 7.6 lineup datasets

Implement:

```text
current/lineup_evaluations.parquet
current/lineup_recommendations.parquet
```

Directly from corresponding `decision_db` tables.

The source already contains both current and optimal expected scores, quantiles and win probabilities.

---

# 7.7 rosters

Build:

```text
current/rosters.parquet
```

Join:

```text
ESPN current roster
+
players
+
injury status
+
forecast
+
optimal lineup state
```

Reuse existing ESPN→FFA mapping.

Do NOT implement a separate matching algorithm.

---

# 7.8 Waiver and trade recommendations

Export:

```text
current/waiver_recommendations.parquet
current/trade_recommendations.parquet
```

Preserve decision-engine ranking.

For free agents, recommendation ranking is based on `delta_expected`, not on win-probability delta.

For trades, preserve:

```text
fairness
trade_score
partner_is_my_opponent
```

and their documented semantics.

---

# 7.9 manifest.json

Generate last.

It must contain:

```text
schema_version
generated_at

current run metadata

dataset paths
privacy mode
```

---

# 7.10 Validation

Implement:

```r
validate_web_bundle()
```

Minimum validations:

### PK uniqueness

```text
runs
forecasts
matchups
lineup_evaluations
rosters
```

### Referential integrity

```text
player → players
team → teams
```

### Probability ranges

```text
0 <= probability <= 1
```

### Matchup sum

```text
home + away + tie ≈ 1
```

### Quantile ordering

```text
p05 <= p10 <= p25 <= p50 <= p75 <= p90 <= p95
```

### Run consistency

All `current/*` marts must refer to the same current run.

---

## M1 Definition of Done

This command:

```r
source("R/web/build_web_bundle.R")

build_web_bundle()
```

must generate a complete:

```text
web/data/
```

without running the web application.

---

## Suggested commits

```text
feat(web-data): add run resolution and manifest
feat(web-data): export dimensions and forecasts
feat(web-data): export league and decision marts
test(web-data): validate web data contract
```

---

# 8. M2 — Application Shell

## Objective

Create the reusable static application structure before implementing detailed pages.

---

# 8.1 Navigation

Implement sidebar:

```text
Command Center

Matchup
Lineup
Waivers
Trades

League
Players
Projections

Data Health
```

---

# 8.2 Global header

Display:

```text
Season
Week
Run
Team
Last updated
```

Example:

```text
2026 · Week 1 · Preview
player-mc-v2
Updated Sep 9 07:24
```

---

# 8.3 Global state

Create:

```text
web/js/state.js
```

Canonical state:

```js
{
  season,
  week,
  runId,
  teamId,
  position
}
```

State priority:

```text
URL
 ↓
localStorage
 ↓
manifest default
```

---

# 8.4 Data abstraction

Create:

```text
web/js/data.js
```

Do not scatter DuckDB initialization/query code across pages.

Provide simple helpers:

```text
loadManifest()

getTeams()
getForecasts()
getRoster(teamId)
getMatchups()
getLineupEvaluation(teamId)
getWaiverRecommendations(teamId)
getTradeRecommendations(teamId)
```

Pages consume these functions rather than Parquet paths.

---

# 8.5 Formatting utilities

Create:

```text
format.js
```

Standard functions:

```text
formatPoints()
formatProbability()
formatDelta()
formatPosition()
formatCoverage()
formatTimestamp()
```

Consistency is important.

Example:

```text
0.637 → 63.7%
0.074 → +7.4 pp
4.82 → +4.8 pts
```

---

## M2 Acceptance

Navigation between all pages must work even if some pages still display placeholder content.

Global team/run state must persist across pages.

---

## Suggested commit

```text
feat(web): add application shell and global state
```

---

# 9. M3 — Command Center + Matchups

This is the first truly useful vertical slice.

---

# 9.1 Command Center

Implement:

```text
web/index.qmd
web/js/pages/command-center.js
```

---

## Hero matchup

Display:

```text
My Team
expected score

Opponent
expected score

win probability

P10 / P50 / P90
```

Source:

```text
matchups.parquet
```

---

## KPI cards

Implement:

```text
Win Probability
Expected Score
Optimal Expected
Lineup Gain
Best Waiver
Best Trade
```

Derived only through simple selection from existing marts.

---

## Action Center

Combine top entries from:

```text
lineup_recommendations
waiver_recommendations
trade_recommendations
```

Example:

```text
START Player A over Player B
+4.1 pts
+7.4 pp win probability
```

Do not create a new analytical score for v1.

Order actions primarily by their native recommendation rank.

---

## League matchup board

Show every weekly matchup as:

```text
Team A       72%
██████████████░░░░
Team B       28%
```

---

# 9.2 Matchup page

Implement:

```text
matchup.qmd
matchup.js
```

---

## Required visualizations

### Probability bar

```text
TEAM A  ████████████░░░  TEAM B
                63 / 37
```

### Expected-range chart

```text
p10 ───── p50 ───── p90
```

for each team.

### Starter contribution chart

Use roster + forecasts.

Show expected value per starter.

### League matchups

Allow switching matchup.

---

## M3 Acceptance

User must be able to answer:

```text
Who am I playing?
What is my expected score?
What is my chance of winning?
How uncertain is that prediction?
What are the other league matchups?
```

without leaving these two pages.

---

## Suggested commits

```text
feat(web): implement command center
feat(web): implement matchup center
```

---

# 10. M4 — Lineup Lab

## Objective

Turn optimizer output into an actionable lineup interface.

---

# 10.1 Summary comparison

Use:

```text
lineup_evaluations.parquet
```

Display:

| Metric          | Current | Optimal | Delta |
| --------------- | ------: | ------: | ----: |
| Expected        |         |         |       |
| P10             |         |         |       |
| Median          |         |         |       |
| P90             |         |         |       |
| Win probability |         |         |       |

Do not assume optimal win probability is always greater than current win probability; the source explicitly warns otherwise.

---

# 10.2 Roster board

Sections:

```text
STARTERS
BENCH
IR
```

Each player card:

```text
Player
Position
NFL team

sim_mean
P10–P90
injury status
coverage
```

Highlight:

```text
recommended OUT
recommended IN
optimal starter
```

---

# 10.3 Recommendation cards

Use:

```text
lineup_recommendations.parquet
```

Show:

```text
OUT Player X
IN  Player Y

Slot: FLEX

+4.1 expected points
+7.4 pp win probability
```

---

# 10.4 Opportunity chart

Scatter:

```text
X = sim_mean
Y = sim_sd
```

for the team's roster.

Use labels/tooltip for player identity.

---

## M4 Acceptance

A user must be able to understand:

```text
current lineup
optimal lineup
exact substitutions
expected effect
risk/upside of rostered players
```

---

## Suggested commit

```text
feat(web): implement lineup optimization lab
```

---

# 11. M5 — Waivers + Trades

These are separate screens but belong to the same decision-oriented milestone.

---

# 11.1 Waiver Center

Implement:

```text
waivers.qmd
waivers.js
```

---

## Recommendation scatter

```text
X = delta_expected
Y = delta_win_probability
```

Point = one ADD/DROP recommendation.

---

## Recommendation table

Columns:

```text
Rank
Add
Drop
Position
Δ Expected
Δ Win Probability
```

---

## Detail interaction

Click recommendation:

```text
before roster
after roster

drop player metrics
add player metrics
```

No recalculation required.

---

## Free-agent explorer

If `free_agents.parquet` is implemented, allow:

```text
position filter
search
sim_mean sort
P90 sort
coverage filter
```

---

# 11.2 Trade Center

Implement:

```text
trades.qmd
trades.js
```

---

## Core chart

Trade opportunity map:

```text
X = my_delta_expected
Y = their_delta_expected
```

Each point = proposal.

Quadrant labels:

```text
win-win
you benefit
partner benefits
bad trade
```

Current decision engine should normally only return trades satisfying positive-side filters, but the visualization should not assume this forever.

---

## Tooltip

Show:

```text
Give
Receive

My delta
Their delta

Fairness
Trade score
Win probability delta
```

---

## Partner ranking

Group trades by:

```text
other_team_id
```

Show best `trade_score` per team.

---

## Mandatory warning

If:

```text
partner_is_my_opponent = TRUE
```

display:

```text
Current-week win probability impact may be optimistic.
```

The source explicitly documents this caveat.

---

## M5 Acceptance

Waiver page answers:

```text
Who should I add?
Who should I drop?
How much does the move improve my team?
```

Trade page answers:

```text
Who could I trade with?
What do I give?
What do I receive?
Does the move help both teams?
How fair is it?
```

---

## Suggested commits

```text
feat(web): implement waiver recommendation center
feat(web): implement trade opportunity center
```

---

# 12. M6 — League Analyzer + Player Explorer

---

# 12.1 League Analyzer

Implement:

```text
league.qmd
league.js
```

---

## Standings

Use:

```text
standings.parquet
```

Display:

```text
Rank
Team
Record
Points For
Points Against
```

---

## Strength ranking

For MVP define team strength transparently as:

```text
optimal_expected
```

from `lineup_evaluations`.

Do not invent a composite Power Score yet.

---

## Position strength heatmap

Derive in browser or preferably presentation mart:

```text
team
×
position
```

metric:

```text
sum(sim_mean of optimal/startable roster)
```

Normalize against league mean if desired:

```text
team_position_value
-
league_position_mean
```

This is allowed as a simple presentation aggregation.

---

## League scatter

Plot:

```text
X = standings rank / wins
Y = optimal_expected
```

Purpose:

identify:

```text
strong teams with poor record
weak teams with good record
```

Do not label as "luck" until expected-win methodology is implemented.

---

# 12.2 Player Explorer

Implement:

```text
players.qmd
players.js
```

---

## Main table

Columns:

```text
Player
Position
NFL Team

Projection
Sim Mean

P10
P50
P90

P(>10)
P(>15)
P(>20)
P(>25)

Sources
Coverage
```

---

## Filters

```text
Search
Position
NFL Team
Coverage
```

---

## Detail drawer

Click player:

```text
projection
simulation mean
quantile range
threshold probabilities
source count
coverage class
historical bias
```

---

## M6 Acceptance

League:

```text
Who are the strongest teams?
Where is each team strong?
How does current ranking compare with projected strength?
```

Players:

```text
Who are the best projected players?
Who has the highest ceiling?
Who has unusual uncertainty?
How reliable is the forecast coverage?
```

---

## Suggested commits

```text
feat(web): implement league analyzer
feat(web): implement player explorer
```

---

# 13. M7 — Projection Lab + Data Health

This milestone explains **why the model should be trusted**.

---

# 13.1 Projection exports

Implement if not already present:

```text
source_projections.parquet
source_accuracy.parquet
```

`analytical_db$source_errors` already stores bias, MAE, RMSE and sample size by source, position and season.

---

# 13.2 Projection Lab

Implement:

```text
projections.qmd
projections.js
```

Visualizations:

### Source accuracy heatmap

```text
rows = projection source
columns = position
value = MAE/RMSE
```

Toggle:

```text
MAE
RMSE
Bias
```

### Source bias chart

Diverging horizontal bars.

### Player source disagreement

For selected player:

```text
CBS
ESPN
NFL
FantasyPros
...
```

dot plot of projected points.

### Consensus uncertainty

Plot:

```text
source_sd
vs
historical absolute residual
```

when history mart is available.

---

# 13.3 Data Health

Implement:

```text
data-health.qmd
data-health.js
```

Show:

```text
Current run
Model version
n_sim

FFA timestamp
ESPN timestamp

Forecast players
Roster players
Mapped starters

Single coverage
Sparse coverage
Ensemble coverage
```

The source defines these coverage classes and already records coverage on player forecasts.

---

## Mapping diagnostics

Show `bridge_method` counts if available:

```text
direct ESPN ID
D/ST offset
name + position
manual override
```

---

## M7 Acceptance

A user must be able to understand:

```text
where forecasts came from
which sources historically perform better
how much sources disagree
how complete current data is
whether player mappings are healthy
```

---

## Suggested commits

```text
feat(web): implement projection analysis lab
feat(web): implement model and data health
```

---

# 14. M8 — Polish + Deployment

---

# 14.1 Responsive behavior

Desktop:

```text
sidebar navigation
multi-column dashboards
```

Tablet:

```text
collapsed sidebar
```

Mobile:

```text
bottom or compact navigation
single-column cards
horizontal scroll for analytical tables
```

---

# 14.2 Loading states

Every page must handle:

```text
loading
empty
error
stale data
```

Avoid blank charts.

---

# 14.3 Empty recommendation states

Zero rows is not necessarily an error.

Examples:

```text
No lineup substitutions recommended.

No acceptable waiver move found.

No mutually beneficial trade found.
```

This is important because several decision tables legitimately allow zero rows.

---

# 14.4 Static build

Target:

```bash
Rscript -e 'source("R/web/build_web_bundle.R"); build_web_bundle()'

quarto render web
```

Output:

```text
web/_site/
```

---

# 14.5 Deployment target

First choice:

```text
GitHub Pages
```

Alternative:

```text
Cloudflare Pages
```

No infrastructure should be introduced merely for deployment.

---

# 14.6 Privacy validation

Before public deploy:

```text
privacy = "public"
```

verify absence of:

```text
credentials
cookies
API tokens
owner IDs
unnecessary personal data
```

---

## M8 Acceptance

Copying:

```text
web/_site/
```

to any static web server must produce a functioning cockpit.

---

## Suggested commit

```text
feat(web): finalize static build and deployment
```

---

# 15. Deferred Features

Do NOT block MVP for these features.

---

## M9 — What Changed?

Compare:

```text
current run
vs
previous run
```

Detect:

```text
forecast movement
matchup probability movement
injury changes
new lineup recommendation
new waiver recommendation
new trade recommendation
```

---

## M10 — Matchup Distribution

Add:

```text
matchup_distribution_bins
```

Do not persist the 10,000 individual simulation draws.

The decision engine intentionally avoids persisting those draws today.

---

## M11 — Expected Wins / Schedule Luck

Use completed weekly team scores to calculate all-play record and expected wins.

Only after this exists should the UI present concepts such as:

```text
luck index
expected record
schedule luck
```

---

## M12 — Season Simulator

New analytics module.

Potential output:

```text
expected wins
playoff probability
bye probability
championship probability
seed probabilities
```

This is **new analytics**, not frontend work.

---

## M13 — Draft Review

Use:

```text
espn_draft
```

The ESPN source already provides overall pick, round, team and player.

Potential views:

```text
snake draft board
draft value
position runs
best/worst selections
```

---

# 16. Do Not Implement Yet

Avoid premature complexity:

```text
React SPA rewrite
custom API
PostgreSQL
user accounts
authentication service
websocket live scoring
server-side Monte Carlo
frontend lineup optimizer
frontend trade engine
frontend ESPN access
microservices
Docker production cluster
```

Only introduce infrastructure when a concrete capability cannot reasonably remain static.

---

# 17. Testing Strategy

Three levels.

---

## 17.1 R contract tests

Validate:

```text
schemas
data types
PKs
references
probabilities
quantiles
run consistency
privacy
```

---

## 17.2 Frontend smoke tests

Every page must load with generated fixture data.

At minimum verify:

```text
manifest loads
DuckDB initializes
Parquet files query
charts render
filters work
empty recommendations work
```

---

## 17.3 End-to-end build test

Run:

```text
pipeline outputs
      ↓
build_web_bundle()
      ↓
quarto render
```

Then verify `_site/`.

---

# 18. Fixture Strategy

Do not make frontend development dependent on calling ESPN.

Keep a small deterministic fixture:

```text
tests/fixtures/web_bundle/
```

Containing a representative run with:

```text
14 teams
7 matchups
rosters

forecast players

at least:
1 lineup recommendation
1 waiver recommendation
1 trade recommendation

1 OUT player
single/sparse/ensemble examples
```

This allows stable UI development and screenshot regression later.

---

# 19. Claude Code Working Rules

When implementing this plan:

### MUST

* inspect existing R functions before writing equivalent logic;
* reuse decision engine outputs;
* follow `WEB_DATA_CONTRACT.md`;
* keep every milestone runnable;
* validate bundle after schema changes;
* use semantic names;
* keep frontend analytical logic simple;
* preserve `run_id` traceability.

### MUST NOT

* silently change simulation semantics;
* recompute recommendations in JavaScript;
* independently resolve ESPN↔FFA IDs;
* hard-code roster slots when the ESPN definitions exist;
* assume every recommendation table has rows;
* assume optimal win probability always improves;
* ignore trade `partner_is_my_opponent`;
* directly consume `historic/` from the frontend.

Historical data has known schema and type drift and should be normalized before reaching the web layer.

---

# 20. Recommended Implementation Sequence for Claude Code

Execute work in this exact order:

```text
STEP 1
Read:
ARCHITECTURE.md
WEB_DATA_CONTRACT.md
DATA_CATALOG.md

STEP 2
Inspect:
decision pipeline
league state
lineup optimizer
roster evaluator
free agents
trades

STEP 3
Implement:
resolve_run()

STEP 4
Implement:
manifest
runs
dimensions
forecasts

STEP 5
Implement:
matchups
rosters
lineup
waivers
trades

STEP 6
Implement:
bundle validation

STEP 7
Generate real bundle

STEP 8
Scaffold Quarto application

STEP 9
Implement global state/data access

STEP 10
Implement Command Center

STEP 11
Implement Matchup

STEP 12
Implement Lineup

STEP 13
Implement Waivers

STEP 14
Implement Trades

STEP 15
Implement League

STEP 16
Implement Players

STEP 17
Implement Projection Lab

STEP 18
Implement Data Health

STEP 19
Responsive/polish

STEP 20
Static build + deployment
```

---

# 21. MVP Success Criteria

The MVP is considered successful when a manager can open the cockpit and, without understanding the underlying R pipeline, answer within approximately one minute:

```text
1. What is happening this week?

2. What is my probability of winning?

3. What is the plausible scoring range?

4. Is my lineup optimal?

5. Which substitutions should I make?

6. Who should I add/drop?

7. What trades are attractive and mutually reasonable?

8. How strong is my roster relative to the league?

9. Which players offer the best expectation/upside?

10. How reliable are the underlying projections?
```

---

# 22. MVP Boundary

The MVP consists of:

```text
DATA LAYER

manifest
runs
teams
players
standings
rosters
forecasts
matchups
lineup evaluation
lineup recommendations
waiver recommendations
trade recommendations
projection sources
source accuracy
data health
```

plus:

```text
UI

Command Center
Matchup Center
Lineup Lab
Waiver Center
Trade Center
League Analyzer
Player Explorer
Projection Lab
Data Health
```

Everything else is incremental evolution.

---

# 23. Final Architectural Constraint

Before adding any new service or infrastructure component, answer:

> Can this capability be computed by the existing R pipeline, persisted as a compact analytical artifact and rendered statically?

If the answer is **yes**, keep it static.

The desired long-term property is:

```text
R analytics
     ↓
small immutable web bundle
     ↓
static analytical application
```

rather than:

```text
browser
     ↓
API
     ↓
application server
     ↓
database
     ↓
analytics service
```

unless future requirements genuinely require that complexity.

---

# 24. Implementation North Star

The project should continuously preserve:

```text
git clone
+
available .rds data
+
build_web_bundle()
+
quarto render
=
complete analytical cockpit
```

The key separation remains:

> **R computes.
> Parquet contracts.
> DuckDB queries.
> Plotly communicates.
> Quarto ships.**
