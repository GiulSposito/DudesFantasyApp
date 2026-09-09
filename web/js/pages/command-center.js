// Command Center — situation, risk, next best action, in one screen.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, statRow, statTile, deltaSpan, bar } from "../components.js";
import { probabilityBar } from "../charts.js";

function leagueBoard(matchups, teamId) {
  const rows = matchups.map((m) => {
    const hp = m.home_win_probability;
    const mine = String(m.home_team_id) === String(teamId) || String(m.away_team_id) === String(teamId);
    return el("div", { style: "display:flex;align-items:center;gap:8px;padding:5px 0;font-size:13px" +
      (mine ? ";color:var(--accent)" : "") },
      el("span", { style: `flex:1;text-align:right;color:${hp >= 0.5 && !mine ? "var(--ink)" : "inherit"}` }, m.home_team_name),
      el("span", { class: "player-row__num", style: "width:38px;color:var(--muted)" }, fmt.prob(hp, 0)),
      el("div", { style: "width:96px" }, bar(hp)),
      el("span", { class: "player-row__num", style: "width:38px;color:var(--muted);text-align:left" }, fmt.prob(m.away_win_probability, 0)),
      el("span", { style: `flex:1;color:${hp < 0.5 && !mine ? "var(--ink)" : "inherit"}` }, m.away_team_name));
  });
  return card(sectionLabel("Week matchups"), ...rows);
}

function actionCard(a) {
  return el("div", { class: "cockpit-card cockpit-card--tight", style: "margin-bottom:8px" },
    el("div", { style: "font-family:Poppins,sans-serif;font-weight:600;color:var(--accent);font-size:11px;letter-spacing:.06em" }, a.kind),
    el("div", { style: "color:var(--ink)" }, a.headline),
    el("div", { style: "font-size:13px;color:var(--muted)" }, a.impact));
}

export async function render(root) {
  const { teamId } = state.get();
  const [my, ev, waivers, trades, lineupRecs, matchups] = await Promise.all([
    data.getMatchupForTeam(teamId),
    data.getLineupEvaluation(teamId),
    data.getWaiverRecommendations(teamId),
    data.getTradeRecommendations(),
    data.getLineupRecommendations(teamId),
    data.getMatchups(),
  ]);

  if (!my) { mount(root, banner("empty", "No matchup for the selected run.")); return; }

  const iAmHome = String(my.home_team_id) === String(teamId);
  const pick = (side) => ({
    name: my[`${side}_team_name`], exp: my[`${side}_expected`],
    p10: my[`${side}_p10`], p50: my[`${side}_p50`], p90: my[`${side}_p90`],
    win: my[`${side}_win_probability`],
  });
  const me = iAmHome ? pick("home") : pick("away");
  const opp = iAmHome ? pick("away") : pick("home");

  const bestWaiver = waivers[0];
  const bestTrade = trades.filter((t) => String(t.my_team_id) === String(teamId))[0] || trades[0];

  const hero = card(
    el("div", { class: "hero" },
      el("div", { class: "hero__side" },
        el("div", { class: "stat__label" }, "My team"),
        el("div", { class: "stat__value stat__value--xl" }, fmt.points(me.exp)),
        el("div", { class: "hero__team" }, me.name)),
      el("div", { class: "hero__side" },
        el("div", { class: "stat__label" }, "Opponent"),
        el("div", { class: "stat__value stat__value--xl", style: "color:var(--ink-2)" }, fmt.points(opp.exp)),
        el("div", { class: "hero__team" }, opp.name))),
    el("div", { id: "cc-winbar", style: "margin:14px 0 6px" }),
    el("div", { style: "text-align:center;font-family:Poppins,sans-serif;font-weight:700;color:var(--accent)" },
      `WIN ${fmt.prob(me.win, 0)}`),
    el("div", { style: "display:flex;justify-content:space-between;font-size:12px;color:var(--muted);margin-top:10px;max-width:340px;margin-left:auto;margin-right:auto" },
      el("span", {}, `P10 ${fmt.points(me.p10)}`),
      el("span", {}, `P50 ${fmt.points(me.p50)}`),
      el("span", {}, `P90 ${fmt.points(me.p90)}`)));

  const actions = [];
  if (lineupRecs[0]) {
    const r = lineupRecs[0];
    actions.push({ kind: "START", headline: `${r.player_in_name} → bench ${r.player_out_name}`,
      impact: `${fmt.deltaPts(r.delta_expected)} · ${fmt.deltaPp(r.delta_win_probability)} win` });
  }
  if (bestWaiver) actions.push({ kind: "ADD", headline: `${bestWaiver.add_player_name} → drop ${bestWaiver.drop_player_name}`,
    impact: `${fmt.deltaPts(bestWaiver.delta_expected)} · ${fmt.deltaPp(bestWaiver.delta_win_probability)} win` });
  if (bestTrade) actions.push({ kind: "TRADE", headline: `${bestTrade.receive_player_name} ↔ ${bestTrade.give_player_name} · ${bestTrade.other_team_name}`,
    impact: `you ${fmt.deltaPts(bestTrade.my_delta_expected)} · partner ${fmt.deltaPts(bestTrade.their_delta_expected)} · score ${fmt.points(bestTrade.trade_score)}` });

  mount(root,
    hero,
    el("div", { style: "margin:16px 0" }, statRow([
      statTile("Win prob", fmt.prob(me.win, 0), null, { accent: true }),
      statTile("Expected", fmt.points(me.exp)),
      statTile("Optimal", ev ? fmt.points(ev.optimal_expected) : "–"),
      statTile("Lineup edge", ev ? fmt.deltaPts(ev.delta_expected) : "–"),
      statTile("Best waiver", bestWaiver ? fmt.deltaPts(bestWaiver.delta_expected) : "–"),
      statTile("Best trade", bestTrade ? fmt.deltaPts(bestTrade.my_delta_expected) : "–"),
    ])),
    el("div", { class: "grid-2" },
      el("div", {}, sectionLabel("Action center"),
        actions.length ? actions.map(actionCard) : banner("empty", "No lineup, waiver or trade move recommended.")),
      leagueBoard(matchups, teamId)),
  );

  probabilityBar(document.getElementById("cc-winbar"),
    { labelA: me.name, probA: me.win, labelB: opp.name, probB: opp.win });
}
