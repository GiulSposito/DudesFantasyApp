// Escalação — optimizer output as an actionable start/sit interface.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, deltaSpan, rankTable, playerRow, playerRowHeader, badge, avatar, rangeBar,
  statusBadge, lockBadge, moveSide } from "../components.js";
import { opportunityScatter } from "../charts.js";

function comparison(ev) {
  const row = (label, cur, opt, isProb) => ({
    metric: label,
    current: isProb ? fmt.prob(cur) : fmt.points(cur),
    optimal: isProb ? fmt.prob(opt) : fmt.points(opt),
    _d: opt - cur, _isProb: isProb,
  });
  const rows = [
    row("Pontos esperados", ev.current_expected, ev.optimal_expected),
    row("Piso (P10)", ev.current_p10, ev.optimal_p10),
    row("Mediana", ev.current_p50, ev.optimal_p50),
    row("Teto (P90)", ev.current_p90, ev.optimal_p90),
    row("Chance de vitória", ev.current_win_probability, ev.optimal_win_probability, true),
  ];
  return rankTable(rows, [
    { key: "metric", label: "" },
    { key: "current", label: "Atual", num: true },
    { key: "optimal", label: "Ótima", num: true },
    { key: "_d", label: "Δ", num: true, fmt: (v, r) => deltaSpan(v, r._isProb ? "pp" : "pts") },
  ]);
}

function slotCard(p, rec) {
  return el("div", { class: "slot-card" + (rec === "out" ? " slot-card--out" : "") },
    avatar(p, { size: 52 }),
    el("div", { style: "min-width:0" },
      el("div", { class: "slot-card__slot" }, p.lineup_slot, rec === "out" ? " · sair" : ""),
      el("div", { class: "slot-card__name", title: p.player_name }, p.player_name),
      el("div", { class: "slot-card__meta" }, fmt.nflAbbr(p.nfl_team), " ",
        p.is_locked ? lockBadge() : statusBadge(p.injury_status))),
    el("div", { class: "slot-card__foot" },
      rangeBar(p.p10, p.p50, p.p90),
      el("span", { class: "slot-card__pts", title: p.is_realized ? "pontos reais" : "pontos esperados" }, fmt.points(p.sim_mean))));
}

function playerLine(p, rec) {
  const rb = rec === "in" ? badge("↑ escalar", "start")
    : rec === "out" ? badge("↓ banco", "out") : null;
  return playerRow(p, { badge: rb, optimal: p.is_optimal_starter });
}

export async function render(root) {
  const { teamId } = state.get();
  const [roster, ev, recs] = await Promise.all([
    data.getRoster(teamId), data.getLineupEvaluation(teamId), data.getLineupRecommendations(teamId),
  ]);
  if (!ev) { mount(root, banner("empty", "Sem avaliação de escalação para este time nesta captura.")); return; }

  const inIds = new Set(recs.map((r) => String(r.player_in_id)));
  const outIds = new Set(recs.map((r) => String(r.player_out_id)));
  const recOf = (p) => inIds.has(String(p.player_id)) ? "in" : outIds.has(String(p.player_id)) ? "out" : null;
  const byPid = new Map(roster.map((p) => [String(p.player_id), p]));

  const starters = roster.filter((p) => p.is_starter).sort((a, b) => a.lineup_slot_id - b.lineup_slot_id);
  const bench = roster.filter((p) => !p.is_starter && !p.is_ir).sort((a, b) => b.sim_mean - a.sim_mean);
  const ir = roster.filter((p) => p.is_ir);

  const moves = recs.map((r) => {
    const pin = byPid.get(String(r.player_in_id)) || { player_name: r.player_in_name, position: r.player_in_position, player_id: r.player_in_id };
    const pout = byPid.get(String(r.player_out_id)) || { player_name: r.player_out_name, position: r.player_out_position, player_id: r.player_out_id };
    return el("div", { class: "move-card" + (r.recommendation_rank === 1 ? " move-card--top" : "") },
      el("div", { class: "move-card__head" }, el("span", {}, `#${r.recommendation_rank} · slot ${r.slot}`),
        el("span", {}, deltaSpan(r.delta_expected, "pts"), " · ", deltaSpan(r.delta_win_probability, "pp"))),
      el("div", { class: "move-card__players" },
        moveSide(pin, "Escalar", "in", pin), el("span", { class: "move-card__arrow" }, "⇄"), moveSide(pout, "Para o banco", "out", pout)));
  });

  mount(root,
    sectionLabel(`Titulares (${starters.length})`),
    el("div", { class: "slot-grid" }, ...starters.map((p) => slotCard(p, recOf(p)))),

    sectionLabel("Mudanças recomendadas"),
    moves.length ? el("div", { class: "move-grid" }, ...moves)
      : banner("empty", "Nenhuma troca de titular recomendada: a escalação atual já é a ótima."),

    sectionLabel("Atual x ótima"),
    card(comparison(ev),
      el("div", { class: "note-inline" },
        `${ev.n_substitutions} substituição(ões) · valor do banco ${fmt.points(ev.bench_value)} pts` +
        (ev.optimal_win_probability < ev.current_win_probability
          ? " · a escalação de mais pontos se sai um pouco pior contra este adversário" : ""))),

    sectionLabel(`Banco (${bench.length})`),
    el("div", { class: "cockpit-card cockpit-card--tight" },
      playerRowHeader(), ...bench.map((p) => playerLine(p, recOf(p)))),
    ir.length ? sectionLabel(`IR (${ir.length})`) : null,
    ir.length ? el("div", { class: "cockpit-card cockpit-card--tight" }, ...ir.map((p) => playerLine(p, null))) : null,

    sectionLabel("Mapa de oportunidade: valor x risco"),
    card(el("div", { id: "lineup-opp" }),
      el("div", { class: "note-inline" }, "Mais à direita: mais pontos esperados. Mais alto: resultado mais incerto. Nome só nos titulares; passe o mouse nos outros.")),
  );

  opportunityScatter(document.getElementById("lineup-opp"),
    roster.filter((p) => p.sim_mean != null).map((p) => ({
      player_name: p.player_name, sim_mean: p.sim_mean, sim_sd: p.sim_sd, pos: fmt.pos(p.position), is_starter: p.is_starter,
    })));
}
