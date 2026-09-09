// Matchup Center — scoreboard + the probabilistic layer the model adds.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount } from "../app.js";
import { card, sectionLabel } from "../components.js";
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

  const switcher = el("select", { class: "field", style: "width:auto",
    onchange: (e) => { selectedId = e.target.value; render(root); } },
    ...matchups.map((x) => el("option", { value: x.matchup_id, selected: String(x.matchup_id) === String(selectedId) ? "" : null },
      `${x.home_team_name} vs ${x.away_team_name}`)));

  mount(root,
    el("div", { class: "toolbar" },
      el("span", { class: "stat__sub" }, "Matchup"), switcher),
    card(
      el("div", { class: "hero" },
        el("div", { class: "hero__side" },
          el("div", { class: "stat__value", style: "font-size:32px;font-weight:700" }, fmt.points(m.home_expected)),
          el("div", { class: "hero__team" }, m.home_team_name + " · expected")),
        el("div", { class: "hero__side" },
          el("div", { class: "stat__value", style: "font-size:32px;font-weight:700" }, fmt.points(m.away_expected)),
          el("div", { class: "hero__team" }, m.away_team_name + " · expected"))),
      el("div", { id: "mu-winbar", style: "margin:14px 0 4px" }),
      el("div", { style: "text-align:center;font-size:13px;color:var(--muted)" },
        `${fmt.prob(m.home_win_probability, 0)} — ${fmt.prob(m.away_win_probability, 0)}` +
        (m.tie_probability > 0.001 ? ` · tie ${fmt.prob(m.tie_probability, 1)}` : ""))),
    sectionLabel("Scoring range (P10 – P50 – P90)"),
    el("div", { id: "mu-range" }),
    el("div", { class: "grid-2", style: "margin-top:16px" },
      el("div", {}, sectionLabel(m.home_team_name + " starters"), el("div", { id: "mu-home" })),
      el("div", {}, sectionLabel(m.away_team_name + " starters"), el("div", { id: "mu-away" }))),
    sectionLabel("All league matchups"),
    el("div", {}, ...matchups.map((x) => el("div", {
      style: "display:flex;gap:8px;padding:4px 0;font-size:13px;cursor:pointer" +
        (String(x.matchup_id) === String(selectedId) ? ";color:var(--accent)" : ""),
      onclick: () => { selectedId = x.matchup_id; render(root); } },
      el("span", { style: "flex:1;text-align:right" }, x.home_team_name),
      el("span", { class: "player-row__num", style: "width:38px;color:var(--muted)" }, fmt.prob(x.home_win_probability, 0)),
      el("span", { style: "color:var(--muted)" }, "vs"),
      el("span", { class: "player-row__num", style: "width:38px;color:var(--muted);text-align:left" }, fmt.prob(x.away_win_probability, 0)),
      el("span", { style: "flex:1" }, x.away_team_name)))),
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
