// Rank — the league race week by week, in the bump-chart style of the old
// weekly recap (ggbump + team logos): standings, cumulative points, survival.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel } from "../components.js";
import { bumpChart } from "../charts.js";

const record = (r) => `${r.wins}-${r.losses}${r.ties ? `-${r.ties}` : ""}`;

export async function render(root) {
  const { teamId } = state.get();
  const rows = await data.getLeagueRanks();
  if (!rows.length) { mount(root, banner("empty", "Nenhuma semana encerrada ainda.")); return; }

  const name = (r) => team(r.team_id).team_name;
  const lastOut = new Map(rows.filter((r) => r.eliminated).map((r) => [String(r.team_id), r.week]));

  mount(root,
    sectionLabel("Classificação"),
    card(el("div", { id: "rk-standing" }),
      el("div", { class: "note-inline" }, "Posição na tabela ao fim de cada semana: % de vitórias, desempate por pontos marcados. Embaixo do logo: campanha.")),

    sectionLabel("Pontos marcados (acumulado)"),
    card(el("div", { id: "rk-points" }),
      el("div", { class: "note-inline" }, "Posição no ranking de pontos marcados somados até cada semana. Embaixo do logo: total acumulado.")),

    sectionLabel("Survival"),
    card(el("div", { id: "rk-survival" }),
      el("div", { class: "note-inline" }, "Posição pela pontuação da semana entre os times ainda vivos. A menor pontuação de cada semana (anel vermelho) é eliminada e some das semanas seguintes. Embaixo do logo: pontos da semana.")),
  );

  const opts = { teamOf: team, selectedTeamId: teamId };

  bumpChart(document.getElementById("rk-standing"), rows.map((r) => ({
    week: r.week, team_id: r.team_id, rank: r.standing_rank, label: record(r),
    hover: `${name(r)}<br>semana ${r.week}: ${r.standing_rank}º · ${record(r)} · ${fmt.points(r.cum_points)} pts`,
  })), opts);

  bumpChart(document.getElementById("rk-points"), rows.map((r) => ({
    week: r.week, team_id: r.team_id, rank: r.points_rank, label: fmt.points(r.cum_points, 0),
    hover: `${name(r)}<br>semana ${r.week}: ${r.points_rank}º · ${fmt.points(r.cum_points)} pts acumulados`,
  })), opts);

  bumpChart(document.getElementById("rk-survival"), rows.filter((r) => r.survival_rank != null).map((r) => ({
    week: r.week, team_id: r.team_id, rank: r.survival_rank, label: fmt.points(r.points, 0), alert: r.eliminated,
    hover: `${name(r)}<br>semana ${r.week}: ${r.survival_rank}º · ${fmt.points(r.points)} pts` +
      (r.eliminated ? "<br>eliminado nesta semana" : lastOut.has(String(r.team_id)) ? `<br>eliminado na semana ${lastOut.get(String(r.team_id))}` : ""),
  })), opts);
}
