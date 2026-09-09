# WEB_DATA_CONTRACT.md

## 1. Purpose

Este documento define o contrato de dados entre:

```text
R Analytics / Decision Engine
            ↓
      Web Data Bundle
            ↓
       Static Web App
```

O objetivo é impedir que o frontend precise conhecer:

* objetos `dm`;
* arquivos `.rds`;
* relações internas entre databases;
* regras de ESPN ↔ FFA mapping;
* seleção de snapshots;
* algoritmos de Monte Carlo;
* otimização de lineup;
* regras de waiver;
* regras de trade.

Toda lógica analítica deve permanecer em **R**.

O frontend recebe datasets tabulares, estáveis e explicitamente versionados.

---

# 2. Architectural Contract

A fronteira arquitetural é:

```text
RDS / dm
   ↓
R transformations
   ↓
Presentation Marts
   ↓
Parquet / JSON
   ↓
DuckDB-Wasm
   ↓
Visualization
```

Regra fundamental:

> **O Web Data Bundle deve representar conceitos da interface, não a estrutura interna do banco analítico.**

Exemplo:

```text
BAD

frontend
   ↓
espn_rosters
JOIN espn_players
JOIN player_ids
JOIN player_forecasts
JOIN injury_status
```

Preferir:

```text
GOOD

rosters.parquet
   ↓
frontend
```

---

# 3. Source of Truth

Os arquivos `.rds` permanecem como fonte canônica.

Principais fontes:

```text
ffa_db.rds
espn_db.rds
analytical_db.rds
decision_db.rds
```

`ffa_db` contém player master, projeções consolidadas e projeções individuais por fonte.

`espn_db` contém configuração da liga, times, jogadores, standings, injuries, rosters, matchups e draft.

`analytical_db` contém histórico de projeções, realizado, erros das fontes e consenso histórico.

`decision_db` contém runs, forecasts probabilísticos, matchup simulations, avaliação de lineup e recomendações de lineup, free agents e trades.

---

# 4. Bundle Location

```text
web/
└── data/
    ├── manifest.json
    ├── runs.parquet
    │
    ├── dimensions/
    │   ├── teams.parquet
    │   ├── players.parquet
    │   └── roster_slots.parquet
    │
    ├── current/
    │   ├── standings.parquet
    │   ├── rosters.parquet
    │   ├── forecasts.parquet
    │   ├── matchups.parquet
    │   ├── lineup_evaluations.parquet
    │   ├── lineup_recommendations.parquet
    │   ├── free_agents.parquet
    │   ├── waiver_recommendations.parquet
    │   ├── trade_recommendations.parquet
    │   └── data_health.parquet
    │
    ├── projections/
    │   ├── source_projections.parquet
    │   └── source_accuracy.parquet
    │
    ├── history/
    │   ├── player_points.parquet
    │   └── consensus_history.parquet
    │
    └── draft/
        └── draft.parquet
```

Future optional marts:

```text
current/run_changes.parquet
current/matchup_distribution_bins.parquet

season/
├── season_simulations.parquet
└── playoff_probabilities.parquet
```

---

# 5. Data Types

Parquet types should be predictable across builds.

## Identifiers

**All identifiers exported to web MUST be strings.**

Examples:

```text
team_id
player_id
ffa_id
espn_id
nfl_id
run_id
matchup_id
owner_id
```

Reason:

* eliminates JS integer precision issues;
* avoids type drift;
* simplifies joins DuckDB/JavaScript;
* ESPN/FFA/NFL IDs are identifiers, not measures.

---

## Numeric measures

Use:

```text
double
```

for:

```text
projection
sim_mean
sim_sd
points
probabilities
quantiles
delta_expected
MAE
RMSE
bias
```

---

## Integers

Use integer for:

```text
season
week
rank
n_sources
recommendation_rank
n_sim
n_substitutions
residual_pool_n
```

---

## Boolean

Use:

```text
boolean
```

for:

```text
is_starter
is_bench
is_ir
injured
active
is_optimal_starter
partner_is_my_opponent
```

---

## Missing values

R:

```text
NA
```

must become:

```text
Parquet NULL
```

Never export:

```text
"NA"
"NULL"
"null"
""
```

to represent missing numerical values.

---

# 6. Naming Convention

All exported columns:

```text
snake_case
```

Use ESPN terminology consistently for:

```text
team_id
player_id
lineup_slot_id
```

Use:

```text
ffa_id
```

explicitly when referencing FFA identity.

Avoid ambiguous fields such as:

```text
id
name
value
points_x
points_y
```

Prefer:

```text
player_name
team_name
actual_points
projected_points
```

---

# 7. Snapshot Consistency

## Critical rule

Datasets under:

```text
current/
```

MUST represent the **same decision run**.

Never combine:

```text
latest ESPN snapshot
+
latest FFA snapshot
+
some previous decision run
```

Use `decision_db$simulation_runs` as the synchronization point.

`simulation_runs` registra `season`, `week`, `tag`, `ffa_timestamp`, `espn_timestamp`, modelo, número de simulações e seed.

Therefore:

```text
selected run_id
      ↓
simulation_runs
      ↓
ffa_timestamp
espn_timestamp
season/week/tag
      ↓
all current marts
```

---

# 8. Current Run

Default selection:

```text
maximum(created_at)
```

unless explicitly supplied:

```r
build_web_bundle(
  run_id = "..."
)
```

Recommended function:

```r
build_web_bundle(
  run_id = NULL,
  output_dir = "web/data",
  privacy = c("private", "public")
)
```

`run_id = NULL` means most recent valid run.

---

# 9. manifest.json

## Purpose

Small bootstrap file loaded before any Parquet.

### Contract

```json
{
  "schema_version": "1.0.0",
  "generated_at": "2026-09-09T10:30:00Z",

  "current": {
    "run_id": "2026-W01-preview-20260908T161947",
    "season": 2026,
    "week": 1,
    "tag": "preview",

    "model_version": "player-mc-v2",
    "n_sim": 10000,

    "created_at": "2026-09-08T16:19:47Z",
    "ffa_timestamp": "...",
    "espn_timestamp": "..."
  },

  "datasets": {
    "teams": "dimensions/teams.parquet",
    "players": "dimensions/players.parquet",
    "rosters": "current/rosters.parquet",
    "forecasts": "current/forecasts.parquet",
    "matchups": "current/matchups.parquet"
  },

  "privacy": "private"
}
```

The frontend MUST use the manifest rather than hard-code dataset paths or current week.

---

# 10. runs.parquet

## Grain

```text
1 row = 1 decision engine run
```

## Source

```text
decision_db$simulation_runs
```

The decision database intentionally accumulates runs through `dm_rows_upsert`, making this table the natural run selector.

## Logical PK

```text
run_id
```

## Required columns

| column         | type      |
| -------------- | --------- |
| run_id         | string    |
| created_at     | timestamp |
| season         | integer   |
| week           | integer   |
| tag            | string    |
| ffa_timestamp  | timestamp |
| espn_timestamp | timestamp |
| model_version  | string    |
| n_sim          | integer   |
| seed           | integer   |
| is_current     | boolean   |

`is_current` is presentation-derived.

Exactly one row SHOULD have:

```text
is_current = TRUE
```

---

# 11. dimensions/teams.parquet

## Grain

```text
1 row = 1 fantasy team / season
```

## Primary Source

```text
espn_db$espn_teams
```

`espn_teams` contains `team_name`, abbreviation, division and ownership information.

## Logical PK

```text
season + team_id
```

## Contract

| column         | nullable | origin               |
| -------------- | -------: | -------------------- |
| season         |       no | ESPN                 |
| team_id        |       no | ESPN                 |
| team_name      |       no | ESPN                 |
| abbrev         |      yes | ESPN                 |
| division_id    |      yes | ESPN                 |
| owner_name     |      yes | derived ESPN members |
| is_my_team     |       no | presentation         |
| team_image_url |      yes | if available         |

### Privacy

When:

```text
privacy = public
```

`owner_name` SHOULD be omitted or anonymized.

---

# 12. dimensions/players.parquet

## Grain

```text
1 row = 1 ESPN player / season
```

## Sources

```text
espn_players
ffa_player_ids
ffa_players
```

The FFA crosswalk contains ESPN, NFL and other provider IDs.

## Logical PK

```text
season + player_id
```

## Contract

| column      | nullable |
| ----------- | -------: |
| season      |       no |
| player_id   |       no |
| ffa_id      |      yes |
| nfl_id      |      yes |
| player_name |       no |
| position    |      yes |
| nfl_team    |      yes |

Optional:

```text
first_name
last_name
age
experience
bye_week
```

Do not export unused provider IDs unless required by a screen.

---

# 13. dimensions/roster_slots.parquet

## Grain

```text
1 row = 1 lineup slot definition
```

## Source

```text
espn_roster_slots
```

The source describes `lineup_slot_id`, label and slot count.

## Contract

```text
season
lineup_slot_id
slot_label
slot_count
```

---

# 14. current/forecasts.parquet

This is one of the main frontend datasets.

## Grain

```text
1 row =
1 player forecast
for 1 decision run
```

## Source

```text
decision_db$player_forecasts
```

`player_forecasts` already contains projection consensus, Monte Carlo statistics, quantiles, threshold probabilities and residual-pool diagnostics.

## Logical PK

```text
run_id + ffa_id + position
```

## Contract

```text
run_id
season
week
tag

ffa_id
espn_id
player_name
position
nfl_team

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

residual_pool_level
residual_pool_n
```

## Derived display field

Optional:

```text
historical_bias = sim_mean - projection
```

This is a presentation-derived metric, not a new model result.

---

# 15. current/standings.parquet

## Grain

```text
1 row = 1 fantasy team
at selected ESPN snapshot
```

## Source

```text
espn_team_standings
```

The source contains rank, W-L-T, points for/against, streak and transaction counts.

## Selection

Filter exactly by:

```text
season
week
tag
espn_timestamp
```

resolved from current `run_id`.

## Logical PK

```text
run_id + team_id
```

## Required fields

```text
run_id
season
week

team_id
team_name

rank

wins
losses
ties

points_for
points_against

streak
```

Additional transaction statistics may be exported when present.

---

# 16. current/rosters.parquet

## Grain

```text
1 row =
1 rostered player
for 1 fantasy team
for current decision run
```

## Sources

```text
espn_rosters
espn_players
espn_player_injury_status
player_forecasts
lineup recommendations / optimal lineup
```

`espn_rosters` already identifies starter, bench and IR state.

## Logical PK

```text
run_id + team_id + player_id
```

## Required columns

```text
run_id
season
week

team_id
team_name

player_id
ffa_id
player_name
position
nfl_team

lineup_slot_id
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
optimal_slot

bridge_method
```

---

## Mapping Rule

Do NOT implement ESPN → FFA mapping again inside `build_web_bundle.R`.

Reuse the mapping implementation from:

```text
R/decision/league_state.R
```

The decision engine already applies four strategies in cascade and records `bridge_method`; unmapped starters cause the run to fail.

If needed, expose that existing mapping function as a reusable R helper.

---

# 17. current/matchups.parquet

## Grain

```text
1 row = 1 league matchup
```

## Source

```text
decision_db$matchup_simulations
```

The decision engine already calculates expected scores, P10/P50/P90 and win/tie probabilities.

## Logical PK

```text
run_id + matchup_id
```

## Contract

```text
run_id
season
week
tag

matchup_id

home_team_id
home_team_name

away_team_id
away_team_name

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

is_my_matchup
```

`is_my_matchup` is presentation-derived.

Validation:

```text
home_win_probability
+ away_win_probability
+ tie_probability
≈ 1
```

Tolerance:

```text
1e-6
```

---

# 18. current/lineup_evaluations.parquet

## Grain

```text
1 row = 1 fantasy team
```

## Source

```text
decision_db$lineup_evaluations
```

The source compares current ESPN lineup against optimized lineup and includes bench value and number of substitutions.

## Logical PK

```text
run_id + team_id
```

## Contract

```text
run_id
season
week
tag

team_id
team_name
opponent_team_id
opponent_team_name

current_expected
current_p10
current_p50
current_p90
current_win_probability

optimal_expected
optimal_p10
optimal_p50
optimal_p90
optimal_win_probability

bench_value
n_substitutions
```

Derived:

```text
delta_expected =
optimal_expected - current_expected

delta_win_probability =
optimal_win_probability - current_win_probability
```

Important:

Do NOT assume:

```text
optimal_win_probability >= current_win_probability
```

The source explicitly documents that this is not guaranteed.

---

# 19. current/lineup_recommendations.parquet

## Grain

```text
1 row = 1 recommended lineup substitution
```

No rows means the current team can already be optimal.

## Source

```text
decision_db$lineup_recommendations
```

## Logical PK

```text
run_id + team_id + player_out
```

## Contract

```text
run_id
season
week
tag

team_id
team_name

player_out_id
player_out_name
player_out_position

player_in_id
player_in_name
player_in_position

slot

current_expected
optimized_expected
delta_expected

current_win_probability
optimized_win_probability
delta_win_probability

recommendation_rank
```

The decision engine excludes IR and `OUT` players from lineup candidates.

Frontend MUST NOT re-evaluate eligibility.

---

# 20. current/free_agents.parquet

This dataset does not exist directly in `decision_db`.

It is a **presentation-derived mart**, but MUST reproduce the same free-agent universe used by the decision engine.

## Grain

```text
1 row = 1 currently available fantasy player
```

## Source Logic

Following the documented decision-engine definition:

```text
espn_players

ANTI JOIN

current espn_rosters

then:

ESPN → FFA bridge

then:

forecast availability

then:

exclude IR / inactive
```

This matches the free-agent definition documented for M4.

## Contract

```text
run_id

player_id
ffa_id

player_name
position
nfl_team

injury_status

projection
sim_mean
sim_sd

p10
p50
p90

prob_gt_10
prob_gt_15
prob_gt_20
prob_gt_25

n_sources
coverage_class

percent_owned
percent_started
```

`percent_owned` and `percent_started` may be nullable depending on ESPN availability.

---

# 21. current/waiver_recommendations.parquet

## Grain

```text
1 row = 1 recommended ADD/DROP
```

## Source

```text
decision_db$free_agent_recommendations
```

## Logical PK

```text
run_id
+ team_id
+ drop_player_id
+ add_player_id
```

## Contract

```text
run_id
season
week
tag

team_id

drop_player_id
drop_ffa_id
drop_player_name
drop_position

add_player_id
add_ffa_id
add_player_name
add_position

before_expected
after_expected
delta_expected

before_win_probability
after_win_probability
delta_win_probability

recommendation_rank
```

The ranking MUST preserve the decision-engine ordering:

```text
delta_expected DESC
```

Do not rerank by win probability.

The source explicitly states that `delta_win_probability` is reported but is not the ranking criterion.

---

# 22. current/trade_recommendations.parquet

## Grain

```text
1 row = 1 proposed 1×1 trade
```

## Source

```text
decision_db$trade_recommendations
```

## Logical PK

```text
run_id
+ my_team_id
+ other_team_id
+ give_player_id
+ receive_player_id
```

The table now carries recommendations for every team; `recommendation_rank`
restarts at 1 per `my_team_id`. The frontend filters to the selected team.

## Contract

```text
run_id
season
week
tag

my_team_id
my_team_name

other_team_id
other_team_name

give_player_id
give_ffa_id
give_player_name
give_position

receive_player_id
receive_ffa_id
receive_player_name
receive_position

my_before_expected
my_after_expected
my_delta_expected

their_before_expected
their_after_expected
their_delta_expected

my_before_win_probability
my_after_win_probability
my_delta_win_probability

fairness
trade_score

partner_is_my_opponent

recommendation_rank
```

Semantics:

```text
fairness =
-abs(my_delta_expected - their_delta_expected)
```

```text
trade_score =
my_delta_expected +
min(my_delta_expected, their_delta_expected)
```

These definitions come directly from the decision-engine catalog.

## UI warning

When:

```text
partner_is_my_opponent = TRUE
```

the frontend MUST show a warning that matchup win-probability impact can be optimistic.

This limitation is explicitly documented in the source.

---

# 23. projections/source_projections.parquet

## Purpose

Support Player Explorer and Projection Lab.

## Grain

```text
1 row =
1 player
× 1 projection source
× current run
```

## Source

```text
ffa_proj_source_points
```

The source dataset contains projection points by `data_src` for each player/snapshot.

## Snapshot

Use `simulation_runs$ffa_timestamp`.

Do NOT independently select:

```text
max(timestamp)
```

## Contract

```text
run_id

ffa_id
espn_id

player_name
position
nfl_team

data_src
projected_points
```

Logical PK:

```text
run_id + ffa_id + position + data_src
```

---

# 24. projections/source_accuracy.parquet

## Grain

```text
1 row =
projection source
× position
× season
```

## Source

```text
analytical_db$source_errors
```

The source already provides:

```text
bias
mae
rmse
n
```

for seasons 2020–2025.

## Contract

```text
season
data_src
position

bias
mae
rmse
n
```

Logical PK:

```text
season + data_src + position
```

No recalculation is required for v1.

---

# 25. history/player_points.parquet

## Grain

```text
1 row =
1 player
× season
× week
```

## Source

```text
analytical_db$nfl_player_points
```

The source already stores actual fantasy points by player/week.

## Contract

```text
nfl_id
ffa_id
espn_id

season
week

actual_points
```

Important:

```text
week == 0
```

means season aggregate, not a real NFL week.

Frontend charts of weekly performance SHOULD default to:

```text
week > 0
```

---

# 26. history/consensus_history.parquet

## Grain

```text
1 row =
1 player
× season
× week
```

## Source

```text
analytical_db$consensus_error_history
```

The source already contains projection, actual points, residual/error, source dispersion and coverage class.

## Contract

```text
season
week

ffa_id
nfl_id
espn_id

position

projection

n_sources
coverage_class

source_median
source_sd
source_mad
source_min
source_max
source_range

actual_points

residual
abs_residual
squared_residual

consensus_type
```

This mart supports:

* projection × actual;
* model error history;
* uncertainty analysis;
* coverage analysis;
* calibration research.

---

# 27. draft/draft.parquet

## Grain

```text
1 row = 1 draft selection
```

## Sources

```text
espn_draft
espn_teams
espn_players
```

`espn_draft` contains overall pick, round, round pick, team and player.

## Contract

```text
season

overall_pick
round
round_pick

team_id
team_name

player_id
player_name
position
nfl_team

bid_amount
keeper
trade_locked
```

Nullable values should follow ESPN source availability.

---

# 28. current/data_health.parquet

This is a presentation-derived diagnostic mart.

## Grain

```text
1 row = current run
```

## Contract

```text
run_id
generated_at

ffa_timestamp
espn_timestamp
decision_timestamp

n_forecast_players
n_rostered_players
n_starters

n_mapped_players
n_mapped_starters
n_unmapped_players

n_ensemble
n_sparse
n_single

pct_ensemble
pct_sparse
pct_single

model_version
n_sim

status
```

Recommended:

```text
status ∈
healthy
warning
error
```

Example rules:

```text
error:
unmapped starter > 0

warning:
forecast coverage < expected threshold

healthy:
all mandatory validation passed
```

The underlying decision pipeline already treats unmapped/missing-forecast starters as fatal conditions.

---

# 29. Optional v1.1 — run_changes.parquet

Supports:

```text
"What changed since last run?"
```

## Grain

```text
1 row = 1 material change
between current run and previous run
```

Suggested contract:

```text
current_run_id
previous_run_id

change_type

entity_type
entity_id
entity_name

metric

previous_value
current_value
delta

importance
```

Possible:

```text
change_type =
forecast_change
win_probability_change
injury_change
new_lineup_recommendation
new_waiver_recommendation
new_trade_recommendation
```

This is a presentation feature, not a new model.

---

# 30. Optional v1.1 — matchup_distribution_bins.parquet

The decision engine intentionally does not persist the individual Monte Carlo draws.

Do NOT change that merely for visualization.

Instead generate compact histogram bins before discarding draws.

## Contract

```text
run_id
matchup_id
team_id

bin_index
bin_min
bin_max

count
probability
```

Suggested:

```text
30–50 bins / team
```

This supports density/histogram visualizations with negligible storage.

---

# 31. Future — season_simulations.parquet

Not available in the current source model.

This dataset MUST NOT be fabricated from existing weekly simulation outputs.

It requires a future Season Simulator.

Proposed contract:

```text
run_id
team_id

expected_wins

p10_wins
p25_wins
p50_wins
p75_wins
p90_wins

playoff_probability
bye_probability
championship_probability
```

---

# 32. Data Validation

Implement:

```text
R/web/validate_web_bundle.R
```

The build MUST fail when mandatory validations fail.

---

## 32.1 Manifest

Validate:

```text
schema_version exists

current.run_id exists in runs.parquet

all manifest dataset paths exist
```

---

## 32.2 Referential integrity

Validate logical references such as:

```text
rosters.team_id
    ∈ teams.team_id

rosters.player_id
    ∈ players.player_id

matchups.home_team_id
    ∈ teams.team_id

matchups.away_team_id
    ∈ teams.team_id
```

---

## 32.3 Run consistency

Every `current/*` dataset containing `run_id` MUST contain exactly:

```text
manifest$current$run_id
```

unless the specific dataset is intentionally multi-run.

---

## 32.4 Unique grains

Assert uniqueness of each logical PK.

Examples:

```text
forecasts:
run_id + ffa_id + position

matchups:
run_id + matchup_id

lineup_evaluations:
run_id + team_id
```

---

## 32.5 Probability checks

All probabilities:

```text
0 <= p <= 1
```

Matchups:

```text
home_win_probability
+ away_win_probability
+ tie_probability
≈ 1
```

---

## 32.6 Quantile monotonicity

For forecasts:

```text
p05 <=
p10 <=
p25 <=
p50 <=
p75 <=
p90 <=
p95
```

Failure indicates invalid model output or export corruption.

---

## 32.7 Coverage class

Allowed:

```text
single
sparse
ensemble
```

Historical semantics are:

```text
single   = 1 source
sparse   = 2–3 sources
ensemble = 4+ sources
```

as defined by `consensus_error_history`.

---

# 33. Schema Versioning

`manifest.json` MUST contain:

```text
schema_version
```

Use semantic versioning.

Example:

```text
1.0.0
```

Rules:

### Patch

```text
1.0.0 → 1.0.1
```

Data bug fixes without contract changes.

### Minor

```text
1.0 → 1.1
```

Backward-compatible new:

* columns;
* datasets;
* optional fields.

### Major

```text
1.x → 2.0
```

Breaking:

* renamed columns;
* removed columns;
* changed semantics;
* changed grains.

Frontend MUST refuse unsupported major versions.

---

# 34. No List Columns

Web presentation marts MUST NOT contain R list-columns.

This is especially important because the source datasets contain list-columns in raw scrape, recap and simulation objects.

Any required nested information should be:

1. flattened;
2. normalized into another Parquet;
3. or exported as explicit JSON.

Do not serialize arbitrary R structures into Parquet columns.

---

# 35. Historic Data Caveats

The export layer must isolate the frontend from known historical schema drift.

The catalog documents:

* missing PK/FK in merged `historic/`;
* type drift;
* incomplete weeks;
* differences in historical schemas;
* incomplete 2021 projection coverage;
* stale historical simulation data.

Therefore:

> Frontend code MUST NOT read directly from `historic/`.

All normalization belongs in:

```text
analytical_db
```

or the Web Presentation Layer.

---

# 36. Privacy Modes

Supported:

```text
private
public
```

## private

May expose:

```text
team names
manager display names
```

## public

Must remove or anonymize:

```text
manager real names
owner/member IDs
internal identifiers not required by UI
```

Never export:

```text
authentication cookies
ESPN credentials
API tokens
raw authenticated responses
```

---

# 37. Build Implementation

Recommended entrypoint:

```r
build_web_bundle <- function(
  run_id = NULL,
  output_dir = "web/data",
  privacy = c("private", "public"),
  validate = TRUE
) {
  ...
}
```

Suggested orchestration:

```text
resolve_run()
     ↓
load_sources()
     ↓
build_dimensions()
     ↓
build_current_state()
     ↓
build_projection_views()
     ↓
build_history()
     ↓
build_draft()
     ↓
build_data_health()
     ↓
write_parquet()
     ↓
write_manifest()
     ↓
validate_web_bundle()
```

---

# 38. Recommended R Module Layout

```text
R/web/

build_web_bundle.R

bundle/
├── manifest.R
├── runs.R
├── dimensions.R
├── current_state.R
├── forecasts.R
├── matchups.R
├── lineup.R
├── free_agents.R
├── trades.R
├── projections.R
├── history.R
├── draft.R
└── data_health.R

utils/
├── schema.R
├── privacy.R
├── parquet.R
└── validation.R
```

Reuse existing decision-engine functions whenever possible.

Do not clone business logic into `R/web/`.

---

# 39. Frontend Rule

The following operations are allowed in DuckDB-Wasm:

```text
filter
sort
group
simple ranking
simple aggregation
pivot
search
```

Examples:

```sql
SELECT *
FROM forecasts
WHERE position = 'WR'
ORDER BY sim_mean DESC
```

Allowed.

---

The following are NOT frontend responsibilities:

```text
Monte Carlo simulation
ESPN ↔ FFA entity resolution
lineup optimization
waiver candidate generation
trade generation
historical residual sampling
projection model calculation
```

These must remain in R.

---

# 40. Minimum Bundle for MVP

The MVP may initially ship only:

```text
manifest.json
runs.parquet

dimensions/
    teams
    players

current/
    standings
    rosters
    forecasts
    matchups
    lineup_evaluations
    lineup_recommendations
    free_agents
    waiver_recommendations
    trade_recommendations

projections/
    source_projections
    source_accuracy
```

This is sufficient for:

```text
Command Center
Matchup Center
Lineup Lab
Waiver Center
Trade Center
League Analyzer
Player Explorer
Projection Lab
```

Historical and draft marts can follow without changing the core architecture.

---

# 41. Definition of Done

`WEB_DATA_CONTRACT v1.0` is implemented when:

* `build_web_bundle.R` builds the bundle from existing `.rds`;
* every current mart references one consistent `run_id`;
* no frontend join requires knowledge of the original `dm`;
* no web file contains R list-columns;
* all identifiers are normalized to strings;
* all logical PKs pass uniqueness validation;
* probabilities and quantiles pass consistency checks;
* roster player mapping reuses the existing decision-engine bridge;
* public/private export modes are supported;
* `manifest.json` exposes schema and run metadata;
* the generated directory can be copied to another machine and consumed without R;
* the frontend requires no ESPN/API access;
* failed validation prevents publication.

---

# 42. Core Design Principle

The contract deliberately creates three independent concerns:

```text
DOMAIN MODEL
RDS / dm
rich relational representation

        ↓

PRESENTATION MODEL
Parquet
screen-oriented analytical marts

        ↓

INTERACTION MODEL
DuckDB-Wasm / JavaScript
filtering + visualization
```

Do not collapse these layers.

The expected architecture is:

> **R owns meaning and decisions.
> The Web Data Bundle owns the stable interface.
> The browser owns interaction and visualization.**
