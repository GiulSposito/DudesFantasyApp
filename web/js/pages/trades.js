// Trocas — 1×1 trades, impact shown for both teams.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel, posBadge, deltaSpan, rankTable, drawer, fairnessMeter, teamBadge, moveSide, gainBar, badge } from "../components.js";
import { tradeScatter } from "../charts.js";

function detail(t) {
  drawer(`${t.receive_player_name} ↔ ${t.give_player_name}`,
    el("div", { class: "stat__sub", style: "margin-bottom:8px" }, teamBadge(team(t.other_team_id), { size: 22 })),
    t.partner_is_my_opponent
      ? el("div", { class: "cockpit-banner stale" }, "⚠ Este time é seu adversário desta semana: o ganho de chance de vitória pode estar otimista.")
      : null,
    sectionLabel("Você"),
    el("div", {}, "cede ", posBadge(t.give_position), " ", t.give_player_name),
    el("div", {}, "recebe ", posBadge(t.receive_position), " ", t.receive_player_name),
    el("div", { style: "margin-top:6px" }, "pontos ", deltaSpan(t.my_delta_expected, "pts"),
      " · chance ", deltaSpan(t.my_delta_win_probability, "pp")),
    sectionLabel("Parceiro"),
    el("div", {}, "pontos ", deltaSpan(t.their_delta_expected, "pts")),
    sectionLabel("Equilíbrio"),
    fairnessMeter(t.my_delta_expected - t.their_delta_expected),
    el("div", { class: "stat__sub", style: "margin-top:4px" },
      `equilíbrio ${fmt.points(t.fairness, 2)} · nota ${fmt.points(t.trade_score, 1)}`));
}

function tradeCard(t, fc, max, top) {
  const recv = { player_id: t.receive_player_id, player_name: t.receive_player_name, position: t.receive_position };
  const give = { player_id: t.give_player_id, player_name: t.give_player_name, position: t.give_position };
  return el("div", { class: "move-card clickable" + (top ? " move-card--top" : ""), role: "button", tabindex: "0",
    onclick: () => detail(t), onkeydown: (e) => { if (e.key === "Enter") detail(t); } },
    el("div", { class: "move-card__head" },
      teamBadge(team(t.other_team_id), { size: 24 }),
      el("span", {}, t.partner_is_my_opponent ? badge("adversário da semana", "q") : null,
        " nota ", el("b", { style: "color:var(--ink)" }, fmt.points(t.trade_score, 1)))),
    el("div", { class: "move-card__players" },
      moveSide(recv, "Você recebe", "in", fc.get(String(t.receive_ffa_id))),
      el("span", { class: "move-card__arrow" }, "⇄"),
      moveSide(give, "Você cede", "out", fc.get(String(t.give_ffa_id)))),
    el("div", {},
      gainBar("Seu ganho", t.my_delta_expected, max),
      gainBar("Ganho dele", t.their_delta_expected, max)));
}

export async function render(root) {
  const { teamId } = state.get();
  const all = await data.getTradeRecommendations();
  const rows = all.filter((t) => String(t.my_team_id) === String(teamId));

  if (!rows.length) { mount(root,
    banner("empty", "Nenhuma troca 1×1 que ajude seu time nesta semana.")); return; }

  const fcRows = await data.getForecastsByIds(rows.flatMap((t) => [t.receive_ffa_id, t.give_ffa_id]));
  const fc = new Map(fcRows.map((f) => [String(f.ffa_id), f]));
  const max = Math.max(...rows.flatMap((t) => [t.my_delta_expected || 0, t.their_delta_expected || 0]), 0.1);
  const cards = rows.slice(0, 12);

  mount(root,
    el("div", { class: "cockpit-banner stale" },
      "O valor de cada troca é calculado só para a semana atual (escalação ótima desta rodada). Use como ponto de partida, não como veredito para a temporada."),

    sectionLabel("Melhores propostas"),
    el("div", { class: "move-grid" }, ...cards.map((t, i) => tradeCard(t, fc, max, i === 0))),

    sectionLabel("Mapa de trocas: seu ganho x ganho do parceiro"),
    card(el("div", { id: "tr-scatter" }),
      el("div", { class: "note-inline" }, "Acima da linha zero a troca também ajuda o parceiro, e fica mais fácil de ser aceita. Bolha maior: nota maior. Laranja: parceiro é seu adversário desta semana.")),

    sectionLabel(`Todas as propostas (${rows.length})`),
    rankTable(rows, [
      { key: "recommendation_rank", label: "#", num: true },
      { key: "other_team_name", label: "Parceiro", fmt: (v, r) => teamBadge(team(r.other_team_id), { size: 20 }) },
      { key: "receive_player_name", label: "Recebe", fmt: (v, r) => el("span", {}, posBadge(r.receive_position), " ", v) },
      { key: "give_player_name", label: "Cede", fmt: (v, r) => el("span", {}, posBadge(r.give_position), " ", v) },
      { key: "my_delta_expected", label: "Seu Δ", num: true, fmt: (v) => deltaSpan(v, "pts") },
      { key: "their_delta_expected", label: "Δ dele", num: true, fmt: (v) => deltaSpan(v, "pts") },
      { key: "trade_score", label: "Nota", num: true, fmt: (v) => fmt.points(v, 1) },
    ], { onRow: detail }),
  );

  tradeScatter(document.getElementById("tr-scatter"), rows);
}
