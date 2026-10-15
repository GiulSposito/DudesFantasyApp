// "Mapa de comparação" block (docs/comparison_map.md), shared by Lineup and
// Waivers: lens chips [Semana] [Próx. 4] [Realizado] + slot chips + the chart.
// Logic lives in compare.js; this module loads the data and draws.
import * as data from "./data.js";
import { el } from "./app.js";
import { chips, openPlayer } from "./components.js";
import { compareMap } from "./charts.js";
import { withHorizon } from "./trade-sim.js";
import { MAP_LENSES, startingSlots, slotGroup, lineToBeat, mapPoint, mapSet, defaultSlot } from "./compare.js";

const _state = new Map();   // key -> { lens, slot }: survives the page's re-renders

// host: an element already in the page. roster: the team's rosters rows (loaded
// when omitted). nFa: free agents added per slot. allowAll: a "Todos" slot chip
// (whole roster, no line to beat). selectedId: player_id ringed and named.
export async function comparisonMap(host, { key, teamId, roster = null, nFa = 0, allowAll = false,
  defaultLens = "week", selectedId = null }) {
  const [ros0, fa0, hz, slots, run] = await Promise.all([
    roster ?? data.getRoster(teamId), nFa ? data.getFreeAgents() : [],
    data.getHorizon(), data.getRosterSlots(), data.getRun()]);
  const ros = withHorizon(ros0, hz), fa = withHorizon(fa0, hz);
  const weekRows = await data.getPlayerWeeks([...ros, ...fa].map((p) => p.ffa_id));
  const weeksByFfa = new Map();
  for (const r of weekRows) {
    const k = String(r.ffa_id);
    if (!weeksByFfa.has(k)) weeksByFfa.set(k, []);
    weeksByFfa.get(k).push(r);
  }

  const lenses = ["week", ...(hz.size ? ["next"] : []), ...(weekRows.length ? ["real"] : [])];
  const starting = startingSlots(slots);
  const slotLabels = { ALL: "Todos", ...Object.fromEntries(starting.map((s) => [s.id, s.label])) };
  const week = run?.week;
  const lastWeek = hz.size ? Math.max(...[...hz.values()].flat().map((x) => x.target_week)) : null;
  if (!_state.has(key)) _state.set(key, { lens: defaultLens, slot: allowAll ? "ALL" : defaultSlot(starting, ros) });
  const st = _state.get(key);
  if (!lenses.includes(st.lens)) st.lens = "week";

  const paint = () => {
    const pts = mapSet({ roster: ros, freeAgents: fa, slotId: st.slot, lens: st.lens, nFa, weeksByFfa });
    const lp = st.slot === "ALL" ? null : lineToBeat(ros, slotGroup(st.slot, [...ros, ...fa], starting), starting);
    const lpt = lp && st.lens !== "real" ? mapPoint(lp, st.lens, weeksByFfa) : null;
    const line = lpt && { ...lpt, label: `a superar · ${lp.player_name} (${lp.optimal_slot})` };
    const titles = {
      week: { x: `pontos na S${week} (média e faixa P10–P90)` },
      next: { x: `S${week} · esta semana (consenso)`, y: `média S${week + 1}–S${lastWeek} (ESPN, bye = 0)` },
      real: { x: "projeção média por jogo", y: "pontos reais por jogo" },
    }[st.lens];
    const note = {
      week: line ? "À direita da linha tracejada: ganho esperado sobre o titular a superar." : "",
      next: line ? "Cruz tracejada: o titular a superar. Diagonal: jogador estável." : "Diagonal: jogador estável.",
      real: "Semanas fechadas, projeção feita antes de cada jogo. Acima da diagonal: entregando mais que o projetado. Tamanho = nº de jogos.",
    }[st.lens];
    const plot = el("div");
    host.replaceChildren(
      el("div", { class: "toolbar" }, ...chips(lenses, st.lens, (v) => { st.lens = v; paint(); }, MAP_LENSES)),
      el("div", { class: "toolbar" }, ...chips([...(allowAll ? ["ALL"] : []), ...starting.map((s) => s.id)], st.slot,
        (v) => { st.slot = v; paint(); }, slotLabels)),
      pts.length ? plot : el("div", { class: "cockpit-banner empty" }, "Nenhum jogador com dados para este slot nesta lente."),
      el("div", { class: "note-inline" }, `${note} Cheio = titular do lineup ótimo, contorno = banco, cinza = free agent. Clique num ponto para abrir o jogador.`));
    if (pts.length) compareMap(plot, pts, { lens: st.lens, line, selectedId, onPick: openPlayer, titles });
  };
  paint();
}
