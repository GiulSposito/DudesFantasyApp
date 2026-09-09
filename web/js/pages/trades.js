// Trade Center — full build in M5. M2 stub.
import * as data from "../data.js";
import { el, table, banner } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const rows = await data.getTradeRecommendations();
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — opportunity map and fairness meter land in M5."),
    rows.length ? table(rows, [
      { key: "recommendation_rank", label: "#" },
      { key: "other_team_name", label: "Partner" },
      { key: "give_player_name", label: "Give" },
      { key: "receive_player_name", label: "Receive" },
      { key: "my_delta_expected", label: "My Δ", fmt: (v) => fmt.deltaPts(v) },
      { key: "their_delta_expected", label: "Their Δ", fmt: (v) => fmt.deltaPts(v) },
      { key: "trade_score", label: "Score", fmt: (v) => fmt.points(v) },
      { key: "partner_is_my_opponent", label: "Opp?", fmt: (v) => (v ? "⚠ yes" : "no") },
    ]) : banner("empty", "No mutually beneficial trade found."),
  );
}
