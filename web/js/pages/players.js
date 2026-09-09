// Player Explorer — full build in M6. M2 stub.
import * as data from "../data.js";
import * as state from "../state.js";
import { el, table } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const { position } = state.get();
  const rows = (await data.getForecasts({ position })).slice(0, 50);
  root.replaceChildren(
    el("p", { class: "text-muted" }, `M2 stub — search + filters + detail drawer land in M6. Showing top ${rows.length} by sim mean.`),
    table(rows, [
      { key: "player_name", label: "Player" },
      { key: "position", label: "Pos", fmt: (v) => fmt.pos(v) },
      { key: "nfl_team", label: "Team" },
      { key: "projection", label: "Proj", fmt: (v) => fmt.points(v) },
      { key: "sim_mean", label: "Sim", fmt: (v) => fmt.points(v) },
      { key: "p10", label: "P10", fmt: (v) => fmt.points(v) },
      { key: "p90", label: "P90", fmt: (v) => fmt.points(v) },
      { key: "coverage_class", label: "Cov", fmt: (v) => fmt.coverage(v).label },
    ]),
  );
}
