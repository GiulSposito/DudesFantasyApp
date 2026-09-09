// Waiver Wire Center — full build in M5. M2 stub.
import * as data from "../data.js";
import * as state from "../state.js";
import { el, table, banner } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const { teamId } = state.get();
  const rows = await data.getWaiverRecommendations(teamId);
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — Δ scatter and detail drawer land in M5."),
    rows.length ? table(rows, [
      { key: "recommendation_rank", label: "#" },
      { key: "add_player_name", label: "Add" },
      { key: "drop_player_name", label: "Drop" },
      { key: "delta_expected", label: "Δ pts", fmt: (v) => fmt.deltaPts(v) },
      { key: "delta_win_probability", label: "Δ win", fmt: (v) => fmt.deltaPp(v) },
    ]) : banner("empty", "No acceptable waiver move found."),
  );
}
