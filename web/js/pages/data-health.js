// Data & Model Health — make missing / stale data explicit.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, statRow, statTile, rankTable, kv } from "../components.js";

export async function render(root) {
  const h = await data.getDataHealth();
  if (!h) { mount(root, banner("empty", "No data_health row for this run.")); return; }

  const ageH = (Date.now() - new Date(h.generated_at).getTime()) / 3.6e6;
  const stale = ageH > 24;
  const bannerKind = h.status === "healthy" ? "empty" : h.status === "warning" ? "stale" : "error";

  mount(root,
    el("div", { class: `cockpit-banner ${bannerKind}` }, `status: ${h.status}`),
    stale ? banner("stale", `Bundle generated ${fmt.since(h.generated_at)} — data may be out of date.`) : null,

    sectionLabel("Run"),
    statRow([
      statTile("Model", h.model_version, `${h.n_sim} draws`),
      statTile("Forecast players", h.n_forecast_players),
      statTile("Mapped starters", `${h.n_mapped_starters} / ${h.n_starters}`,
        h.n_unmapped_starters > 0 ? `${h.n_unmapped_starters} unmapped` : "all mapped",
        { accent: h.n_unmapped_starters === 0 }),
      statTile("Coverage ensemble", fmt.prob(h.pct_ensemble), null, { accent: true }),
    ]),

    sectionLabel("Snapshots"),
    card(
      kv("FFA projections", fmt.ts(h.ffa_timestamp)),
      kv("ESPN snapshot", fmt.ts(h.espn_timestamp)),
      kv("Decision run", fmt.ts(h.decision_timestamp)),
      kv("Bundle generated", `${fmt.ts(h.generated_at)} · ${fmt.since(h.generated_at)}`)),

    sectionLabel("Coverage"),
    card(
      kv("Ensemble (4+ sources)", `${h.n_ensemble} · ${fmt.prob(h.pct_ensemble)}`),
      kv("Sparse (2–3 sources)", `${h.n_sparse} · ${fmt.prob(h.pct_sparse)}`),
      kv("Single (1 source)", `${h.n_single} · ${fmt.prob(h.pct_single)}`)),

    sectionLabel("ESPN → FFA bridge method"),
    rankTable([
      { m: "direct ESPN id", n: h.n_bridge_espn_id },
      { m: "D/ST offset", n: h.n_bridge_dst_offset },
      { m: "name + position", n: h.n_bridge_name_pos },
      { m: "manual override", n: h.n_bridge_override },
      { m: "unmapped", n: h.n_bridge_none },
    ], [{ key: "m", label: "Method" }, { key: "n", label: "Players", num: true }]),
  );
}
