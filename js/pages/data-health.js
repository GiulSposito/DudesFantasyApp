// Saúde dos dados — make missing / stale data explicit.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, statRow, statTile, rankTable, kv } from "../components.js";

export async function render(root) {
  const h = await data.getDataHealth();
  if (!h) { mount(root, banner("empty", "Sem registro de saúde dos dados para esta captura.")); return; }

  const ageH = (Date.now() - new Date(h.generated_at).getTime()) / 3.6e6;
  const stale = ageH > 24;
  const bannerKind = h.status === "healthy" ? "empty" : h.status === "warning" ? "stale" : "error";

  mount(root,
    el("div", { class: `cockpit-banner ${bannerKind}` }, `situação: ${h.status}`),
    stale ? banner("stale", `Bundle gerado ${fmt.since(h.generated_at)}: os dados podem estar desatualizados.`) : null,

    sectionLabel("Execução"),
    statRow([
      statTile("Modelo", h.model_version, `${fmt.points(h.n_sim, 0)} simulações`),
      statTile("Jogadores projetados", h.n_forecast_players),
      statTile("Titulares mapeados", `${h.n_mapped_starters} / ${h.n_starters}`,
        h.n_unmapped_starters > 0 ? `${h.n_unmapped_starters} sem projeção` : "todos com projeção",
        { accent: h.n_unmapped_starters === 0 }),
      statTile("Cobertura alta", fmt.prob(h.pct_ensemble), null, { accent: true }),
    ]),

    sectionLabel("Capturas"),
    card(
      kv("Projeções FFA", fmt.ts(h.ffa_timestamp)),
      kv("Snapshot ESPN", fmt.ts(h.espn_timestamp)),
      kv("Motor de decisão", fmt.ts(h.decision_timestamp)),
      kv("Bundle do site", `${fmt.ts(h.generated_at)} · ${fmt.since(h.generated_at)}`)),

    sectionLabel("Cobertura de fontes"),
    card(
      kv("Alta (4+ fontes)", `${h.n_ensemble} · ${fmt.prob(h.pct_ensemble)}`),
      kv("Média (2–3 fontes)", `${h.n_sparse} · ${fmt.prob(h.pct_sparse)}`),
      kv("Baixa (1 fonte)", `${h.n_single} · ${fmt.prob(h.pct_single)}`)),

    sectionLabel("Como cada jogador ESPN foi ligado à projeção"),
    rankTable([
      { m: "id ESPN direto", n: h.n_bridge_espn_id },
      { m: "D/ST (offset de id)", n: h.n_bridge_dst_offset },
      { m: "nome + posição", n: h.n_bridge_name_pos },
      { m: "ajuste manual", n: h.n_bridge_override },
      { m: "sem ligação", n: h.n_bridge_none },
    ], [{ key: "m", label: "Método" }, { key: "n", label: "Jogadores", num: true }]),
  );
}
