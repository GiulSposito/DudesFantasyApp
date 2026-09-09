// Command Center — situation, risk, next best action, in one screen.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner } from "../app.js";
import { probabilityBar } from "../charts.js";

function kpi(label, value, sub) {
  return el("div", { class: "cockpit-card", style: "flex:1;min-width:130px" },
    el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae" }, label.toUpperCase()),
    el("div", { style: "font-size:26px;font-weight:600;color:#fff" }, value),
    sub ? el("div", { style: "font-size:12px;color:#9298ae" }, sub) : null);
}

function leagueBoard(matchups) {
  const rows = matchups.map((m) => {
    const hp = m.home_win_probability;
    return el("div", { style: "display:flex;align-items:center;gap:8px;padding:4px 0;font-size:13px" },
      el("span", { style: "width:150px;text-align:right;color:" + (hp >= 0.5 ? "#fff" : "#9298ae") }, m.home_team_name),
      el("span", { style: "width:44px;text-align:right;color:#9298ae" }, fmt.prob(hp, 0)),
      el("div", { style: "flex:1;height:8px;background:#131b38;border-radius:4px;overflow:hidden" },
        el("div", { style: `width:${(hp * 100).toFixed(0)}%;height:100%;background:#00fff9` })),
      el("span", { style: "width:44px;color:#9298ae" }, fmt.prob(m.away_win_probability, 0)),
      el("span", { style: "width:150px;color:" + (hp < 0.5 ? "#fff" : "#9298ae") }, m.away_team_name));
  });
  return el("div", { class: "cockpit-card" },
    el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin-bottom:6px" }, "WEEK MATCHUPS"),
    ...rows);
}

function actionCard(a) {
  return el("div", { class: "cockpit-card", style: "margin-bottom:8px" },
    el("div", { style: "font-weight:600;color:#00fff9;font-size:12px;letter-spacing:.05em" }, a.kind),
    el("div", { style: "color:#fff" }, a.headline),
    el("div", { style: "font-size:13px;color:#9298ae" }, a.impact));
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

  if (!my) { root.replaceChildren(banner("empty", "No matchup for the selected run.")); return; }

  const iAmHome = String(my.home_team_id) === String(teamId);
  const me = iAmHome
    ? { name: my.home_team_name, exp: my.home_expected, p10: my.home_p10, p50: my.home_p50, p90: my.home_p90, win: my.home_win_probability }
    : { name: my.away_team_name, exp: my.away_expected, p10: my.away_p10, p50: my.away_p50, p90: my.away_p90, win: my.away_win_probability };
  const opp = iAmHome
    ? { name: my.away_team_name, exp: my.away_expected, p10: my.away_p10, p50: my.away_p50, p90: my.away_p90, win: my.away_win_probability }
    : { name: my.home_team_name, exp: my.home_expected, p10: my.home_p10, p50: my.home_p50, p90: my.home_p90, win: my.home_win_probability };

  const bestWaiver = waivers[0];
  const bestTrade = trades.filter((t) => String(t.my_team_id) === String(teamId))[0] || trades[0];

  // hero
  const hero = el("div", { class: "cockpit-card" },
    el("div", { style: "display:flex;justify-content:space-around;text-align:center" },
      el("div", {},
        el("div", { style: "font-size:11px;color:#9298ae;letter-spacing:.06em" }, "MY TEAM"),
        el("div", { style: "font-size:40px;font-weight:700;color:#fff" }, fmt.points(me.exp)),
        el("div", { style: "font-size:12px;color:#9298ae" }, me.name)),
      el("div", {},
        el("div", { style: "font-size:11px;color:#9298ae;letter-spacing:.06em" }, "OPPONENT"),
        el("div", { style: "font-size:40px;font-weight:700;color:#d8d8d8" }, fmt.points(opp.exp)),
        el("div", { style: "font-size:12px;color:#9298ae" }, opp.name))),
    el("div", { id: "cc-winbar", style: "margin:12px 0 4px" }),
    el("div", { style: "text-align:center;font-weight:600;color:#00fff9" }, `WIN ${fmt.prob(me.win, 0)}`),
    el("div", { style: "display:flex;justify-content:space-between;font-size:12px;color:#9298ae;margin-top:8px" },
      el("span", {}, `P10 ${fmt.points(me.p10)}`),
      el("span", {}, `P50 ${fmt.points(me.p50)}`),
      el("span", {}, `P90 ${fmt.points(me.p90)}`)));

  // action center — top of each native recommendation list, no re-ranking
  const actions = [];
  if (lineupRecs[0]) {
    const r = lineupRecs[0];
    actions.push({ kind: "START", headline: `${r.player_in_name} → bench ${r.player_out_name}`,
      impact: `${fmt.deltaPts(r.delta_expected)} · ${fmt.deltaPp(r.delta_win_probability)} win` });
  }
  if (bestWaiver) {
    actions.push({ kind: "ADD", headline: `${bestWaiver.add_player_name} → drop ${bestWaiver.drop_player_name}`,
      impact: `${fmt.deltaPts(bestWaiver.delta_expected)} · ${fmt.deltaPp(bestWaiver.delta_win_probability)} win` });
  }
  if (bestTrade) {
    actions.push({ kind: "TRADE", headline: `${bestTrade.receive_player_name} ↔ ${bestTrade.give_player_name} (${bestTrade.other_team_name})`,
      impact: `you ${fmt.deltaPts(bestTrade.my_delta_expected)} · partner ${fmt.deltaPts(bestTrade.their_delta_expected)} · score ${fmt.points(bestTrade.trade_score)}` });
  }

  root.replaceChildren(
    hero,
    el("div", { style: "display:flex;gap:10px;flex-wrap:wrap;margin:14px 0" },
      kpi("Win prob", fmt.prob(me.win, 0)),
      kpi("Expected", fmt.points(me.exp)),
      kpi("Optimal", ev ? fmt.points(ev.optimal_expected) : "–"),
      kpi("Lineup edge", ev ? fmt.deltaPts(ev.delta_expected) : "–"),
      kpi("Best waiver", bestWaiver ? fmt.deltaPts(bestWaiver.delta_expected) : "–"),
      kpi("Best trade", bestTrade ? fmt.deltaPts(bestTrade.my_delta_expected) : "–")),
    el("div", { style: "display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start" },
      el("div", {},
        el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin-bottom:6px" }, "ACTION CENTER"),
        actions.length ? actions.map(actionCard) : banner("empty", "No lineup, waiver or trade move recommended.")),
      leagueBoard(matchups)),
  );

  probabilityBar(document.getElementById("cc-winbar"),
    { labelA: me.name, probA: me.win, labelB: opp.name, probB: opp.win });
}
