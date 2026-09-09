// Matchup Center — full build in M3. M2 stub.
import * as data from "../data.js";
import { el, table } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const rows = await data.getMatchups();
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — uncertainty ranges and contribution chart land in M3."),
    table(rows, [
      { key: "home_team_name", label: "Home" },
      { key: "home_expected", label: "Exp", fmt: (v) => fmt.points(v) },
      { key: "home_win_probability", label: "Win%", fmt: (v) => fmt.prob(v) },
      { key: "away_team_name", label: "Away" },
      { key: "away_expected", label: "Exp", fmt: (v) => fmt.points(v) },
      { key: "away_win_probability", label: "Win%", fmt: (v) => fmt.prob(v) },
    ]),
  );
}
