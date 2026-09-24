// Waivers — add/drop moves ranked by team gain, not player rank.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { sectionLabel, posBadge, coverageDot, deltaSpan, rankTable, drawer, kv, avatar, rangeBar, moveSide, gainBar } from "../components.js";

let faPos = "ALL";

async function detail(rec) {
  const [addF, dropF] = await Promise.all([
    rec.add_ffa_id ? data.getForecast(rec.add_ffa_id) : null,
    rec.drop_ffa_id ? data.getForecast(rec.drop_ffa_id) : null,
  ]);
  const cmp = (label, d, a, isProb) => kv(label,
    `${isProb ? fmt.prob(d) : fmt.points(d)}  →  ${isProb ? fmt.prob(a) : fmt.points(a)}`);
  drawer(`${rec.add_player_name} no lugar de ${rec.drop_player_name}`,
    sectionLabel("Impacto no time"),
    kv("Pontos esperados", `${fmt.points(rec.before_expected)} → ${fmt.points(rec.after_expected)}`),
    kv("Chance de vitória", `${fmt.prob(rec.before_win_probability)} → ${fmt.prob(rec.after_win_probability)}`),
    el("div", { class: "stat__sub", style: "margin-top:6px" },
      deltaSpan(rec.delta_expected, "pts"), " · ", deltaSpan(rec.delta_win_probability, "pp"), " de chance"),
    sectionLabel("Dispensar → Pegar"),
    cmp("Projeção", dropF?.projection, addF?.projection),
    cmp("Média simulada", dropF?.sim_mean, addF?.sim_mean),
    cmp("P10", dropF?.p10, addF?.p10),
    cmp("P50", dropF?.p50, addF?.p50),
    cmp("P90", dropF?.p90, addF?.p90),
    cmp("P(>15)", dropF?.prob_gt_15, addF?.prob_gt_15, true));
}

function recCard(r, fc, maxPts, maxPp) {
  const add = { player_id: r.add_player_id, player_name: r.add_player_name, position: r.add_position };
  const drop = { player_id: r.drop_player_id, player_name: r.drop_player_name, position: r.drop_position };
  return el("div", { class: "move-card clickable" + (r.recommendation_rank === 1 ? " move-card--top" : ""),
    role: "button", tabindex: "0", onclick: () => detail(r), onkeydown: (e) => { if (e.key === "Enter") detail(r); } },
    el("div", { class: "move-card__head" }, el("span", {}, `#${r.recommendation_rank}`),
      el("span", { class: "gain-big delta--pos" }, fmt.deltaPts(r.delta_expected))),
    el("div", { class: "move-card__players" },
      moveSide(add, "Pegar", "in", fc.get(String(r.add_ffa_id))),
      el("span", { class: "move-card__arrow" }, "⇄"),
      moveSide(drop, "Dispensar", "out", fc.get(String(r.drop_ffa_id)))),
    el("div", {},
      gainBar("Pontos esperados", r.delta_expected, maxPts, "pts"),
      gainBar("Chance de vitória", r.delta_win_probability, maxPp, "pp")));
}

export async function render(root) {
  const { teamId } = state.get();
  const recs = await data.getWaiverRecommendations(teamId);
  const fcRows = await data.getForecastsByIds(recs.flatMap((r) => [r.add_ffa_id, r.drop_ffa_id]));
  const fc = new Map(fcRows.map((f) => [String(f.ffa_id), f]));
  const maxPts = Math.max(...recs.map((r) => r.delta_expected || 0), 0.1);
  const maxPp = Math.max(...recs.map((r) => r.delta_win_probability || 0), 0.001);

  mount(root,
    sectionLabel("Movimentos sugeridos"),
    recs.length ? el("div", { class: "move-grid" }, ...recs.map((r) => recCard(r, fc, maxPts, maxPp)))
      : banner("empty", "Nenhum movimento de waiver que melhore o time nesta semana."),
    recs.length ? el("div", { class: "note-inline" },
      "Ordenado pelo ganho de pontos esperados na escalação ótima desta semana. Clique num card para comparar os dois jogadores.") : null,

    sectionLabel("Free agents disponíveis"),
    el("div", { class: "toolbar" },
      ...["ALL", "QB", "RB", "WR", "TE", "K", "DST"].map((p) =>
        el("button", { class: "chip" + (p === faPos ? " active" : ""),
          onclick: () => { faPos = p; render(root); } }, p === "ALL" ? "Todos" : p))),
    el("div", { id: "wv-fa" }),
  );

  const fa = (await data.getFreeAgents({ position: faPos })).slice(0, 40);
  document.getElementById("wv-fa").replaceChildren(rankTable(fa, [
    { key: "player_name", label: "Jogador", fmt: (v, r) => el("span", { class: "player-cell" }, avatar(r, { size: 30 }), posBadge(r.position), " ", v) },
    { key: "nfl_team", label: "Time", fmt: (v) => fmt.nflAbbr(v) },
    { key: "p10", label: "Faixa P10–P90", fmt: (v, r) => rangeBar(r.p10, r.p50, r.p90) },
    { key: "sim_mean", label: "Proj", num: true, fmt: (v) => el("b", {}, fmt.points(v)) },
    { key: "coverage_class", label: "Conf", num: true, fmt: (v) => coverageDot(v) },
  ], { empty: "Nenhum free agent nesta posição." }));
}
