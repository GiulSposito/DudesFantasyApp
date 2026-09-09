// Waiver Wire Center — add/drop moves ranked by team gain, not player rank.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel, posBadge, coverageDot, deltaSpan, rankTable, drawer } from "../components.js";
import { waiverScatter } from "../charts.js";

let faPos = "ALL";

async function detail(rec) {
  const [addF, dropF] = await Promise.all([
    rec.add_ffa_id ? data.getForecast(rec.add_ffa_id) : null,
    rec.drop_ffa_id ? data.getForecast(rec.drop_ffa_id) : null,
  ]);
  const line = (label, a, b, isProb) => el("tr", {},
    el("th", { style: "color:#9298ae;font-weight:400" }, label),
    el("td", { style: "text-align:right" }, isProb ? fmt.prob(a) : fmt.points(a)),
    el("td", { style: "text-align:right" }, isProb ? fmt.prob(b) : fmt.points(b)));
  drawer(`${rec.add_player_name} → ${rec.drop_player_name}`,
    sectionLabel("Team impact"),
    el("table", { class: "table table-sm table-dark" }, el("tbody", {},
      line("Expected", rec.before_expected, rec.after_expected),
      line("Win probability", rec.before_win_probability, rec.after_win_probability, true))),
    el("div", { style: "color:#9298ae;font-size:13px" },
      deltaSpan(rec.delta_expected, "pts"), " · ", deltaSpan(rec.delta_win_probability, "pp"), " win"),
    sectionLabel("Drop vs add"),
    el("table", { class: "table table-sm table-dark" },
      el("thead", {}, el("tr", {}, el("th", {}, ""), el("th", { style: "text-align:right" }, "DROP"), el("th", { style: "text-align:right" }, "ADD"))),
      el("tbody", {},
        line("Projection", dropF?.projection, addF?.projection),
        line("Sim mean", dropF?.sim_mean, addF?.sim_mean),
        line("P10", dropF?.p10, addF?.p10),
        line("P50", dropF?.p50, addF?.p50),
        line("P90", dropF?.p90, addF?.p90),
        line("P(>15)", dropF?.prob_gt_15, addF?.prob_gt_15, true))));
}

export async function render(root) {
  const { teamId } = state.get();
  const recs = await data.getWaiverRecommendations(teamId);

  mount(root,
    
    sectionLabel("Add / drop — Δ expected vs Δ win probability"),
    recs.length ? card(el("div", { id: "wv-scatter" })) : banner("empty", "No acceptable waiver move found this week."),
    recs.length ? sectionLabel("Recommendations") : null,
    recs.length ? rankTable(recs, [
      { key: "recommendation_rank", label: "#", align: "right" },
      { key: "add_player_name", label: "Add", fmt: (v, r) => el("span", {}, posBadge(r.add_position), " ", v) },
      { key: "drop_player_name", label: "Drop", fmt: (v, r) => el("span", {}, posBadge(r.drop_position), " ", v) },
      { key: "delta_expected", label: "Δ pts", align: "right", fmt: (v) => deltaSpan(v, "pts") },
      { key: "delta_win_probability", label: "Δ win", align: "right", fmt: (v) => deltaSpan(v, "pp") },
    ], { onRow: detail }) : null,

    sectionLabel("Free agent explorer"),
    el("div", { style: "margin-bottom:8px" },
      ...["ALL", "QB", "RB", "WR", "TE", "K", "DST"].map((p) =>
        el("button", { class: "btn btn-sm " + (p === faPos ? "btn-info" : "btn-outline-secondary"),
          style: "margin-right:4px", onclick: () => { faPos = p; render(root); } }, p))),
    el("div", { id: "wv-fa" }),
  );

  if (recs.length) waiverScatter(document.getElementById("wv-scatter"), recs);

  const fa = (await data.getFreeAgents({ position: faPos })).slice(0, 40);
  document.getElementById("wv-fa").replaceChildren(rankTable(fa, [
    { key: "player_name", label: "Player" },
    { key: "position", label: "Pos", fmt: (v) => posBadge(v) },
    { key: "nfl_team", label: "Team" },
    { key: "sim_mean", label: "Sim", align: "right", fmt: (v) => fmt.points(v) },
    { key: "p90", label: "P90", align: "right", fmt: (v) => fmt.points(v) },
    { key: "coverage_class", label: "Cov", align: "right", fmt: (v) => coverageDot(v) },
  ], { empty: "No free agents for this position." }));
}
