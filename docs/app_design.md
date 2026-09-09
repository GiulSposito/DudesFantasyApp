Analisei principalmente a página atual de **Fantasy Football**, a home do Sleeper e exemplos oficiais da interface web/mobile. A versão 2026 reforça uma identidade **dark-first, muito orientada a dados, com navy quase preto + cyan elétrico**, cards densos e uma mistura de dashboard esportivo com produto social. A própria Sleeper diz que design é colocado no centro das decisões do produto e destaca chat, pesquisa de jogadores e informação em tempo real como partes essenciais da experiência. ([Sleeper][1])

![Image](https://images.openai.com/static-rsc-4/AiDMP3fDI7sImPVW5XfAzUQW3LEhbEp9tjUGiSpZ9yH1IzYVohksIvFbRMXH6JsvTPzXQ0NooDTBRegJturDNGAI9p8vkunq2iuz8dgsonpsAZEF3kEBC0EVx2EtclpJGWYdk_Im8mqGhZebN9fzkQVVKhVeP3r5dqBpPZ9Dxa3GgJ-9tcw_s10dJ6xJfEvw?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/jyoOKw2VNjrODt7WgbOlFHbhxPXT_W3L12AsCwwuSZaC6c3NNvX9_2sJeTFu6_9fH_adcvdc7bcS4Vsnh_6BA8Wc66nx_a1YY1raAASnKNUk49aTW5t5TzQTSa3vADKMH9xYGMsoL9_mZAx2GmtP6qcRWSRB0GJ6kkQy7DA6A2ddwJ_ZP_3JXpDvOe2y03G1?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/Rc2dj9XvFrpdkAOvpRw0orZ6Aqkq_Pu_BYk0IUHtZOqy4cRfwasJoqILMoj5qUgaW9vxqAg44oMzvIWEkpVK1tgpP8ODYW1juklbItpW6tiIjylGUtc2tlnAA0bJvCAJGaLCZnHe6unrWe8z2cyfPaFy-JvILNrb_gJQDViIid0kyEhhBU1WqZAT6X-umStQ?purpose=fullsize)

Há também uma análise automatizada independente do site atual que identifica **Poppins + Inter**, fundo `#050921`, cyan `#00FFF9` e uma hierarquia de superfícies navy. Como isso não é um brand book oficial da Sleeper, eu trataria esses valores como **design tokens reverse-engineered**, não como especificação oficial da marca. ([Sokosumi][2])

Abaixo está um guideline já estruturado para você colocar, por exemplo, em `DESIGN.md` e passar para Claude Code.

````markdown
# Design Guideline — Fantasy Sports UI
## Inspired by Sleeper

Version: 1.0
Purpose: Design system for fantasy sports, sports analytics, draft tools,
league dashboards and data-rich web applications.

---

# 1. Design Philosophy

The interface should feel like a modern fantasy sports control center.

Primary characteristics:

- dark-first
- data-dense but readable
- fast and responsive
- competitive
- social
- slightly futuristic
- colorful only where color conveys meaning
- minimal decoration
- strong visual hierarchy
- optimized for dashboards, rankings, players and live events

The experience should resemble a combination of:

- sports dashboard
- trading terminal
- gaming interface
- social application
- real-time analytics tool

Avoid making the application look like:

- a corporate dashboard
- a generic Bootstrap admin panel
- a casino interface
- a neon cyberpunk UI
- an ESPN clone

Color should be used mainly to communicate:

- state
- position
- rank
- action
- urgency
- selection
- performance

---

# 2. Core Visual Principle

Use a very dark navy environment as the visual canvas.

Bright cyan is the primary interaction color.

Most UI surfaces should remain neutral.

Recommended approximate visual balance:

80–88%  dark neutral surfaces
8–15%   text / borders / secondary surfaces
3–5%    primary accent colors

Do NOT flood the screen with cyan.

The accent should attract attention specifically to:

- active tabs
- primary CTAs
- selected players
- current user
- focus states
- live states
- key statistics

---

# 3. Color System

## 3.1 Core palette

```css
:root {

  /* Base canvas */

  --bg-deepest: #020409;
  --bg-page: #050921;
  --bg-subtle: #0A0F2A;

  /* Surfaces */

  --surface-1: #0A0F2A;
  --surface-2: #131B38;
  --surface-3: #1A2447;
  --surface-4: #242D52;

  /* Brand / interaction */

  --accent-primary: #00FFF9;
  --accent-primary-strong: #00D7FF;
  --accent-primary-muted: #00CEB8;

  /* Secondary accents */

  --accent-blue: #3860BE;
  --accent-blue-bright: #00BAFF;

  /* Text */

  --text-primary: #FFFFFF;
  --text-secondary: #D8D8D8;
  --text-muted: #9298AE;
  --text-disabled: #62687A;

  /* Borders */

  --border-subtle: #252D4A;
  --border-default: #343855;
  --border-strong: #4C5579;

  /* Semantic */

  --success: #28E757;
  --warning: #FFAE58;
  --danger: #FF5B6E;
  --info: #00BAFF;

}
````

---

# 4. Surface Hierarchy

Do not use one single dark background everywhere.

Create depth through slightly different navy values.

Recommended hierarchy:

PAGE
#050921

SIDEBAR / DEEPEST PANEL
#020409

CARD
#0A0F2A → #131B38

ELEVATED CARD
#1A2447

MODAL / FLOATING PANEL
#131B38 or #1A2447

SELECTED PANEL
#1A2447 + cyan border or glow

Example:

```css
.card {
  background: rgba(19, 27, 56, 0.72);
  border: 1px solid rgba(120, 130, 170, 0.18);
  border-radius: 10px;
}
```

Avoid large heavy drop shadows.

Depth should primarily come from:

* tonal surface differences
* thin borders
* subtle transparency
* restrained glow
* occasional backdrop blur

---

# 5. Typography

Recommended pairing:

## Display / Titles

Poppins

Weights:

600 — section headings
700 — hero headings
600 — navigation labels
600 — buttons

## Body / Data

Inter

Weights:

400 — body
500 — tables
600 — important values

Fallback:

```css
font-family:
  Inter,
  -apple-system,
  BlinkMacSystemFont,
  "Segoe UI",
  sans-serif;
```

---

# 6. Typography Scale

## Hero

```css
font-family: Poppins;
font-size: 56px;
font-weight: 700;
line-height: 1.05;
letter-spacing: -0.04em;
```

Desktop range:

48–64px

Mobile:

36–44px

---

## H1

40px / 600

## H2

28–32px / 600

## H3

20–22px / 600

## UI title

16–18px / 600

## Body

16px / 400
line-height: 1.5

## Dense data text

14px / 400–500

## Labels

12–14px / 600

## Metadata

11–12px / 500

Examples:

POSITION
WEEK 01
ROSTER %
START %
PROJECTED
ADP

Uppercase may be used for very small semantic labels.

---

# 7. Numbers

Fantasy sports applications contain many numerical values.

Numbers should therefore receive special treatment.

Recommended:

```css
font-variant-numeric: tabular-nums;
```

Use tabular numbers for:

* scores
* projected points
* rankings
* ADP
* percentages
* records
* draft positions
* timestamps

Primary metric:

24–32px
Inter 600

Secondary metric:

14–16px
Inter 500

Metadata:

11–12px
Inter 400

---

# 8. Spacing System

Use an 8px base grid.

```text
4px
8px
12px
16px
24px
32px
40px
48px
64px
80px
96px
```

Preferred tokens:

```css
--space-xs: 4px;
--space-sm: 8px;
--space-md: 12px;
--space-lg: 16px;
--space-xl: 24px;
--space-2xl: 40px;
--space-3xl: 64px;
```

Typical card padding:

16–24px

Dense player rows:

8–12px vertical

Dashboard column gutter:

16–24px

---

# 9. Border Radius

The Sleeper-inspired aesthetic combines relatively compact cards
with very rounded CTAs.

Recommended scale:

```css
--radius-xs: 4px;
--radius-sm: 6px;
--radius-md: 10px;
--radius-lg: 16px;
--radius-xl: 20px;
--radius-pill: 9999px;
```

Use:

Cards → 10–16px

Panels → 10px

Inputs → 6–8px

Badges → pill

Primary CTA → pill

Avoid excessive rounding on every component.

---

# 10. Layout

Desktop applications should favor a three-zone structure.

```text
┌─────────────────────────────────────────────────────┐
│ Top navigation                                      │
├────────────┬──────────────────────────┬──────────────┤
│ Navigation │ Main workspace           │ Context      │
│ / Leagues  │                          │ Chat / Info  │
│            │ Draft / Matchup / Team   │              │
└────────────┴──────────────────────────┴──────────────┘
```

Typical widths:

Left navigation:
72–240px

Main:
fluid

Right contextual panel:
280–380px

Maximum marketing-page content width:

~1280–1440px

Use a 12-column responsive grid.

---

# 11. Navigation

Navigation should be compact.

Active navigation:

* brighter text
* subtle dark-blue surface
* cyan indicator or icon

Example:

```css
.nav-item.active {
  background: rgba(0,255,249,.07);
  color: #FFFFFF;
}

.nav-item.active svg {
  color: #00FFF9;
}
```

Avoid large menu backgrounds.

The content itself should dominate the UI.

---

# 12. Tabs

Tabs are critical for sports applications.

Examples:

MATCHUP
TEAM
PLAYERS
LEAGUE
SCORES
CHAT

Inactive:

muted text

Active:

white text + cyan underline

```css
.tab {
  color: #9298AE;
}

.tab.active {
  color: #FFFFFF;
  border-bottom: 2px solid #00FFF9;
}
```

---

# 13. Buttons

## Primary CTA

Use for:

* Draft
* Add Player
* Submit
* Start League
* Save
* Confirm

```css
.button-primary {
  background: #00FFF9;
  color: #050921;

  min-height: 44px;

  padding: 0 24px;

  border-radius: 9999px;

  font-family: Poppins;
  font-size: 14px;
  font-weight: 600;

  border: 0;
}
```

Hover:

```css
background: #00D7FF;
transform: translateY(-1px);
```

---

## Secondary

Dark or blue surface.

```css
background: #1A2447;
color: white;
```

or

```css
background: #3860BE;
```

---

## Tertiary

Transparent.

```css
background: transparent;
color: #00FFF9;
```

---

# 14. Cards

Cards are one of the most important UI primitives.

Typical card anatomy:

```text
┌──────────────────────────────┐
│ LABEL                 ACTION │
│                              │
│ Primary information          │
│ Supporting information       │
│                              │
│ metadata      metric         │
└──────────────────────────────┘
```

Recommended:

```css
.card {
  background: rgba(19,27,56,.65);

  border:
    1px solid rgba(120,130,170,.16);

  border-radius: 10px;

  padding: 16px;
}
```

Hover:

```css
background: rgba(26,36,71,.8);
border-color: rgba(0,255,249,.20);
```

---

# 15. Player Rows

Player lists should be optimized for scanning.

Structure:

```text
[avatar]  Player Name       18.7
          WR · MIN          PROJ

          87% rostered
```

Example:

```text
─────────────────────────────────────
 JJ   Justin Jefferson          19.4
      WR · MIN                  PROJ
      99% rostered · 96% start
─────────────────────────────────────
```

Hierarchy:

PLAYER NAME
high contrast

POSITION / TEAM
smaller + colored

STATS
tabular numbers

SECONDARY INFO
muted

---

# 16. Position Colors

Fantasy football benefits from consistent positional colors.

Do not necessarily copy Sleeper's exact colors.

Recommended inspired palette:

```css
--pos-qb:  #F45B92;
--pos-rb:  #39C6B5;
--pos-wr:  #3DB5E6;
--pos-te:  #F0A65A;
--pos-k:   #A477E8;
--pos-dst: #6D85A6;
```

Use these colors mainly for:

* position badge
* draft board cells
* small left border
* tiny metadata highlight

Do not color entire large panels.

Example:

```text
[WR] Justin Jefferson
```

rather than a fully cyan player card.

---

# 17. Draft Board

The draft board can be visually richer than the rest of the interface.

Each pick tile can use the player's position color.

Example:

```text
┌──────────────┐
│ 1.07         │
│ Justin       │
│ Jefferson    │
│ WR · MIN     │
└──────────────┘
```

Important information:

Pick
Player
Position
Team
Manager
Round

Strongly emphasize:

CURRENT PICK

with cyan.

Example:

```css
.current-pick {
  outline: 2px solid #00FFF9;
  box-shadow:
    0 0 0 4px rgba(0,255,249,.08);
}
```

---

# 18. Tables

Tables should feel closer to a sports terminal than a spreadsheet.

Avoid:

* thick borders
* white table backgrounds
* excessive grid lines

Use:

```css
tr {
  border-bottom:
    1px solid rgba(255,255,255,.06);
}
```

Hover:

```css
tr:hover {
  background:
    rgba(0,255,249,.04);
}
```

Recommended row height:

44–52px

---

# 19. Ranking Tables

Preferred structure:

```text
RK  PLAYER             POS   PROJ   ADP   VALUE
01  Justin Jefferson   WR    19.4   4.2   +2.8
02  Ja'Marr Chase      WR    18.9   5.1   +2.1
03  Bijan Robinson     RB    18.3   6.4   +1.7
```

Highlight:

positive → green
negative → muted red
neutral → gray

Do not use saturated heatmap colors everywhere.

---

# 20. Badges

Examples:

```text
LIVE
QUESTIONABLE
OUT
ROOKIE
KEEPER
WAIVER
START
TRENDING
```

Badge:

```css
.badge {
  padding: 4px 8px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
}
```

Accent badge:

```css
background: rgba(0,255,249,.12);
color: #00FFF9;
```

---

# 21. Status Colors

SUCCESS

#28E757

WARNING / questionable

#FFAE58

ERROR / out

#FF5B6E

LIVE

#00FFF9

NEUTRAL

#9298AE

Use semantic colors sparingly.

---

# 22. Search and Inputs

Inputs should blend into the dashboard.

```css
.input {
  height: 44px;

  background:
    rgba(0,0,0,.20);

  border:
    1px solid #343855;

  color: white;

  border-radius: 8px;

  padding:
    0 14px;
}
```

Focus:

```css
border-color: #00FFF9;

box-shadow:
  0 0 0 3px rgba(0,255,249,.10);
```

---

# 23. Charts

Charts should match the UI rather than introduce a separate
visual language.

Background:

transparent

Grid:

rgba(255,255,255,.06)

Labels:

#9298AE

Primary series:

#00FFF9

Secondary:

#3860BE

Positive:

#28E757

Warning:

#FFAE58

Negative:

#FF5B6E

---

# 24. Sparklines

Use sparklines frequently for:

* projected points
* ranking movement
* ownership %
* utilization
* target share
* historical performance

Keep them small:

60–100px wide.

Do not display axes unless necessary.

---

# 25. Data Visualization Philosophy

Prefer:

* dot plots
* bars
* ranking tables
* slope charts
* sparklines
* small multiples
* compact distributions

Avoid:

* 3D charts
* decorative pie charts
* rainbow palettes
* giant legends
* unnecessary animations

---

# 26. Icons

Preferred icon style:

* outline
* geometric
* simple
* 1.5–2px stroke

Recommended libraries:

Lucide
Phosphor
Heroicons

Default:

18–20px

Navigation:

20–22px

Small metadata:

14–16px

---

# 27. Avatars

Player avatars and league avatars are important visual anchors.

Recommended:

Player image:
32–44px

User avatar:
28–36px

League avatar:
36–48px

Use circular masks.

Fantasy applications become visually monotonous without
player/team imagery.

---

# 28. Imagery

Images should usually represent:

* players
* teams
* leagues
* draft boards
* fantasy matchups

Avoid generic stock photography.

Marketing pages can use:

* floating UI screenshots
* device mockups
* app fragments
* player imagery
* layered dashboard compositions

---

# 29. Motion

Interaction should feel immediate.

Recommended durations:

hover:
120–160ms

tabs:
150ms

cards:
180–220ms

modals:
200–250ms

Avoid long animations.

Fantasy sports is a rapid interaction environment.

Use:

```css
transition:
  background-color 150ms ease-out,
  border-color 150ms ease-out,
  transform 150ms ease-out;
```

---

# 30. Live States

Live information should be visually distinct.

Example:

```text
● LIVE
Q3 · 08:42
```

Use a small pulsing indicator.

Do not animate entire cards.

```css
.live-dot {
  animation: pulse 1.8s infinite;
}
```

---

# 31. Empty States

Dark interfaces easily look unfinished when empty.

Use:

* simple illustration/icon
* clear headline
* one sentence
* single CTA

Example:

No players in your queue

Add players to quickly access them during the draft.

[ Browse Players ]

---

# 32. Loading States

Use skeletons instead of large spinners.

```css
background:
linear-gradient(
  90deg,
  #131B38,
  #1A2447,
  #131B38
);
```

Skeleton layout should approximate actual content.

---

# 33. Responsive Strategy

## Desktop

Multi-column dashboard.

## Tablet

Two columns.

Contextual panels become drawers.

## Mobile

Single column.

Use bottom navigation for the main application areas.

Example:

```text
LEAGUES
PLAYERS
SCORES
CHAT
PROFILE
```

Keep primary actions reachable with the thumb.

---

# 34. Marketing Website

The marketing site can be visually less dense than the actual app.

Recommended structure:

NAV

HERO
headline
subheadline
primary CTA
secondary CTA
app screenshot

SOCIAL PROOF

FEATURES

PRODUCT UI DEMOS

LEAGUE TYPES

DRAFT EXPERIENCE

STATS / TRUST

CTA

FOOTER

---

# 35. Hero

Preferred style:

Large, simple headline.

Example:

Fantasy,
done smarter.

or

Own your draft.

Large product screenshot below or beside it.

Avoid large abstract illustrations unrelated to the product.

The UI itself should be the hero image.

---

# 36. Marketing Background

Unlike the dashboard, marketing pages may alternate:

```text
near-black navy
↓
dark navy
↓
very light neutral section
↓
dark navy
```

This prevents an excessively heavy all-dark page.

If a light section is used:

Background:
#F7F9FC

Text:
#101426

Cards:
#FFFFFF

Accent remains cyan/teal.

---

# 37. Glass Effects

Use very subtle glass-like surfaces only on floating UI.

Example:

```css
.floating-panel {

  background:
    rgba(19,27,56,.72);

  backdrop-filter:
    blur(10px);

  border:
    1px solid rgba(255,255,255,.08);

}
```

Do not turn the entire site into glassmorphism.

---

# 38. Visual Density

Fantasy applications are naturally information dense.

Do not solve density by increasing whitespace excessively.

Instead use hierarchy:

font size
font weight
color
alignment
grouping
subtle dividers

A player row can contain many fields while remaining readable.

---

# 39. Voice

Interface copy should be:

* short
* direct
* energetic
* conversational
* sports-oriented

Prefer:

Add Player
Start Draft
View Matchup
Set Lineup
Trade
Watch
Queue

Avoid:

Proceed to Player Acquisition Process

or

Execute Draft Selection

---

# 40. Accessibility

Minimum contrast:

WCAG AA

Avoid relying solely on color for:

player status
position
win/loss
injury

Combine color + label/icon.

Example:

🔴 OUT

rather than a red dot alone.

Focus states must always be visible.

---

# 41. Recommended Design Tokens

```css
:root {

  --color-bg:
    #050921;

  --color-bg-deep:
    #020409;

  --color-surface:
    #131B38;

  --color-surface-hover:
    #1A2447;

  --color-primary:
    #00FFF9;

  --color-primary-hover:
    #00D7FF;

  --color-secondary:
    #3860BE;

  --color-text:
    #FFFFFF;

  --color-text-secondary:
    #D8D8D8;

  --color-muted:
    #9298AE;

  --color-border:
    #343855;

  --color-success:
    #28E757;

  --color-warning:
    #FFAE58;

  --color-danger:
    #FF5B6E;


  --font-display:
    "Poppins",
    sans-serif;

  --font-ui:
    "Inter",
    sans-serif;


  --radius-card:
    10px;

  --radius-panel:
    16px;

  --radius-button:
    9999px;


  --container-max:
    1440px;

  --page-gutter:
    24px;

}
```

---

# 42. Component Priority

When implementing the system, create components in this order:

1. AppShell
2. Navigation
3. Tabs
4. Button
5. Card
6. PlayerRow
7. PlayerAvatar
8. PositionBadge
9. Stat
10. RankingTable
11. DraftCard
12. SearchInput
13. FilterBar
14. StatusBadge
15. Modal
16. Drawer
17. Tooltip
18. ChartContainer
19. EmptyState
20. Skeleton

---

# 43. Recommended UI Patterns

For fantasy football specifically create reusable patterns:

PlayerCard

PlayerRow

TeamCard

MatchupCard

LeagueCard

DraftPick

DraftBoard

RosterSlot

ProjectionMetric

RankMovement

InjuryStatus

RosterPercentage

StartPercentage

WaiverStatus

TradeCard

NewsCard

ScoreCard

---

# 44. Do

DO:

* Use navy instead of pure black.
* Use cyan sparingly.
* Make numbers easy to scan.
* Use player imagery.
* Use semantic position colors.
* Use compact layouts.
* Separate information by surface levels.
* Make hover and selection states obvious.
* Use tabular numeric fonts.
* Optimize for live data.
* Make data tables first-class components.
* Make mobile navigation extremely simple.

---

# 45. Don't

DON'T:

* Copy Sleeper logos or proprietary artwork.
* Reproduce the Sleeper interface pixel-for-pixel.
* Use cyan everywhere.
* Use pure #000000 as the main background.
* Add giant shadows.
* Use random gradients.
* Overuse glassmorphism.
* Use excessive animation.
* Make cards excessively tall.
* Add whitespace that harms information density.
* Use generic dashboard templates.
* use rainbow colors for charts.
* put borders around every individual element.

---

# 46. Target Aesthetic

The final result should communicate:

SPORT
+
DATA
+
COMPETITION
+
COMMUNITY
+
REAL-TIME

The interface should look sophisticated enough for an analytics
application while still feeling like a sports product.

Think:

"professional fantasy sports command center"

rather than:

"business intelligence dashboard".

```

### Alguns pontos que eu manteria quase obrigatoriamente

A combinação mais característica que encontrei é **Poppins para títulos/labels + Inter para corpo e dados**, com `#050921` como canvas, `#131B38`/`#1A2447` para os diferentes níveis de cards e `#00FFF9` como accent principal. A análise externa do site atual identifica exatamente essa estrutura, incluindo container de até 1440 px e CTA arredondado. :contentReference[oaicite:3]{index=3}
```

[1]: https://sleeper.com/fantasy-football?utm_source=chatgpt.com "Fantasy Football on Sleeper — Run Your League Free Forever"
[2]: https://www.sokosumi.com/tools/design-md/analysis/sleeper?utm_source=chatgpt.com "Sleeper DESIGN.md: colors, type, components | Sokosumi"
