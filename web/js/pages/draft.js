// Draft — how the season's draft is paying off: top scorers, the teams that
// drafted best, steals and busts, waiver finds and decision vs luck
// (draft/draft.parquet, contract section 27).
import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel, statRow, statTile, rankTable, teamBadge, avatar, posBadge, chips, deltaSpan } from "../components.js";
import { baseLayout, POS_COLOR } from "../charts.js";

let position = "ALL";
let topN = 25;
let metric = "vor";            // vor = VOR over expected · rank = positional rank gained

const MUTED = "#9298ae";
const GRID = "rgba(255,255,255,0.06)";
const ZERO = { color: "#4c5579", dash: "dot", width: 1 };

const pick = (r) => `${r.round}.${String(r.round_pick).padStart(2, "0")}`;
const posRank = (r, k) => (r[k] == null ? "–" : `${fmt.pos(r.position)}${r[k]}`);
const path = (r) => `${posRank(r, "draft_pos_rank")} → ${posRank(r, "pos_rank")}`;
const player = (r) => el("span", { class: "player-cell" }, avatar(r, { size: 28 }), posBadge(r.position), " ", r.player_name);
const teamCell = (id, none = "–") => (id == null ? el("span", { class: "stat__sub" }, none) : teamBadge(team(id), { size: 18 }));
// whole positions: +31 / −8, coloured like deltaSpan
const rankDelta = (v) => (v == null ? "–"
  : el("span", { class: `delta ${v > 0 ? "delta--pos" : v < 0 ? "delta--neg" : "delta--zero"}` },
    `${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.abs(v)}`));
const perWeek = (r) => (r.weeks_scored ? r.points / r.weeks_scored : null);
const sum = (rs, k) => rs.reduce((s, r) => s + (r[k] ?? 0), 0);
const mean = (rs, k) => { const v = rs.filter((r) => r[k] != null); return v.length ? sum(v, k) / v.length : null; };
const byMetric = (a, b) => (metric === "rank"
  ? (b.pos_rank_delta ?? -Infinity) - (a.pos_rank_delta ?? -Infinity) || b.value_over_expected - a.value_over_expected
  : b.value_over_expected - a.value_over_expected);

export async function render(root) {
  const rows = await data.getDraft();
  const drafted = rows.filter((r) => r.overall_pick != null);
  if (!drafted.length) { mount(root, banner("empty", "Sem dados de draft para esta temporada.")); return; }

  // ---- teams --------------------------------------------------------------
  const teams = [...new Set(drafted.map((r) => String(r.draft_team_id)))].map((id) => {
    const rs = drafted.filter((r) => String(r.draft_team_id) === id);
    const ranked = [...rs].sort((a, b) => b.value_over_expected - a.value_over_expected);
    return {
      team_id: id, voe: sum(rs, "value_over_expected"), decision: sum(rs, "decision_value"),
      luck: sum(rs, "luck_value"), rank_delta: mean(rs, "pos_rank_delta"), points: sum(rs, "points"),
      best: ranked[0], worst: ranked[ranked.length - 1],
    };
  }).sort((a, b) => (metric === "rank" ? b.rank_delta - a.rank_delta : b.voe - a.voe));

  const sorted = [...drafted].sort(byMetric);
  const steals = sorted.slice(0, 10);
  const busts = sorted.slice(-10).reverse();
  const finds = rows.filter((r) => r.overall_pick == null).sort((a, b) => b.vor - a.vor).slice(0, 10);
  const top = rows.filter((r) => position === "ALL" || fmt.pos(r.position) === position)
    .sort((a, b) => b.points - a.points).slice(0, topN);

  const pickCols = [
    { key: "overall_pick", label: "Pick", num: true, tight: true, fmt: (v, r) => el("span", { title: `${v}ª escolha geral` }, pick(r)) },
    { key: "player_name", label: "Jogador", fmt: (v, r) => player(r) },
    { key: "draft_team_id", label: "Draftado por", fmt: (v) => teamCell(v) },
    { key: "pos_rank", label: "Draft → hoje", title: "Ordem em que saiu na posição → rank atual na posição", fmt: (v, r) => path(r) },
    { key: "points", label: "Pontos", num: true, fmt: (v) => fmt.points(v) },
    { key: "value_over_expected", label: "Saldo VOR", num: true,
      title: "VOR menos a média de VOR das picks em volta (≈ uma rodada)", fmt: (v) => deltaSpan(v) },
    { key: "pos_rank_delta", label: "Δ rank", num: true, title: "Posições ganhas na posição desde o draft", fmt: rankDelta },
  ];
  const metricBar = el("div", { class: "toolbar" },
    el("span", { class: "stat__sub" }, "métrica"),
    ...chips(["vor", "rank"], metric, (m) => { metric = m; render(root); },
      { vor: "VOR vs esperado", rank: "Rank na posição" }));

  mount(root,
    statRow([
      statTile("Melhor draft", team(teams[0].team_id).team_name, metricLabel(teams[0]), { accent: true }),
      statTile("Pior draft", team(teams[teams.length - 1].team_id).team_name, metricLabel(teams[teams.length - 1])),
      statTile("Maior achado", steals[0].player_name, `pick ${pick(steals[0])} · ${path(steals[0])}`),
      statTile("Maior decepção", busts[0].player_name, `pick ${pick(busts[0])} · ${path(busts[0])}`),
    ]),

    sectionLabel("Top jogadores da temporada"),
    el("div", { class: "toolbar" },
      ...chips(["ALL", "QB", "RB", "WR", "TE", "K", "DST"], position, (p) => { position = p; render(root); }, { ALL: "Todos" }),
      el("span", { class: "stat__sub" }, "top"),
      ...chips([10, 25, 50], topN, (n) => { topN = n; render(root); })),
    rankTable(top, [
      { key: "pos_rank", label: "#", num: true, tight: true, fmt: (v, r) => String(top.indexOf(r) + 1) },
      { key: "player_name", label: "Jogador", fmt: (v, r) => player(r) },
      { key: "pos_rank", label: "Rank", fmt: (v, r) => posRank(r, "pos_rank") },
      { key: "points", label: "Pontos", num: true, fmt: (v) => el("b", {}, fmt.points(v)) },
      { key: "weeks_scored", label: "Pts/sem", num: true, title: "Pontos por semana em que pontuou (bye / fora do jogo não contam)",
        fmt: (v, r) => fmt.points(perWeek(r)) },
      { key: "vor", label: "VOR", num: true, title: "Pontos acima do jogador de reposição da posição", fmt: (v) => fmt.points(v) },
      { key: "overall_pick", label: "Draft", fmt: (v, r) => (v == null ? el("span", { class: "stat__sub" }, "não draftado")
        : el("span", { class: "player-cell" }, pick(r), " ", teamCell(r.draft_team_id))) },
      { key: "owner_team_id", label: "Dono atual", fmt: (v) => teamCell(v, "livre") },
    ]),

    sectionLabel("Ranking dos drafts"),
    metricBar,
    rankTable(teams, [
      { key: "team_id", label: "#", num: true, tight: true, fmt: (v, r) => String(teams.indexOf(r) + 1) },
      { key: "team_id", label: "Time", fmt: (v) => teamBadge(team(v), { size: 22 }) },
      { key: "voe", label: "Saldo VOR", num: true, title: "Soma do saldo VOR de todas as picks", fmt: (v) => deltaSpan(v) },
      { key: "decision", label: "Decisão", num: true, title: "Parte do saldo explicada pela projeção pré-temporada", fmt: (v) => deltaSpan(v) },
      { key: "luck", label: "Sorte", num: true, title: "Parte do saldo que veio do desempenho acima / abaixo da projeção", fmt: (v) => deltaSpan(v) },
      { key: "rank_delta", label: "Δ rank médio", num: true, title: "Média de posições ganhas na posição por pick",
        fmt: (v) => (v == null ? "–" : deltaSpan(v, "raw")) },
      { key: "points", label: "Pontos", num: true, title: "Pontos dos jogadores draftados (onde estiverem hoje)", fmt: (v) => fmt.points(v, 0) },
      { key: "best", label: "Melhor pick", fmt: (v) => `${v.player_name} (${pick(v)}) · ${path(v)}` },
      { key: "worst", label: "Pior pick", fmt: (v) => `${v.player_name} (${pick(v)}) · ${path(v)}` },
    ]),

    sectionLabel("Valor por pick"),
    card(el("div", { id: "dr-curve" }),
      el("div", { class: "note-inline" },
        "Cada ponto é uma pick: VOR = pontos acima do jogador de reposição da posição (o melhor fora das escalações titulares da liga). ",
        "A linha é o esperado da pick, a média de VOR das picks em volta (≈ uma rodada). Acima da linha = achado; abaixo = decepção.")),

    sectionLabel("Achados"),
    rankTable(steals, pickCols),
    sectionLabel("Decepções"),
    rankTable(busts, pickCols),

    sectionLabel("Achados do waiver"),
    rankTable(finds, [
      { key: "player_name", label: "Jogador", fmt: (v, r) => player(r) },
      { key: "pos_rank", label: "Rank", fmt: (v, r) => posRank(r, "pos_rank") },
      { key: "points", label: "Pontos", num: true, fmt: (v) => fmt.points(v) },
      { key: "vor", label: "VOR", num: true, fmt: (v) => fmt.points(v) },
      { key: "owner_team_id", label: "Dono atual", fmt: (v) => teamCell(v, "livre") },
    ], { empty: "Nenhum jogador não draftado pontuou ainda." }),

    sectionLabel("Decisão vs sorte"),
    card(el("div", { id: "dr-luck" }),
      el("div", { class: "note-inline" },
        "Decisão: o VOR que a projeção pré-temporada da ESPN (a do draft room) previa para o jogador até aqui, menos o previsto para as picks em volta. ",
        "Sorte: o resto do saldo, quanto o jogador rendeu acima ou abaixo da projeção. Decisão + sorte = saldo VOR. ",
        "Pontos da temporada até o último snapshot; jogador trocado ou dispensado continua creditado a quem draftou.")),
  );

  drawCurve(document.getElementById("dr-curve"), drafted);
  drawLuck(document.getElementById("dr-luck"), drafted);
}

function metricLabel(t) {
  return metric === "rank"
    ? `${fmt.points(t.rank_delta)} posições por pick`
    : `${t.voe >= 0 ? "+" : "−"}${fmt.points(Math.abs(t.voe), 0)} de saldo VOR`;
}

const hover = (r) => `${r.player_name} (${fmt.pos(r.position)}) · pick ${pick(r)}<br>${team(r.draft_team_id).team_name}`;
const byPos = (rs) => Object.keys(POS_COLOR).map((p) => [p, rs.filter((r) => fmt.pos(r.position) === p)]).filter(([, v]) => v.length);

function drawCurve(node, rs) {
  const line = [...rs].sort((a, b) => a.overall_pick - b.overall_pick);
  window.Plotly.react(node, [
    ...byPos(rs).map(([p, v]) => ({
      type: "scatter", mode: "markers", name: p, x: v.map((r) => r.overall_pick), y: v.map((r) => r.vor),
      marker: { size: 7, color: POS_COLOR[p], opacity: 0.85 },
      hovertext: v.map((r) => `${hover(r)}<br>VOR ${fmt.points(r.vor)} · esperado ${fmt.points(r.vor_expected)}`),
      hovertemplate: "%{hovertext}<extra></extra>",
    })),
    { type: "scatter", mode: "lines", name: "esperado", x: line.map((r) => r.overall_pick), y: line.map((r) => r.vor_expected),
      line: { color: "#d8d8d8", width: 2 }, hoverinfo: "skip" },
  ], baseLayout({
    height: 360,
    xaxis: { title: { text: "pick geral", font: { color: MUTED } }, gridcolor: GRID, tickfont: { color: MUTED }, zeroline: false },
    yaxis: { title: { text: "VOR (pontos)", font: { color: MUTED } }, gridcolor: GRID, tickfont: { color: MUTED }, zeroline: true, zerolinecolor: "#4c5579" },
    legend: { orientation: "h", y: 1.08, font: { color: MUTED } },
  }), { displayModeBar: false, responsive: true });
}

function drawLuck(node, rs) {
  const corner = (x, y, text, xanchor, yanchor) => ({ xref: "paper", yref: "paper", x, y, text, showarrow: false,
    xanchor, yanchor, font: { color: MUTED, size: 11 } });
  window.Plotly.react(node, byPos(rs).map(([p, v]) => ({
    type: "scatter", mode: "markers", name: p, x: v.map((r) => r.decision_value), y: v.map((r) => r.luck_value),
    marker: { size: 7, color: POS_COLOR[p], opacity: 0.85 },
    hovertext: v.map((r) => `${hover(r)}<br>decisão ${fmt.deltaPts(r.decision_value)} · sorte ${fmt.deltaPts(r.luck_value)}`),
    hovertemplate: "%{hovertext}<extra></extra>",
  })), baseLayout({
    height: 420,
    xaxis: { title: { text: "decisão (pontos)", font: { color: MUTED } }, gridcolor: GRID, tickfont: { color: MUTED }, zeroline: false },
    yaxis: { title: { text: "sorte (pontos)", font: { color: MUTED } }, gridcolor: GRID, tickfont: { color: MUTED }, zeroline: false },
    shapes: [
      { type: "line", x0: 0, x1: 0, yref: "paper", y0: 0, y1: 1, line: ZERO },
      { type: "line", y0: 0, y1: 0, xref: "paper", x0: 0, x1: 1, line: ZERO },
    ],
    annotations: [
      corner(1, 1, "boa escolha, deu certo", "right", "top"),
      corner(0, 1, "escolha ruim, salvou na sorte", "left", "top"),
      corner(1, 0, "boa escolha, deu azar", "right", "bottom"),
      corner(0, 0, "escolha ruim, deu errado", "left", "bottom"),
    ],
    legend: { orientation: "h", y: 1.08, font: { color: MUTED } },
  }), { displayModeBar: false, responsive: true });
}
