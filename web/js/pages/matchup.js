// Confronto — scoreboard + slot-by-slot duel + how the odds moved this week.
import * as data from "../data.js";
import * as state from "../state.js";
import * as fmt from "../format.js";
import { el, banner, mount, team } from "../app.js";
import { card, sectionLabel, avatar, teamLogo, winBar, rangeBar, lockBadge, statusBadge } from "../components.js";
import { winProbLine } from "../charts.js";

let selectedId = null;

// starters of one team grouped by slot, best first inside a slot
function slotted(roster) {
  const bySlot = new Map();
  for (const p of roster.filter((r) => r.is_starter)) {
    const k = p.lineup_slot_id;
    if (!bySlot.has(k)) bySlot.set(k, []);
    bySlot.get(k).push(p);
  }
  for (const v of bySlot.values()) v.sort((a, b) => b.sim_mean - a.sim_mean);
  return bySlot;
}

function duelSide(p, cls, win) {
  if (!p) return el("div", { class: `duel__side ${cls}` }, el("span", { class: "stat__sub" }, "vazio"));
  const shown = p.is_realized ? "real" : "proj";
  return el("div", { class: `duel__side ${cls}` },
    avatar(p, { size: 40 }),
    el("div", { class: "duel__info" },
      el("div", { class: "duel__name", title: p.player_name }, p.player_name),
      el("div", { class: "duel__meta" },
        el("span", {}, `${fmt.nflAbbr(p.nfl_team)} · ${shown}`),
        p.is_locked ? lockBadge() : statusBadge(p.injury_status),
        p.is_realized ? null : el("span", { style: "flex:1;max-width:120px" }, rangeBar(p.p10, p.p50, p.p90)))),
    el("div", { class: "duel__pts " + (win == null ? "" : win ? "duel__pts--win" : "duel__pts--lose") }, fmt.points(p.sim_mean)));
}

function duel(home, away, m) {
  const h = slotted(home), a = slotted(away);
  const slotIds = [...new Set([...h.keys(), ...a.keys()])].sort((x, y) => x - y);
  const rows = [];
  for (const sid of slotIds) {
    const hs = h.get(sid) || [], as = a.get(sid) || [];
    for (let i = 0; i < Math.max(hs.length, as.length); i++) {
      const hp = hs[i], ap = as[i];
      const edge = (hp?.sim_mean ?? 0) - (ap?.sim_mean ?? 0);
      const win = hp && ap ? edge > 0 : null;
      rows.push(el("div", { class: "duel__row" },
        duelSide(hp, "duel__side--home", win),
        el("div", { class: "duel__slot" },
          el("span", { class: "pos-badge " + fmt.pos((hp || ap).position).toLowerCase() }, (hp || ap).lineup_slot),
          el("span", { class: "duel__edge" }, (edge >= 0 ? "+" : "−") + fmt.points(Math.abs(edge)))),
        duelSide(ap, "duel__side--away", win == null ? null : !win)));
    }
  }
  return el("div", { class: "duel" },
    el("div", { class: "duel__row duel__row--head" },
      el("div", { class: "duel__side" }, teamLogo(team(m.home_team_id), { size: 28 }), el("b", {}, m.home_team_name)),
      el("div", { class: "duel__slot stat__sub" }, "slot"),
      el("div", { class: "duel__side duel__side--away" }, teamLogo(team(m.away_team_id), { size: 28 }), el("b", {}, m.away_team_name))),
    ...rows,
    el("div", { class: "duel__row duel__row--total" },
      el("div", { class: "duel__side" }, el("div", { class: "duel__info" }, "Total"),
        el("div", { class: "duel__pts duel__pts--win" }, fmt.points(m.home_expected))),
      el("div", { class: "duel__slot stat__sub" }, "Σ"),
      el("div", { class: "duel__side duel__side--away" }, el("div", { class: "duel__info" }, "Total"),
        el("div", { class: "duel__pts duel__pts--win" }, fmt.points(m.away_expected)))));
}

export async function render(root) {
  const { teamId } = state.get();
  const matchups = await data.getMatchups();
  if (!matchups.length) { mount(root, banner("empty", "Nenhum confronto para esta captura.")); return; }

  if (selectedId == null || !matchups.find((m) => String(m.matchup_id) === String(selectedId))) {
    const mine = matchups.find((m) => String(m.home_team_id) === String(teamId) || String(m.away_team_id) === String(teamId));
    selectedId = (mine || matchups[0]).matchup_id;
  }
  const m = matchups.find((x) => String(x.matchup_id) === String(selectedId));
  const [home, away, hist] = await Promise.all([
    data.getRoster(m.home_team_id), data.getRoster(m.away_team_id),
    data.getMatchupHistory(m.week, m.matchup_id).catch(() => []),
  ]);

  const switcher = el("select", { class: "field", style: "width:auto;max-width:100%", "aria-label": "Confronto",
    onchange: (e) => { selectedId = e.target.value; render(root); } },
    ...matchups.map((x) => el("option", { value: x.matchup_id, selected: String(x.matchup_id) === String(selectedId) ? "" : null },
      `${x.home_team_name} x ${x.away_team_name}`)));

  const side = (id, name, exp, p10, p90) => el("div", { class: "hero__side" },
    teamLogo(team(id), { size: 56 }),
    el("div", { class: "stat__value stat__value--xl" }, fmt.points(exp)),
    el("div", { class: "hero__team" }, name),
    el("div", { class: "hero__range" }, `${fmt.points(p10)} – ${fmt.points(p90)}`));

  mount(root,
    el("div", { class: "toolbar" }, el("span", { class: "stat__sub" }, "Confronto"), switcher),
    card(
      el("div", { class: "hero" },
        side(m.home_team_id, m.home_team_name, m.home_expected, m.home_p10, m.home_p90),
        el("div", { class: "hero__vs" }, "x"),
        side(m.away_team_id, m.away_team_name, m.away_expected, m.away_p10, m.away_p90)),
      el("div", { style: "margin:14px 0 4px" },
        winBar(m.home_win_probability, m.away_win_probability, { labelA: m.home_team_name, labelB: m.away_team_name })),
      m.tie_probability > 0.001 ? el("div", { class: "note-inline", style: "text-align:center" }, `empate ${fmt.prob(m.tie_probability, 1)}`) : null),

    sectionLabel("Duelo posição a posição"),
    card(duel(home, away, m),
      el("div", { class: "note-inline" }, "Número grande: pontos esperados (ou reais, depois que o jogo trava). Barra: faixa P10–P90 com a mediana. Embaixo do slot: vantagem do time da esquerda.")),

    hist.length > 1 ? sectionLabel("Como a chance de vitória mudou nesta semana") : null,
    hist.length > 1 ? card(el("div", { id: "mu-hist" }),
      el("div", { class: "note-inline" }, `Chance de vitória de ${m.home_team_name} em cada captura da semana ${m.week}. Depois que os jogos travam, os pontos reais substituem a projeção.`)) : null,
  );

  if (hist.length > 1) {
    winProbLine(document.getElementById("mu-hist"),
      hist.map((r) => ({ tag: r.tag, p: String(r.home_team_id) === String(m.home_team_id) ? r.home_win_probability : r.away_win_probability })),
      { label: m.home_team_name });
  }
}
