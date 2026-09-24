// Placar da rodada — league-wide matchup grid, one glance per game.
// Rebuilds R_old/reports/MatchupPredictionsPanel.R (team avatar + score +
// win-prob bar + game-progress bar) on the ESPN/decision-engine data model.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { bar, teamLogo } from "../components.js";

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

function matchupCard(m) {
  return el("div", { class: "cockpit-card scoreboard-card" + (m.is_my_matchup ? " scoreboard-card--mine" : "") },
    teamHalf(m, "home"),
    el("div", { class: "scoreboard-vs" }, "x"),
    teamHalf(m, "away"));
}

export async function render(root) {
  const matchups = await data.getMatchups();
  if (!matchups.length) { mount(root, banner("empty", "Nenhum confronto para esta captura.")); return; }

  const sorted = [...matchups].sort((a, b) => b.is_my_matchup - a.is_my_matchup);
  mount(root,
    el("div", { class: "scoreboard-grid" }, ...sorted.map(matchupCard)),
    el("div", { class: "note-inline" }, "Placar = pontos esperados (inclui pontos reais de quem já jogou). Seu confronto aparece primeiro, com borda."));
}
