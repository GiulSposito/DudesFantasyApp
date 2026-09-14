// Scoreboard — league-wide matchup grid, one glance per game.
// Rebuilds R_old/reports/MatchupPredictionsPanel.R (team avatar + score +
// win-prob bar + game-progress bar) on the ESPN/decision-engine data model,
// reusing the app's shared shell instead of the old standalone HTML report.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { bar } from "../components.js";

function teamHalf(m, side) {
  const name = m[`${side}_team_name`];
  const logo = m[`${side}_logo_url`];
  const expected = m[`${side}_expected`];
  const winProb = m[`${side}_win_probability`];
  const locked = m[`${side}_locked_starters`];
  const total = m[`${side}_total_starters`];

  return el("div", { class: "scoreboard-half" },
    el("div", { class: "scoreboard-half__row" },
      logo ? el("img", { class: "scoreboard-avatar", src: logo, alt: name }) : null,
      el("div", { class: "scoreboard-score" }, fmt.points(expected))),
    el("div", { class: "scoreboard-team" }, name),
    bar(winProb, "#00fff9"),
    el("div", { class: "scoreboard-half__row scoreboard-half__row--sub" },
      el("span", {}, fmt.prob(winProb, 0), " to win"),
      total ? el("span", {}, `${locked}/${total} locked`) : null));
}

function matchupCard(m) {
  return el("div", { class: "cockpit-card scoreboard-card" + (m.is_my_matchup ? " scoreboard-card--mine" : "") },
    teamHalf(m, "home"),
    el("div", { class: "scoreboard-vs" }, "VS"),
    teamHalf(m, "away"));
}

export async function render(root) {
  const matchups = await data.getMatchups();
  if (!matchups.length) { mount(root, banner("empty", "No matchups for this run.")); return; }

  mount(root,
    el("div", { class: "scoreboard-grid" }, ...matchups.map(matchupCard)));
}
