// Command Center — full build in M3. M2 stub: prove the data path.
import * as data from "../data.js";
import { el, banner } from "../app.js";

export async function render(root) {
  const [my, health] = await Promise.all([data.getMyMatchup(), data.getDataHealth()]);
  if (!my) { root.replaceChildren(banner("empty", "No matchup for the selected run.")); return; }
  root.replaceChildren(
    el("p", { class: "text-muted" }, "M2 stub — hero, KPIs and Action Center land in M3."),
    el("div", { class: "cockpit-card" },
      el("div", {}, `${my.home_team_name} ${my.home_expected?.toFixed(1)} — ${my.away_expected?.toFixed(1)} ${my.away_team_name}`),
      el("div", {}, `Win probability: ${(my.home_win_probability * 100).toFixed(1)}% / ${(my.away_win_probability * 100).toFixed(1)}%`)),
    el("p", { class: "text-muted" }, `Data health: ${health?.status} · ${health?.n_forecast_players} forecasts · ${health?.n_mapped_starters}/${health?.n_starters} starters mapped`),
  );
}
