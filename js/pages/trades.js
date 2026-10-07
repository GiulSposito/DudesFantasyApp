// Trocas — trade simulator (any 1×1, three lenses) + the engine's 1×1
// recommendations, impact shown for both teams.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel, posBadge, deltaSpan, rankTable, drawer, fairnessMeter, teamBadge, moveSide, gainBar, badge,
  avatar, oppLabel, playerLink } from "../components.js";
import { tradeScatter, strengthStrip, normalOverlay, SIM_ME, SIM_THEM } from "../charts.js";
import { evaluateTrade, weightedScore } from "../trade-sim.js";

// ---- simulator -----------------------------------------------------------

const LENS_INFO = {
  week: { title: "Semana", sub: "projeção desta semana", unit: "pts/sem" },
  season: { title: "Temporada", sub: "projeção ESPN do resto da temporada, por jogo", unit: "pts/sem" },
  perf: { title: "Desempenho", sub: "pontos reais por jogo até agora", unit: "pts/sem" },
};
const POS_ORDER = ["QB", "RB", "WR", "TE", "K", "D/ST"];
const EPS = 0.3;                                   // pts/week that count as "no change"

const sim = { give: null, partner: null, receive: null, team: null,
  weights: { week: 25, season: 55, perf: 20 }, strengthLens: "season" };

const byPosThenProj = (a, b) => POS_ORDER.indexOf(a.position) - POS_ORDER.indexOf(b.position) || (b.sim_mean ?? 0) - (a.sim_mean ?? 0);

// <select> of a roster, grouped by position
function playerSelect(players, current, label, onPick) {
  const groups = POS_ORDER.map((pos) => [pos, players.filter((p) => p.position === pos).sort(byPosThenProj)])
    .filter(([, ps]) => ps.length);
  return el("select", { class: "field", "aria-label": label, onchange: (e) => onPick(e.target.value || null) },
    el("option", { value: "" }, `${label}…`),
    ...groups.map(([pos, ps]) => el("optgroup", { label: pos },
      ...ps.map((p) => el("option", { value: p.player_id, selected: String(p.player_id) === String(current) ? "" : null },
        `${p.player_name} · ${fmt.points(p.sim_mean)}${p.is_ir ? " · IR" : ""}`)))));
}

function simSide(p, f, label, color) {
  return playerLink(el("div", { class: "sim-side" },
    avatar(p, { size: 52 }),
    el("div", { class: "sim-side__text" },
      el("div", { class: "sim-side__label", style: `color:${color}` }, label),
      el("div", { class: "sim-side__name", title: p.player_name }, p.player_name),
      el("div", { class: "sim-side__meta" }, `${f?.pos_rank != null ? fmt.pos(p.position) + f.pos_rank : fmt.pos(p.position)} · ${fmt.nflAbbr(p.nfl_team)} `,
        oppLabel(p)),
      el("div", { style: "margin-top:4px" }, teamBadge(team(p.team_id), { size: 18 })))), p);
}

// cede x recebe value bars of one lens, shared scale, with the VORP chip
function pairBars(L, r) {
  const max = Math.max(L.give.value, L.receive.value, 0.1);
  const row = (label, p, v, color) => el("div", { class: "sim-bar" },
    el("span", { class: "sim-bar__who", title: p.player_name }, label),
    el("div", { class: "bar" }, el("div", { class: "bar__fill", style: `width:${Math.max(0, v.value / max) * 100}%;background:${color}` })),
    el("span", { class: "sim-bar__v" }, fmt.points(v.value)),
    v.vor == null ? el("span") : el("span", { class: "sim-vor", title: "Acima do melhor free agent da posição (VORP)" },
      `${v.vor >= 0 ? "+" : "−"}${fmt.points(Math.abs(v.vor))} vs waiver`));
  return el("div", { class: "sim-bars" },
    row("cede", r.give, L.give, SIM_THEM), row("recebe", r.receive, L.receive, SIM_ME));
}

function lensPanel(lens, r) {
  const L = r.lenses[lens], info = LENS_INFO[lens];
  let foot;
  if (lens === "week") {
    foot = L.me.winBefore == null ? null : el("div", {},
      el("div", {}, "chance de vitória ", fmt.prob(L.me.winBefore, 0), " → ", el("b", {}, fmt.prob(L.me.winAfter, 0)), " ",
        deltaSpan(L.me.winAfter - L.me.winBefore, "pp")),
      el("div", {}, `desvio do time ${fmt.points(L.me.before.sd)} → ${fmt.points(L.me.after.sd)}`));
  } else if (lens === "season") {
    foot = el("div", {},
      el("div", {}, "em ", el("b", {}, `${L.weeksLeft} semanas`), ": ", deltaSpan(L.me.total, "pts")),
      el("div", { title: "Faixa P10–P90 pela volatilidade semanal dos dois jogadores" },
        `faixa ${fmt.deltaPts(L.me.total - L.me.band)} a ${fmt.deltaPts(L.me.total + L.me.band)}`));
  } else {
    const se = (v, n) => `${fmt.points(v.value)} ± ${fmt.points(v.sd)} (${n} j)`;
    foot = el("div", {},
      el("div", { title: "Pontos por jogo ± erro padrão (desvio / √jogos)" }, `cede ${se(L.give, L.give.games)}`),
      el("div", {}, `recebe ${se(L.receive, L.receive.games)}`));
  }
  return el("div", { class: "sim-lens" },
    el("div", { class: "sim-lens__title" }, info.title),
    el("div", { class: "stat__sub" }, info.sub),
    el("div", { class: "sim-lens__delta" }, deltaSpan(L.me.delta, "raw"), el("span", { class: "sim-lens__unit" }, info.unit)),
    el("div", { class: "stat__sub" }, "parceiro ", deltaSpan(L.them.delta, "raw"), ` ${info.unit}`),
    pairBars(L, r),
    el("div", { class: "sim-lens__foot" }, foot));
}

function verdictText(me, them) {
  if (me > EPS && them >= -EPS) return "Boa para os dois: tem chance real de ser aceita.";
  if (me > EPS) return "Boa para você, ruim para ele: difícil de aceitarem.";
  if (me < -EPS && them > EPS) return "Ruim para você: só ajuda o parceiro.";
  if (me < -EPS) return "Ruim para os dois.";
  return "Troca neutra: muda pouco para você.";
}

// weighted score for both sides + weight sliders. The sliders are built once;
// dragging only repaints the gauges / text (recreating an input mid-drag drops it).
function verdict(r) {
  const w = sim.weights;
  const result = el("div");
  const pct = {};
  const gauge = (label, v, max, color) => el("div", { class: "sim-gauge" },
    el("span", { class: "sim-gauge__who", style: `color:${color}` }, label),
    el("div", { class: "sim-gauge__track" },
      el("div", { class: "sim-gauge__fill" + (v >= 0 ? " pos" : " neg"),
        style: v >= 0 ? `left:50%;width:${(v / max) * 50}%` : `right:50%;width:${(-v / max) * 50}%` })),
    el("span", { class: "sim-gauge__v" }, deltaSpan(v, "raw"), " pts/sem"));
  const paint = () => {
    const me = weightedScore(r, w, "me"), them = weightedScore(r, w, "them");
    const max = Math.max(Math.abs(me), Math.abs(them), 1);
    result.replaceChildren(gauge("Você", me, max, SIM_ME), gauge("Parceiro", them, max, SIM_THEM),
      el("div", { class: "sim-verdict__text" }, verdictText(me, them)));
    const tot = w.week + w.season + w.perf || 1;
    for (const l of Object.keys(pct)) pct[l].textContent = `${Math.round((w[l] / tot) * 100)}%`;
  };
  const slider = (lens) => {
    pct[lens] = el("span", { class: "sim-slider__v" });
    return el("label", { class: "sim-slider" },
      el("span", {}, LENS_INFO[lens].title),
      el("input", { type: "range", min: "0", max: "100", step: "5", value: String(w[lens]),
        "aria-label": `Peso ${LENS_INFO[lens].title}`, oninput: (e) => { w[lens] = Number(e.target.value); paint(); } }),
      pct[lens]);
  };
  const node = el("div", { class: "sim-verdict" },
    el("div", {}, el("div", { class: "section-label", style: "margin-top:0" }, "Nota ponderada"), result),
    el("div", { class: "sim-sliders" },
      el("div", { class: "stat__sub" }, "Peso de cada dimensão (mesma unidade: pts/sem)"),
      slider("week"), slider("season"), slider("perf")));
  paint();
  return node;
}

function howNote() {
  return el("details", { class: "sim-how" }, el("summary", {}, "Como calculamos"),
    el("ul", {},
      el("li", {}, "O valor da troca é o que ela muda no lineup titular ótimo de cada time (regras de slot da liga, flex RB/WR). Assim um WR por um RB é comparável: o banco e o flex absorvem a diferença."),
      el("li", {}, "As três dimensões usam a mesma unidade, pontos por semana do lineup: Semana = média simulada desta semana; Temporada = projeção ESPN do resto da temporada ÷ jogos restantes do time; Desempenho = pontos reais ÷ jogos do time até agora."),
      el("li", {}, "Chance de vitória: aproximação normal com o desvio do time (√Σ desvios²) contra o adversário da semana; fica a < 1 p.p. da simulação Monte Carlo do motor."),
      el("li", {}, "“vs waiver” (VORP) = valor acima do melhor free agent da mesma posição: mede escassez, como no Value-Based Drafting."),
      el("li", {}, "Desempenho conta jogos do time: jogo perdido por lesão entra como 0. Poucos jogos = erro padrão alto.")));
}

function simCard(r, f, onStrengthLens) {
  const warns = [];
  if (r.locked) warns.push("Jogo de um dos jogadores já começou: na Semana, a troca só valeria a partir da próxima.");
  if (r.lenses.week.partnerIsOpponent) warns.push("O parceiro é o seu adversário desta semana: a chance de vitória considera os dois lineups depois da troca.");
  if (r.give.sim_mean == null || r.receive.sim_mean == null) warns.push("Um dos jogadores não tem projeção nesta captura: conta como 0 na Semana.");
  const lensChips = el("div", { class: "toolbar", style: "margin:0 0 4px" },
    ...["week", "season", "perf"].map((l) => el("button", { class: "chip" + (sim.strengthLens === l ? " active" : ""),
      onclick: (e) => {
        sim.strengthLens = l;
        e.target.parentNode.querySelectorAll(".chip").forEach((c) => c.classList.toggle("active", c === e.target));
        onStrengthLens();
      } }, LENS_INFO[l].title)));
  return el("div", { class: "cockpit-card sim-card" },
    el("div", { class: "sim-card__players" },
      simSide(r.give, f.get(String(r.give.ffa_id)), "Você cede", SIM_THEM),
      el("span", { class: "move-card__arrow" }, "⇄"),
      simSide(r.receive, f.get(String(r.receive.ffa_id)), "Você recebe", SIM_ME)),
    ...warns.map((w) => el("div", { class: "cockpit-banner stale", style: "margin:8px 0 0" }, "⚠ " + w)),
    el("div", { class: "sim-lenses" }, ...["week", "season", "perf"].map((l) => lensPanel(l, r))),
    verdict(r),
    el("div", { class: "grid-2", style: "margin-top:12px" },
      el("div", {}, el("div", { class: "section-label" }, "Força por posição na liga"), lensChips,
        el("div", { id: "sim-strength" }),
        el("div", { class: "note-inline" }, "Soma dos titulares ótimos por posição. Vazio = antes, cheio = depois; cinza = outros times. Número = rank na liga quando muda.")),
      el("div", {}, el("div", { class: "section-label" }, "Seu placar da semana"),
        el("div", { id: "sim-dist" }),
        el("div", { class: "note-inline" }, `Curva do total do seu time antes × depois. Linha vertical: ${team(r.lenses.week.opponent?.team_id).team_name || "adversário"} (esperado).`))),
    howNote());
}

async function simulator(teamId) {
  const [rosters, freeAgents, slots, matchups, run] = await Promise.all([
    data.getLeagueRosters(), data.getFreeAgents(), data.getRosterSlots(), data.getMatchups(), data.getRun()]);
  const box = el("div", { class: "sim" });
  if (sim.team !== String(teamId)) { Object.assign(sim, { give: null, receive: null, partner: null, team: String(teamId) }); }
  const mine = rosters.filter((p) => String(p.team_id) === String(teamId));
  const partners = [...new Set(rosters.map((p) => String(p.team_id)))].filter((t) => t !== String(teamId))
    .sort((a, b) => team(a).team_name.localeCompare(team(b).team_name));
  if (!sim.partner || !partners.includes(sim.partner)) sim.partner = partners[0] ?? null;
  const weeksLeft = Math.max(0, (run?.final_scoring_period ?? 17) - (run?.week ?? state.get().week) + 1);

  const draw = async () => {
    const theirs = rosters.filter((p) => String(p.team_id) === sim.partner);
    const pickers = el("div", { class: "sim-pickers" },
      el("div", {}, el("div", { class: "stat__sub" }, "Você cede"),
        playerSelect(mine, sim.give, "Jogador do seu time", (v) => { sim.give = v; draw(); })),
      el("span", { class: "move-card__arrow" }, "⇄"),
      el("div", {}, el("div", { class: "stat__sub" }, "Time"),
        el("select", { class: "field", "aria-label": "Time parceiro", onchange: (e) => { sim.partner = e.target.value; sim.receive = null; draw(); } },
          ...partners.map((t) => el("option", { value: t, selected: t === sim.partner ? "" : null }, team(t).team_name)))),
      el("div", {}, el("div", { class: "stat__sub" }, "Você recebe"),
        playerSelect(theirs, sim.receive, "Jogador do outro time", (v) => { sim.receive = v; draw(); })));
    if (!sim.give || !sim.receive) {
      box.replaceChildren(pickers, el("div", { class: "cockpit-banner empty", style: "margin-top:12px" },
        "Escolha um jogador seu e um do outro time para simular a troca."));
      return;
    }
    const r = evaluateTrade({ rosters, freeAgents, slots, matchups, myTeamId: teamId, giveId: sim.give,
      partnerId: sim.partner, receiveId: sim.receive, weeksLeft });
    if (!r) { box.replaceChildren(pickers, banner("empty", "Não foi possível montar essa troca.")); return; }
    const fcRows = await data.getForecastsByIds([r.give.ffa_id, r.receive.ffa_id]).catch(() => []);
    const f = new Map(fcRows.map((x) => [String(x.ffa_id), x]));
    const names = { me: team(teamId).team_name, them: team(sim.partner).team_name };
    const drawStrength = () => strengthStrip(box.querySelector("#sim-strength"), r.lenses[sim.strengthLens].strength, names);
    box.replaceChildren(pickers, simCard(r, f, drawStrength));
    drawStrength();
    const wk = r.lenses.week;
    normalOverlay(box.querySelector("#sim-dist"), { before: wk.me.before, after: wk.me.after, opp: wk.opponent?.after });
  };
  // first draw after the caller mounts box: Plotly sizes charts from the live layout
  return { box, draw };
}

function detail(t) {
  drawer(`${t.receive_player_name} ↔ ${t.give_player_name}`,
    el("div", { class: "stat__sub", style: "margin-bottom:8px" }, teamBadge(team(t.other_team_id), { size: 22 })),
    t.partner_is_my_opponent
      ? el("div", { class: "cockpit-banner stale" }, "⚠ Este time é seu adversário desta semana: o ganho de chance de vitória pode estar otimista.")
      : null,
    sectionLabel("Você"),
    el("div", {}, "cede ", posBadge(t.give_position), " ", t.give_player_name),
    el("div", {}, "recebe ", posBadge(t.receive_position), " ", t.receive_player_name),
    el("div", { style: "margin-top:6px" }, "pontos ", deltaSpan(t.my_delta_expected, "pts"),
      " · chance ", deltaSpan(t.my_delta_win_probability, "pp")),
    sectionLabel("Parceiro"),
    el("div", {}, "pontos ", deltaSpan(t.their_delta_expected, "pts")),
    sectionLabel("Equilíbrio"),
    fairnessMeter(t.my_delta_expected - t.their_delta_expected),
    el("div", { class: "stat__sub", style: "margin-top:4px" },
      `equilíbrio ${fmt.points(t.fairness, 2)} · nota ${fmt.points(t.trade_score, 1)}`));
}

function tradeCard(t, fc, max, top) {
  const recv = { player_id: t.receive_player_id, player_name: t.receive_player_name, position: t.receive_position };
  const give = { player_id: t.give_player_id, player_name: t.give_player_name, position: t.give_position };
  return el("div", { class: "move-card clickable" + (top ? " move-card--top" : ""), role: "button", tabindex: "0",
    onclick: () => detail(t), onkeydown: (e) => { if (e.key === "Enter") detail(t); } },
    el("div", { class: "move-card__head" },
      teamBadge(team(t.other_team_id), { size: 24 }),
      el("span", {}, t.partner_is_my_opponent ? badge("adversário da semana", "q") : null,
        " nota ", el("b", { style: "color:var(--ink)" }, fmt.points(t.trade_score, 1)))),
    el("div", { class: "move-card__players" },
      moveSide(recv, "Você recebe", "in", fc.get(String(t.receive_ffa_id))),
      el("span", { class: "move-card__arrow" }, "⇄"),
      moveSide(give, "Você cede", "out", fc.get(String(t.give_ffa_id)))),
    el("div", {},
      gainBar("Seu ganho", t.my_delta_expected, max),
      gainBar("Ganho dele", t.their_delta_expected, max)));
}

export async function render(root) {
  const { teamId } = state.get();
  const all = await data.getTradeRecommendations();
  const rows = all.filter((t) => String(t.my_team_id) === String(teamId));

  const { box: simBox, draw: drawSim } = await simulator(teamId);
  if (!rows.length) {
    mount(root, sectionLabel("Simulador de troca"), simBox,
      banner("empty", "Nenhuma troca 1×1 que ajude seu time nesta semana."));
    await drawSim();
    return;
  }

  const fcRows = await data.getForecastsByIds(rows.flatMap((t) => [t.receive_ffa_id, t.give_ffa_id]));
  const fc = new Map(fcRows.map((f) => [String(f.ffa_id), f]));
  const max = Math.max(...rows.flatMap((t) => [t.my_delta_expected || 0, t.their_delta_expected || 0]), 0.1);
  const cards = rows.slice(0, 12);

  mount(root,
    sectionLabel("Simulador de troca"),
    simBox,

    sectionLabel("Melhores propostas"),
    el("div", { class: "cockpit-banner stale" },
      "As propostas abaixo são calculadas só para a semana atual (escalação ótima desta rodada). Para ver a troca na temporada e no desempenho, use o simulador acima."),
    el("div", { class: "move-grid" }, ...cards.map((t, i) => tradeCard(t, fc, max, i === 0))),

    sectionLabel("Mapa de trocas: seu ganho x ganho do parceiro"),
    card(el("div", { id: "tr-scatter" }),
      el("div", { class: "note-inline" }, "Acima da linha zero a troca também ajuda o parceiro, e fica mais fácil de ser aceita. Bolha maior: nota maior. Laranja: parceiro é seu adversário desta semana.")),

    sectionLabel(`Todas as propostas (${rows.length})`),
    rankTable(rows, [
      { key: "recommendation_rank", label: "#", num: true },
      { key: "other_team_name", label: "Parceiro", fmt: (v, r) => teamBadge(team(r.other_team_id), { size: 20 }) },
      { key: "receive_player_name", label: "Recebe", fmt: (v, r) => el("span", {}, posBadge(r.receive_position), " ", v) },
      { key: "give_player_name", label: "Cede", fmt: (v, r) => el("span", {}, posBadge(r.give_position), " ", v) },
      { key: "my_delta_expected", label: "Seu Δ", num: true, fmt: (v) => deltaSpan(v, "pts") },
      { key: "their_delta_expected", label: "Δ dele", num: true, fmt: (v) => deltaSpan(v, "pts") },
      { key: "trade_score", label: "Nota", num: true, fmt: (v) => fmt.points(v, 1) },
    ], { onRow: detail }),
  );

  tradeScatter(document.getElementById("tr-scatter"), rows);
  await drawSim();
}
