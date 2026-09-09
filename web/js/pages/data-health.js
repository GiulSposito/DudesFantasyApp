// Data & Model Health — full build in M7. M2 stub already close to final.
import * as data from "../data.js";
import { el, table, banner } from "../app.js";
import * as fmt from "../format.js";

export async function render(root) {
  const h = await data.getDataHealth();
  if (!h) { root.replaceChildren(banner("empty", "No data_health row for this run.")); return; }
  const kv = (k, v) => el("tr", {}, el("th", {}, k), el("td", {}, v));
  root.replaceChildren(
    el("span", { class: `cockpit-banner ${h.status === "healthy" ? "empty" : h.status}` }, `status: ${h.status}`),
    el("table", { class: "table table-sm table-dark", style: "max-width:520px" }, el("tbody", {},
      kv("Model", `${h.model_version} · ${h.n_sim} draws`),
      kv("FFA snapshot", fmt.ts(h.ffa_timestamp)),
      kv("ESPN snapshot", fmt.ts(h.espn_timestamp)),
      kv("Decision run", fmt.ts(h.decision_timestamp)),
      kv("Forecast players", h.n_forecast_players),
      kv("Mapped starters", `${h.n_mapped_starters} / ${h.n_starters}`),
      kv("Unmapped players", h.n_unmapped_players),
      kv("Coverage ensemble", fmt.prob(h.pct_ensemble)),
      kv("Coverage sparse", fmt.prob(h.pct_sparse)),
      kv("Coverage single", fmt.prob(h.pct_single)),
    )),
    el("h3", {}, "Bridge method"),
    table([
      { m: "direct ESPN id", n: h.n_bridge_espn_id },
      { m: "D/ST offset", n: h.n_bridge_dst_offset },
      { m: "name + position", n: h.n_bridge_name_pos },
      { m: "override", n: h.n_bridge_override },
      { m: "unmapped", n: h.n_bridge_none },
    ], [{ key: "m", label: "Method" }, { key: "n", label: "Count" }]),
  );
}
