// League Analyzer — full build in M6. M2 stub.
import * as data from "../data.js";
import { el, table } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const standings = await data.getStandings();
  const le = await data.q("SELECT team_id, optimal_expected FROM lineup_evaluations", "lineup_evaluations");
  const strength = new Map(le.map((r) => [String(r.team_id), r.optimal_expected]));
  const rows = standings.map((r) => ({ ...r, optimal_expected: strength.get(String(r.team_id)) }))
    .sort((a, b) => (b.optimal_expected ?? 0) - (a.optimal_expected ?? 0));
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — position heatmap and quadrant scatter land in M6. Strength = optimal expected points."),
    table(rows, [
      { key: "team_name", label: "Team" },
      { key: "current_projected_rank", label: "Proj rank" },
      { key: "wins", label: "W" },
      { key: "losses", label: "L" },
      { key: "optimal_expected", label: "Strength (opt exp)", fmt: (v) => fmt.points(v) },
    ]),
  );
}
