// Waivers — add/drop moves ranked by team gain, not player rank.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { sectionLabel, posBadge, coverageDot, deltaSpan, rankTable, drawer, kv, avatar, rangeBar, moveSide, gainBar, oppLabel,
  openPlayer, chips, horizonStrip } from "../components.js";

let faPos = "ALL";

// three ranking scopes (docs/horizon_projections.md): streaming = this week,
// holding = the next weeks
const SCOPES = {
  week: { label: "Semana atual", rank: "recommendation_rank", d: "delta_expected" },
  future: { label: "Futuro", rank: "rank_future", d: "delta_future" },
  horizon: { label: "Ambos", rank: "rank_horizon", d: "delta_horizon" },
};
let scope = "week";

const weeksLabel = (key, ctx) => key === "week" || ctx.lastWeek == null ? `S${ctx.week}`
  : key === "future" ? `S${ctx.week + 1}–S${ctx.lastWeek}` : `S${ctx.week}–S${ctx.lastWeek}`;

// a player's points in a scope: this week's forecast, the future ESPN weeks, or both
function scopeTotal(key, w0, rows) {
  const fut = (rows ?? []).reduce((s, r) => s + (r.projection ?? 0), 0);
  return key === "week" ? w0 ?? 0 : key === "future" ? fut : (w0 ?? 0) + fut;
}

async function detail(rec, ctx) {
  const [addF, dropF] = await Promise.all([
    rec.add_ffa_id ? data.getForecast(rec.add_ffa_id) : null,
    rec.drop_ffa_id ? data.getForecast(rec.drop_ffa_id) : null,
  ]);
  const cmp = (label, d, a, isProb) => kv(label,
    `${isProb ? fmt.prob(d) : fmt.points(d)}  →  ${isProb ? fmt.prob(a) : fmt.points(a)}`);
  drawer(`${rec.add_player_name} no lugar de ${rec.drop_player_name}`,
    sectionLabel("Impacto no time"),
    kv("Pontos esperados", `${fmt.points(rec.before_expected)} → ${fmt.points(rec.after_expected)}`),
    kv("Chance de vitória", `${fmt.prob(rec.before_win_probability)} → ${fmt.prob(rec.after_win_probability)}`),
    el("div", { class: "stat__sub", style: "margin-top:6px" },
      deltaSpan(rec.delta_expected, "pts"), " · ", deltaSpan(rec.delta_win_probability, "pp"), " de chance"),
    rec.delta_future == null ? null : el("div", { class: "stat__sub" },
      `${weeksLabel("future", ctx)} `, deltaSpan(rec.delta_future, "pts"),
      ` · ${weeksLabel("horizon", ctx)} `, deltaSpan(rec.delta_horizon, "pts"), " (ESPN semanal)"),
    sectionLabel("Dispensar → Pegar"),
    cmp("Projeção", dropF?.projection, addF?.projection),
    cmp("Média simulada", dropF?.sim_mean, addF?.sim_mean),
    cmp("P10", dropF?.p10, addF?.p10),
    cmp("P50", dropF?.p50, addF?.p50),
    cmp("P90", dropF?.p90, addF?.p90),
    cmp("P(>15)", dropF?.prob_gt_15, addF?.prob_gt_15, true));
}

function hzRows(r, fc, ctx) {
  if (!ctx.hasHz) return null;
  const row = (label, pid, ffa) => {
    const f = fc.get(String(ffa));
    return el("div", { class: "hz-row" }, el("span", { class: "hz-row__who" }, label),
      horizonStrip(f?.sim_mean, ctx.hz.get(String(pid)), ctx.week, { w0Bye: f?.opp_team === "BYE" }));
  };
  return el("div", { class: "hz-rows" },
    row("Pegar", r.add_player_id, r.add_ffa_id), row("Dispensar", r.drop_player_id, r.drop_ffa_id));
}

function recCard(r, fc, maxPts, maxPp, ctx) {
  const S = SCOPES[ctx.scope];
  const add = { player_id: r.add_player_id, player_name: r.add_player_name, position: r.add_position };
  const drop = { player_id: r.drop_player_id, player_name: r.drop_player_name, position: r.drop_position };
  return el("div", { class: "move-card clickable" + (r[S.rank] === 1 ? " move-card--top" : ""),
    role: "button", tabindex: "0", onclick: () => detail(r, ctx), onkeydown: (e) => { if (e.key === "Enter") detail(r, ctx); } },
    el("div", { class: "move-card__head" }, el("span", {}, `#${r[S.rank]}`),
      el("span", { class: "gain-big delta--pos" }, fmt.deltaPts(r[S.d]))),
    el("div", { class: "move-card__players" },
      moveSide(add, "Pegar", "in", fc.get(String(r.add_ffa_id))),
      el("span", { class: "move-card__arrow" }, "⇄"),
      moveSide(drop, "Dispensar", "out", fc.get(String(r.drop_ffa_id)))),
    hzRows(r, fc, ctx),
    el("div", {},
      gainBar(ctx.scope === "week" ? "Pontos esperados" : `Pontos ${weeksLabel(ctx.scope, ctx)}`, r[S.d], maxPts, "pts"),
      // win probability exists for this week only (future opponents unknown)
      ctx.scope === "week" ? gainBar("Chance de vitória", r.delta_win_probability, maxPp, "pp") : null));
}

export async function render(root) {
  const { teamId } = state.get();
  const [all, hz, run] = await Promise.all([data.getWaiverRecommendations(teamId), data.getHorizon(), data.getRun()]);
  const hasHz = hz.size > 0;
  const key = hasHz ? scope : "week";               // runs without a horizon: week scope only
  const S = SCOPES[key];
  const ctx = { hz, hasHz, scope: key, week: run?.week ?? state.get().week,
    lastWeek: hasHz ? Math.max(...[...hz.values()].flat().map((x) => x.target_week)) : null };
  const recs = all.filter((r) => r[S.rank] != null).sort((a, b) => a[S.rank] - b[S.rank]);

  const fcRows = await data.getForecastsByIds(recs.flatMap((r) => [r.add_ffa_id, r.drop_ffa_id]));
  const fc = new Map(fcRows.map((f) => [String(f.ffa_id), f]));
  const maxPts = Math.max(...recs.map((r) => r[S.d] || 0), 0.1);
  const maxPp = Math.max(...recs.map((r) => r.delta_win_probability || 0), 0.001);
  const when = { week: "nesta semana", future: `nas próximas semanas (${weeksLabel("future", ctx)})`,
    horizon: `de ${weeksLabel("horizon", ctx)}` }[key];
  const note = {
    week: "Ordenado pelo ganho de pontos esperados na escalação ótima desta semana (streaming); jogadores em bye ficam de fora.",
    future: `Ordenado pelo ganho nas semanas ${weeksLabel("future", ctx)} (segurar), pela projeção semanal da ESPN vista da S${ctx.week}; bye conta 0.`,
    horizon: `Ordenado pelo ganho de ${weeksLabel("horizon", ctx)}: esta semana pelo consenso + as seguintes pela projeção semanal da ESPN.`,
  }[key];

  mount(root,
    sectionLabel("Movimentos sugeridos"),
    hasHz ? el("div", { class: "toolbar" }, ...chips(Object.keys(SCOPES), key,
      (v) => { scope = v; render(root); }, Object.fromEntries(Object.entries(SCOPES).map(([k, x]) => [k, x.label])))) : null,
    recs.length ? el("div", { class: "move-grid" }, ...recs.map((r) => recCard(r, fc, maxPts, maxPp, ctx)))
      : banner("empty", team(teamId).is_my_team
        ? `Nenhum movimento de waiver que melhore o time ${when}.`
        : "Recomendações de waiver só são calculadas para o seu time."),
    recs.length ? el("div", { class: "note-inline" }, `${note} Clique num card para comparar os dois jogadores.`) : null,

    sectionLabel("Free agents disponíveis"),
    el("div", { class: "toolbar" },
      ...["ALL", "QB", "RB", "WR", "TE", "K", "DST"].map((p) =>
        el("button", { class: "chip" + (p === faPos ? " active" : ""),
          onclick: () => { faPos = p; render(root); } }, p === "ALL" ? "Todos" : p))),
    el("div", { id: "wv-fa" }),
  );

  // outside the week scope, sort by the scope's points so free agents on bye
  // this week (forecast 0) surface
  let fa = await data.getFreeAgents({ position: faPos });
  if (key !== "week") {
    const tot = (r) => scopeTotal(key, r.sim_mean, hz.get(String(r.player_id)));
    fa = fa.map((r) => ({ ...r, _tot: tot(r) })).sort((a, b) => b._tot - a._tot);
  }
  fa = fa.slice(0, 40);
  document.getElementById("wv-fa").replaceChildren(rankTable(fa, [
    { key: "player_name", label: "Jogador", fmt: (v, r) => el("span", { class: "player-cell" }, avatar(r, { size: 30 }), posBadge(r.position), " ", v) },
    { key: "nfl_team", label: "Time", fmt: (v) => fmt.nflAbbr(v) },
    { key: "opp_team", label: "Adv", title: "Adversário da semana; nº = rank da defesa contra a posição (1 = mais difícil)",
      fmt: (v, r) => oppLabel(r) ?? "–" },
    { key: "p10", label: "Faixa P10–P90", fmt: (v, r) => rangeBar(r.p10, r.p50, r.p90) },
    { key: "sim_mean", label: "Proj", num: true, fmt: (v) => el("b", {}, fmt.points(v)) },
    ...(hasHz ? [{ key: "player_id", label: "Próx. semanas (ESPN)",
      title: "Esta semana (consenso) + projeção semanal da ESPN das próximas semanas",
      fmt: (v, r) => horizonStrip(r.sim_mean, hz.get(String(v)), ctx.week, { w0Bye: r.opp_team === "BYE" }) ?? "–" }] : []),
    { key: "coverage_class", label: "Conf", num: true, fmt: (v) => coverageDot(v) },
  ], { empty: "Nenhum free agent nesta posição.", onRow: openPlayer }));
}
