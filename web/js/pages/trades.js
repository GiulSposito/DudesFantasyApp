// Trade Center — 1×1 trades, impact shown for both teams.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, posBadge, deltaSpan, rankTable, drawer, fairnessMeter } from "../components.js";
import { tradeScatter } from "../charts.js";

function detail(t) {
  drawer(`${t.receive_player_name} ↔ ${t.give_player_name}`,
    el("div", { style: "color:#9298ae;font-size:13px;margin-bottom:8px" }, `Partner: ${t.other_team_name}`),
    t.partner_is_my_opponent
      ? el("div", { class: "cockpit-banner stale" }, "⚠ This manager is your current-week opponent — the win-probability impact may be optimistic.")
      : null,
    sectionLabel("You"),
    el("div", {}, "give ", el("span", {}, posBadge(t.give_position), " ", t.give_player_name)),
    el("div", {}, "get ", el("span", {}, posBadge(t.receive_position), " ", t.receive_player_name)),
    el("div", { style: "margin-top:6px" }, "expected ", deltaSpan(t.my_delta_expected, "pts"),
      " · win ", deltaSpan(t.my_delta_win_probability, "pp")),
    sectionLabel("Partner"),
    el("div", {}, "expected ", deltaSpan(t.their_delta_expected, "pts")),
    sectionLabel("Fairness"),
    fairnessMeter(t.my_delta_expected - t.their_delta_expected),
    el("div", { style: "font-size:12px;color:#9298ae;margin-top:4px" },
      `fairness ${fmt.points(t.fairness, 2)} · trade score ${fmt.points(t.trade_score, 1)}`));
}

export async function render(root) {
  const { teamId } = state.get();
  const all = await data.getTradeRecommendations();
  const trades = all.filter((t) => String(t.my_team_id) === String(teamId));
  const rows = trades.length ? trades : all;

  if (!rows.length) { mount(root,
    banner("empty", "No mutually beneficial trade found this week.")); return; }

  // best trade per partner
  const byPartner = new Map();
  for (const t of rows) {
    const k = t.other_team_name;
    if (!byPartner.has(k) || byPartner.get(k).trade_score < t.trade_score) byPartner.set(k, t);
  }
  const partners = [...byPartner.values()].sort((a, b) => b.trade_score - a.trade_score);
  const maxScore = Math.max(...partners.map((p) => p.trade_score), 1);

  mount(root,
    
    rows.some((t) => t.partner_is_my_opponent)
      ? el("div", { class: "cockpit-banner stale" }, "⚠ Some partners are your current-week opponent — their win-probability impact may be optimistic.")
      : null,

    sectionLabel("Trade opportunity map — my Δ vs their Δ (bubble = trade score)"),
    card(el("div", { id: "tr-scatter" })),

    sectionLabel("Best trade by partner"),
    card(...partners.map((p) => el("div", {
      style: "display:flex;align-items:center;gap:10px;padding:4px 0;cursor:pointer", onclick: () => detail(p) },
      el("span", { style: "width:170px;color:#fff" }, p.other_team_name),
      el("div", { style: "flex:1;height:8px;background:#131b38;border-radius:4px;overflow:hidden" },
        el("div", { style: `width:${(p.trade_score / maxScore * 100).toFixed(0)}%;height:100%;background:#00fff9` })),
      el("span", { style: "width:80px;text-align:right;font-variant-numeric:tabular-nums" }, "+" + fmt.points(p.my_delta_expected)),
      p.partner_is_my_opponent ? el("span", { style: "color:#ffae58" }, "⚠") : null))),

    sectionLabel("All proposals"),
    rankTable(rows, [
      { key: "recommendation_rank", label: "#", align: "right" },
      { key: "other_team_name", label: "Partner" },
      { key: "receive_player_name", label: "Get", fmt: (v, r) => el("span", {}, posBadge(r.receive_position), " ", v) },
      { key: "give_player_name", label: "Give", fmt: (v, r) => el("span", {}, posBadge(r.give_position), " ", v) },
      { key: "my_delta_expected", label: "My Δ", align: "right", fmt: (v) => deltaSpan(v, "pts") },
      { key: "their_delta_expected", label: "Their Δ", align: "right", fmt: (v) => deltaSpan(v, "pts") },
      { key: "trade_score", label: "Score", align: "right", fmt: (v) => fmt.points(v, 1) },
      { key: "partner_is_my_opponent", label: "", fmt: (v) => (v ? "⚠" : "") },
    ], { onRow: detail }),
  );

  tradeScatter(document.getElementById("tr-scatter"), rows);
}
