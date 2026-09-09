// Matchup Center — scoreboard + the probabilistic layer the model adds.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { probabilityBar, intervalRange, contributionBars } from "../charts.js";

let selectedId = null;

async function starterContribution(teamId) {
  const roster = await data.getRoster(teamId);
  return roster.filter((r) => r.is_starter)
    .sort((a, b) => a.lineup_slot_id - b.lineup_slot_id)
    .map((r) => ({ label: `${r.lineup_slot} ${r.player_name.split(" ").slice(-1)[0]}`, value: r.sim_mean, pos: fmt.pos(r.position) }));
}

export async function render(root) {
  const { teamId } = state.get();
  const matchups = await data.getMatchups();
  if (!matchups.length) { mount(root,
    banner("empty", "No matchups for this run.")); return; }

  if (selectedId == null || !matchups.find((m) => String(m.matchup_id) === String(selectedId))) {
    const mine = matchups.find((m) => String(m.home_team_id) === String(teamId) || String(m.away_team_id) === String(teamId));
    selectedId = (mine || matchups[0]).matchup_id;
  }
  const m = matchups.find((x) => String(x.matchup_id) === String(selectedId));

  const switcher = el("select", { class: "form-select form-select-sm", style: "width:auto",
    onchange: (e) => { selectedId = e.target.value; render(root); } },
    ...matchups.map((x) => el("option", { value: x.matchup_id, selected: String(x.matchup_id) === String(selectedId) ? "" : null },
      `${x.home_team_name} vs ${x.away_team_name}`)));

  mount(root,
    
    el("div", { style: "display:flex;gap:12px;align-items:center;margin-bottom:12px" },
      el("span", { style: "color:#9298ae;font-size:13px" }, "Matchup"), switcher),
    el("div", { class: "cockpit-card" },
      el("div", { style: "display:flex;justify-content:space-around;text-align:center" },
        el("div", {}, el("div", { style: "font-size:32px;font-weight:700;color:#fff" }, fmt.points(m.home_expected)),
          el("div", { style: "font-size:12px;color:#9298ae" }, m.home_team_name + " · expected")),
        el("div", {}, el("div", { style: "font-size:32px;font-weight:700;color:#fff" }, fmt.points(m.away_expected)),
          el("div", { style: "font-size:12px;color:#9298ae" }, m.away_team_name + " · expected"))),
      el("div", { id: "mu-winbar", style: "margin:12px 0 4px" }),
      el("div", { style: "text-align:center;font-size:13px;color:#9298ae" },
        `${fmt.prob(m.home_win_probability, 0)} — ${fmt.prob(m.away_win_probability, 0)}` +
        (m.tie_probability > 0.001 ? ` · tie ${fmt.prob(m.tie_probability, 1)}` : ""))),
    el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin:16px 0 4px" }, "SCORING RANGE (P10 – P50 – P90)"),
    el("div", { id: "mu-range" }),
    el("div", { class: "grid-2", style: "margin-top:16px" },
      el("div", {}, el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin-bottom:4px" }, m.home_team_name.toUpperCase() + " STARTERS"),
        el("div", { id: "mu-home" })),
      el("div", {}, el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin-bottom:4px" }, m.away_team_name.toUpperCase() + " STARTERS"),
        el("div", { id: "mu-away" }))),
    el("div", { style: "font-size:11px;letter-spacing:.06em;color:#9298ae;margin:18px 0 4px" }, "ALL LEAGUE MATCHUPS"),
    el("div", {}, ...matchups.map((x) => el("div", {
      style: "display:flex;gap:8px;padding:3px 0;font-size:13px;cursor:pointer" + (String(x.matchup_id) === String(selectedId) ? ";color:#00fff9" : ""),
      onclick: () => { selectedId = x.matchup_id; render(root); } },
      el("span", { style: "width:160px;text-align:right" }, x.home_team_name),
      el("span", { style: "width:44px;text-align:right;color:#9298ae" }, fmt.prob(x.home_win_probability, 0)),
      el("span", { style: "color:#9298ae" }, "vs"),
      el("span", { style: "width:44px;color:#9298ae" }, fmt.prob(x.away_win_probability, 0)),
      el("span", { style: "width:160px" }, x.away_team_name)))),
  );

  probabilityBar(document.getElementById("mu-winbar"),
    { labelA: m.home_team_name, probA: m.home_win_probability, labelB: m.away_team_name, probB: m.away_win_probability });
  intervalRange(document.getElementById("mu-range"), [
    { label: m.home_team_name, p10: m.home_p10, p50: m.home_p50, p90: m.home_p90, color: "#00fff9" },
    { label: m.away_team_name, p10: m.away_p10, p50: m.away_p50, p90: m.away_p90, color: "#3860be" },
  ]);
  contributionBars(document.getElementById("mu-home"), await starterContribution(m.home_team_id));
  contributionBars(document.getElementById("mu-away"), await starterContribution(m.away_team_id));
}
