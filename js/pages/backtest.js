// Acerto do modelo — for every closed week, how many matchup winners the
// model called: the pre-kickoff projection (preTNF in practice) applied to the
// starters that actually played, against the real score.
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel, statRow, statTile, rankTable, teamBadge } from "../components.js";
import { baseLayout } from "../charts.js";

const hitRate = (rs) => {
  const scored = rs.filter((r) => r.correct != null);
  const hits = scored.filter((r) => r.correct).length;
  return { hits, n: scored.length, pct: scored.length ? hits / scored.length : null };
};
const ofN = (h) => `${h.hits} de ${h.n}`;

export async function render(root) {
  const rows = await data.getMatchupBacktest();
  if (!rows.length) { mount(root, banner("empty", "Nenhuma semana encerrada ainda.")); return; }

  const weeks = [...new Set(rows.map((r) => r.week))].map((w) => {
    const rs = rows.filter((r) => r.week === w);
    return { week: w, tag: rs[0].tag, ...hitRate(rs) };
  });
  const total = hitRate(rows);
  const ranked = weeks.filter((w) => w.pct != null).sort((a, b) => b.pct - a.pct || a.week - b.week);
  const best = ranked[0], worst = ranked[ranked.length - 1];
  const missing = rows.reduce((s, r) => s + (r.home_n_missing || 0) + (r.away_n_missing || 0), 0);

  const side = (r, s) => el("span", {}, teamBadge(team(r[`${s}_team_id`]), { strong: r.winner === s.toUpperCase() }));
  const score = (s) => (v, r) => `${fmt.points(r[`${s}_projected`])} · ${fmt.points(r[`${s}_points`])}`;

  mount(root,
    sectionLabel("Resumo"),
    statRow([
      statTile("Acerto geral", fmt.prob(total.pct), ofN(total), { accent: true, xl: true }),
      statTile("Semanas fechadas", weeks.length),
      best ? statTile("Melhor semana", `semana ${best.week}`, `${ofN(best)} · ${fmt.prob(best.pct, 0)}`) : null,
      worst ? statTile("Pior semana", `semana ${worst.week}`, `${ofN(worst)} · ${fmt.prob(worst.pct, 0)}`) : null,
    ].filter(Boolean)),

    sectionLabel("Acerto por semana"),
    card(el("div", { id: "bt-weeks" }),
      el("div", { class: "note-inline" },
        "Para cada semana encerrada: projeção do último snapshot antes do primeiro jogo (na prática o preTNF), ",
        "somada sobre os titulares que de fato jogaram (escalação do final). Vence quem tem o maior total projetado. ",
        "Linha pontilhada: 50%, cara ou coroa. Empates reais ficam fora da conta.")),

    sectionLabel("Confrontos"),
    card(
      rankTable(rows, [
        { key: "week", label: "Sem.", num: true, tight: true },
        { key: "home_team_id", label: "Casa", fmt: (v, r) => side(r, "home") },
        { key: "home_projected", label: "Proj · Real", num: true, fmt: score("home") },
        { key: "away_team_id", label: "Fora", fmt: (v, r) => side(r, "away") },
        { key: "away_projected", label: "Proj · Real", num: true, fmt: score("away") },
        { key: "correct", label: "Acertou", tight: true,
          fmt: (v) => v == null ? "empate" : el("span", { class: v ? "delta--pos" : "delta--neg" }, v ? "✓" : "✗") },
      ]),
      el("div", { class: "note-inline" },
        "Proj = pontos projetados antes do kickoff; Real = placar final. Vencedor real em negrito.",
        missing ? ` ${missing} titular(es) sem projeção contaram 0.` : "")),
  );

  window.Plotly.react(document.getElementById("bt-weeks"), [{
    type: "bar",
    x: weeks.map((w) => w.week), y: weeks.map((w) => w.pct),
    marker: { color: weeks.map((w) => (w.pct >= 0.5 ? "#00fff9" : "#3860be")), opacity: 0.75 },
    text: weeks.map((w) => fmt.prob(w.pct, 0)), textposition: "outside",
    hovertext: weeks.map((w) => `semana ${w.week}: ${ofN(w)} · ${w.tag}`),
    hovertemplate: "%{hovertext}<extra></extra>",
  }], baseLayout({
    height: 300,
    xaxis: { title: { text: "semana", font: { color: "#9298ae" } }, dtick: 1, tickfont: { color: "#9298ae" } },
    yaxis: { range: [0, 1.1], tickformat: ".0%", tickfont: { color: "#9298ae" }, gridcolor: "rgba(255,255,255,0.06)" },
    shapes: [{ type: "line", xref: "paper", x0: 0, x1: 1, y0: 0.5, y1: 0.5,
      line: { color: "#4c5579", dash: "dot", width: 1 } }],
    showlegend: false,
  }), { displayModeBar: false, responsive: true });
}
