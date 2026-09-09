// Waiver Wire Center — add/drop moves ranked by team gain, not player rank.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, posBadge, coverageDot, deltaSpan, rankTable, drawer, kv } from "../components.js";
import { waiverScatter } from "../charts.js";

let faPos = "ALL";

async function detail(rec) {
  const [addF, dropF] = await Promise.all([
    rec.add_ffa_id ? data.getForecast(rec.add_ffa_id) : null,
    rec.drop_ffa_id ? data.getForecast(rec.drop_ffa_id) : null,
  ]);
  const cmp = (label, d, a, isProb) => kv(label,
    `${isProb ? fmt.prob(d) : fmt.points(d)}  →  ${isProb ? fmt.prob(a) : fmt.points(a)}`);
  drawer(`${rec.add_player_name} → ${rec.drop_player_name}`,
    sectionLabel("Team impact"),
    kv("Expected", `${fmt.points(rec.before_expected)} → ${fmt.points(rec.after_expected)}`),
    kv("Win probability", `${fmt.prob(rec.before_win_probability)} → ${fmt.prob(rec.after_win_probability)}`),
    el("div", { class: "stat__sub", style: "margin-top:6px" },
      deltaSpan(rec.delta_expected, "pts"), " · ", deltaSpan(rec.delta_win_probability, "pp"), " win"),
    sectionLabel("Drop → Add"),
    cmp("Projection", dropF?.projection, addF?.projection),
    cmp("Sim mean", dropF?.sim_mean, addF?.sim_mean),
    cmp("P10", dropF?.p10, addF?.p10),
    cmp("P50", dropF?.p50, addF?.p50),
    cmp("P90", dropF?.p90, addF?.p90),
    cmp("P(>15)", dropF?.prob_gt_15, addF?.prob_gt_15, true));
}

export async function render(root) {
  const { teamId } = state.get();
  const recs = await data.getWaiverRecommendations(teamId);

  mount(root,
    
    sectionLabel("Add / drop — Δ expected vs Δ win probability"),
    recs.length ? card(el("div", { id: "wv-scatter" })) : banner("empty", "No acceptable waiver move found this week."),
    recs.length ? sectionLabel("Recommendations") : null,
    recs.length ? rankTable(recs, [
      { key: "recommendation_rank", label: "#", num: true },
      { key: "add_player_name", label: "Add", fmt: (v, r) => el("span", {}, posBadge(r.add_position), " ", v) },
      { key: "drop_player_name", label: "Drop", fmt: (v, r) => el("span", {}, posBadge(r.drop_position), " ", v) },
      { key: "delta_expected", label: "Δ pts", num: true, fmt: (v) => deltaSpan(v, "pts") },
      { key: "delta_win_probability", label: "Δ win", num: true, fmt: (v) => deltaSpan(v, "pp") },
    ], { onRow: detail }) : null,

    sectionLabel("Free agent explorer"),
    el("div", { class: "toolbar" },
      ...["ALL", "QB", "RB", "WR", "TE", "K", "DST"].map((p) =>
        el("button", { class: "chip" + (p === faPos ? " active" : ""),
          onclick: () => { faPos = p; render(root); } }, p))),
    el("div", { id: "wv-fa" }),
  );

  if (recs.length) waiverScatter(document.getElementById("wv-scatter"), recs);

  const fa = (await data.getFreeAgents({ position: faPos })).slice(0, 40);
  document.getElementById("wv-fa").replaceChildren(rankTable(fa, [
    { key: "player_name", label: "Player" },
    { key: "position", label: "Pos", fmt: (v) => posBadge(v) },
    { key: "nfl_team", label: "Team" },
    { key: "sim_mean", label: "Sim", num: true, fmt: (v) => fmt.points(v) },
    { key: "p90", label: "P90", num: true, fmt: (v) => fmt.points(v) },
    { key: "coverage_class", label: "Cov", num: true, fmt: (v) => coverageDot(v) },
  ], { empty: "No free agents for this position." }));
}
