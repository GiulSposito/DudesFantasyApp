// Painel — situation, risk, next best action, in one screen.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel, statRow, statTile, bar, avatar, teamLogo, teamBadge, winBar, moveSide } from "../components.js";

function leagueBoard(matchups, teamId) {
  const mineFirst = [...matchups].sort((a, b) => b.is_my_matchup - a.is_my_matchup);
  const rows = mineFirst.map((m) => {
    const mine = String(m.home_team_id) === String(teamId) || String(m.away_team_id) === String(teamId);
    return el("div", { class: "lb-row" + (mine ? " lb-row--mine" : "") },
      teamBadge(team(m.home_team_id), { size: 22, strong: m.home_win_probability >= 0.5 }),
      el("span", { class: "num" }, fmt.prob(m.home_win_probability, 0)),
      bar(m.home_win_probability),
      el("span", { class: "num" }, fmt.prob(m.away_win_probability, 0)),
      el("div", { class: "lb-row__away" }, teamBadge(team(m.away_team_id), { size: 22, strong: m.away_win_probability > 0.5 })));
  });
  return card(sectionLabel("Confrontos da rodada"), ...rows);
}

function actionCard(kind, inP, outP, inLabel, outLabel, impact, fc) {
  return el("div", { class: "move-card" },
    el("div", { class: "move-card__head" }, el("span", {}, kind), el("span", { class: "delta delta--pos" }, impact)),
    el("div", { class: "move-card__players" },
      moveSide(inP, inLabel, "in", fc.get(String(inP.ffa_id))),
      el("span", { class: "move-card__arrow" }, "⇄"),
      moveSide(outP, outLabel, "out", fc.get(String(outP.ffa_id)))));
}

export async function render(root) {
  const { teamId } = state.get();
  const [my, ev, waivers, trades, lineupRecs, matchups, roster] = await Promise.all([
    data.getMatchupForTeam(teamId),
    data.getLineupEvaluation(teamId),
    data.getWaiverRecommendations(teamId),
    data.getTradeRecommendations(),
    data.getLineupRecommendations(teamId),
    data.getMatchups(),
    data.getRoster(teamId),
  ]);

  if (!my) { mount(root, banner("empty", "Nenhum confronto para esta captura.")); return; }

  const iAmHome = String(my.home_team_id) === String(teamId);
  const pick = (side) => ({
    id: my[`${side}_team_id`], name: my[`${side}_team_name`], exp: my[`${side}_expected`],
    p10: my[`${side}_p10`], p50: my[`${side}_p50`], p90: my[`${side}_p90`],
    win: my[`${side}_win_probability`],
  });
  const me = iAmHome ? pick("home") : pick("away");
  const opp = iAmHome ? pick("away") : pick("home");

  const bestWaiver = waivers[0];
  const bestTrade = trades.filter((t) => String(t.my_team_id) === String(teamId))[0];
  const lineupRec = lineupRecs[0];

  const fcRows = await data.getForecastsByIds([
    bestWaiver?.add_ffa_id, bestWaiver?.drop_ffa_id, bestTrade?.receive_ffa_id, bestTrade?.give_ffa_id,
  ]);
  const fc = new Map(fcRows.map((f) => [String(f.ffa_id), f]));
  const byPid = new Map(roster.map((p) => [String(p.player_id), p]));

  const side = (s, dim) => el("div", { class: "hero__side" },
    teamLogo(team(s.id), { size: 64 }),
    el("div", { class: "stat__value stat__value--xl", style: dim ? "color:var(--ink-2)" : "" }, fmt.points(s.exp)),
    el("div", { class: "hero__team" }, s.name),
    el("div", { class: "hero__range", title: "Faixa do placar: P10 a P90" }, `${fmt.points(s.p10)} – ${fmt.points(s.p90)}`));

  const hero = card(
    el("div", { class: "hero" }, side(me, false), el("div", { class: "hero__vs" }, "x"), side(opp, true)),
    el("div", { style: "margin:16px 0 6px" }, winBar(me.win, opp.win, { labelA: me.name, labelB: opp.name })),
    el("div", { class: "note-inline", style: "text-align:center" },
      `Chance de vitória em ${fmt.points(my.n_sim, 0)} simulações. Números embaixo dos placares: faixa P10–P90.`));

  const starters = roster.filter((p) => p.is_starter).sort((a, b) => a.lineup_slot_id - b.lineup_slot_id);
  const strip = el("div", { class: "starter-strip" }, ...starters.map((p) =>
    el("div", { class: "starter-chip", title: `${p.player_name} · ${p.lineup_slot}` },
      avatar(p, { size: 48 }),
      el("div", { class: "starter-chip__name" }, p.player_name.split(" ").slice(-1)[0]),
      el("div", { class: "starter-chip__pts" }, fmt.points(p.sim_mean)),
      el("div", { class: "stat__sub" }, p.is_locked ? "🔒 " + p.lineup_slot : p.lineup_slot))));

  const actions = [];
  if (lineupRec) {
    const pin = byPid.get(String(lineupRec.player_in_id)) || { player_name: lineupRec.player_in_name, position: lineupRec.player_in_position, player_id: lineupRec.player_in_id };
    const pout = byPid.get(String(lineupRec.player_out_id)) || { player_name: lineupRec.player_out_name, position: lineupRec.player_out_position, player_id: lineupRec.player_out_id };
    actions.push(actionCard("Escalação", pin, pout, "Escalar", "Tirar",
      `${fmt.deltaPts(lineupRec.delta_expected)} · ${fmt.deltaPp(lineupRec.delta_win_probability)}`, new Map([[String(pin.ffa_id), pin], [String(pout.ffa_id), pout]])));
  }
  if (bestWaiver) actions.push(actionCard("Waiver",
    { player_id: bestWaiver.add_player_id, ffa_id: bestWaiver.add_ffa_id, player_name: bestWaiver.add_player_name, position: bestWaiver.add_position },
    { player_id: bestWaiver.drop_player_id, ffa_id: bestWaiver.drop_ffa_id, player_name: bestWaiver.drop_player_name, position: bestWaiver.drop_position },
    "Pegar", "Dispensar",
    `${fmt.deltaPts(bestWaiver.delta_expected)} · ${fmt.deltaPp(bestWaiver.delta_win_probability)}`, fc));
  if (bestTrade) actions.push(actionCard(`Troca com ${bestTrade.other_team_name}`,
    { player_id: bestTrade.receive_player_id, ffa_id: bestTrade.receive_ffa_id, player_name: bestTrade.receive_player_name, position: bestTrade.receive_position },
    { player_id: bestTrade.give_player_id, ffa_id: bestTrade.give_ffa_id, player_name: bestTrade.give_player_name, position: bestTrade.give_position },
    "Receber", "Ceder",
    `você ${fmt.deltaPts(bestTrade.my_delta_expected)} · ele ${fmt.deltaPts(bestTrade.their_delta_expected)}`, fc));

  mount(root,
    hero,
    el("div", { style: "margin:16px 0" }, statRow([
      statTile("Chance de vitória", fmt.prob(me.win, 0), null, { accent: true }),
      statTile("Pontos esperados", fmt.points(me.exp)),
      statTile("Escalação ótima", ev ? fmt.points(ev.optimal_expected) : "–",
        ev && ev.delta_expected > 0.05 ? `dá para ganhar ${fmt.deltaPts(ev.delta_expected)}` : "você já está no ótimo"),
      statTile("Melhor waiver", bestWaiver ? fmt.deltaPts(bestWaiver.delta_expected) : "–"),
      statTile("Melhor troca", bestTrade ? fmt.deltaPts(bestTrade.my_delta_expected) : "–"),
    ])),
    sectionLabel("Seus titulares"),
    strip,
    el("div", { class: "grid-2", style: "margin-top:16px" },
      el("div", {}, sectionLabel("Próximas ações"),
        actions.length ? el("div", { class: "move-grid", style: "grid-template-columns:1fr" }, ...actions)
          : banner("empty", "Nenhuma mudança de escalação, waiver ou troca recomendada.")),
      leagueBoard(matchups, teamId)),
  );
}
