// Lineup Lab — full build in M4. M2 stub.
import * as data from "../data.js";
import * as state from "../state.js";
import { el, table, banner } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const { teamId } = state.get();
  const ev = await data.getLineupEvaluation(teamId);
  if (!ev) { root.replaceChildren(banner("empty", "No lineup evaluation for this team/run.")); return; }
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — roster board and opportunity chart land in M4."),
    table([ev], [
      { key: "current_expected", label: "Current", fmt: (v) => fmt.points(v) },
      { key: "optimal_expected", label: "Optimal", fmt: (v) => fmt.points(v) },
      { key: "delta_expected", label: "Δ", fmt: (v) => fmt.deltaPts(v) },
      { key: "current_win_probability", label: "Cur Win%", fmt: (v) => fmt.prob(v) },
      { key: "optimal_win_probability", label: "Opt Win%", fmt: (v) => fmt.prob(v) },
      { key: "n_substitutions", label: "Subs" },
    ]),
  );
}
