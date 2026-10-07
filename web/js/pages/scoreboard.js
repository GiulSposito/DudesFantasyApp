// Placar da rodada — league-wide matchup grid, one glance per game.
// Rebuilds R_old/reports/MatchupPredictionsPanel.R (team avatar + score +
// win-prob bar + game-progress bar) on the ESPN/decision-engine data model.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { bar, teamLogo, avatar, posBadge, card, sectionLabel, playerLink } from "../components.js";

function teamHalf(m, side) {
  const id = m[`${side}_team_id`];
  const winProb = m[`${side}_win_probability`];
  const locked = m[`${side}_locked_starters`];
  const total = m[`${side}_total_starters`];
  const fav = winProb >= 0.5;

  return el("div", { class: "scoreboard-half" },
    el("div", { class: "scoreboard-half__row" },
      teamLogo(team(id), { size: 42 }),
      el("div", { class: "scoreboard-score", style: fav ? "" : "color:var(--ink-2)" }, fmt.points(m[`${side}_expected`]))),
    el("div", { class: "scoreboard-team" }, m[`${side}_team_name`]),
    bar(winProb, fav ? "var(--accent)" : "var(--gray-400, #4c5579)"),
    el("div", { class: "scoreboard-half__row scoreboard-half__row--sub" },
      el("span", { title: "Chance de vitória" }, fmt.prob(winProb, 0)),
      total ? el("span", { title: "Titulares cujo jogo já começou ou terminou" }, `${locked}/${total} jogaram`) : null));
}

// the selected team's matchup, not the config's is_my_matchup
const isTeams = (m, teamId) =>
  String(m.home_team_id) === String(teamId) || String(m.away_team_id) === String(teamId);

function matchupCard(m, teamId) {
  return el("div", { class: "cockpit-card scoreboard-card" + (isTeams(m, teamId) ? " scoreboard-card--mine" : "") },
    teamHalf(m, "home"),
    el("div", { class: "scoreboard-vs" }, "x"),
    teamHalf(m, "away"));
}

// one starting slot of a best-lineup card; owner logo only for rostered players
function bestRow(p) {
  return playerLink(el("div", { class: "best-row" },
    el("div", { class: "best-row__slot" }, p.lineup_slot),
    avatar(p, { size: 32 }),
    el("div", { class: "best-row__name" },
      el("div", {}, posBadge(p.position), " ", p.player_name),
      el("div", { class: "best-row__meta" }, p.nfl_team || "")),
    el("div", { class: "hide-sm" }, p.team_id != null ? teamLogo(team(p.team_id), { size: 24 }) : null),
    el("div", { class: "best-row__pts" }, fmt.points(p.points))), p);
}

function bestCard(title, rows) {
  const total = rows.reduce((s, p) => s + p.points, 0);
  return card(sectionLabel(title), ...rows.map(bestRow),
    el("div", { class: "best-row best-row--total" },
      el("div", {}, "Total"), el("div", { class: "best-row__pts" }, fmt.points(total))));
}

export async function render(root) {
  const { teamId, week } = state.get();
  const [matchups, best] = await Promise.all([data.getMatchups(), data.getBestLineups()]);
  if (!matchups.length) { mount(root, banner("empty", "Nenhum confronto para esta captura.")); return; }

  const sorted = [...matchups].sort((a, b) => isTeams(b, teamId) - isTeams(a, teamId));
  const league = best.filter((p) => p.kind === "league");
  const fa = best.filter((p) => p.kind === "free_agents");
  mount(root,
    el("div", { class: "scoreboard-grid" }, ...sorted.map((m) => matchupCard(m, teamId))),
    el("div", { class: "note-inline" }, "Placar = pontos esperados (inclui pontos reais de quem já jogou). Seu confronto aparece primeiro, com borda."),
    best.length ? el("div", { class: "grid-2", style: "margin-top:24px" },
      el("div", {}, bestCard(`Dream team · Semana ${week}`, league)),
      el("div", {}, bestCard(`Melhores free agents · Semana ${week}`, fa))) : null);
}
