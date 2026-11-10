# Ad-hoc analysis: does the team's QB explain what the projection of his WR, RB, TE
# and K misses? Report: docs/analysis_against_rank_qb.md.
#
# Two questions with different uses: what is known before the game can move a
# projection; what only shows after it (the QB's own surprise) can only shape the
# joint distribution of the simulation, which today draws every player independently.
#
# Run from the project root: source("R/snippets/analysis_qb_influence.R")
# Leaves the tables in `qb` and saves them to data/temp/analysis_qb_influence.rds.

source("./R/snippets/analysis_matchup_panel.R")

set.seed(20261107)
.skill <- c("WR", "RB", "TE", "K")
.roles <- c("WR1", "WR2", "WR3+", "RB1", "RB2+", "TE1", "TE2+", "K1")
.tests <- c(2022:2025, 2026L)

z_of <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)

qb_scale <- panel |>
  filter(!is.na(qb_proj)) |>
  distinct(season, week, team, qb_proj, qb_ppg_std) |>
  mutate(qb_proj_z = z_of(qb_proj), qb_ppg_z = z_of(qb_ppg_std), .by = c(season, week)) |>
  select(season, week, team, qb_proj_z, qb_ppg_z)

d <- panel |>
  filter(pos %in% .skill, !is.na(qb_proj)) |>
  left_join(qb_scale, by = c("season", "week", "team")) |>
  mutate(qb_rank_z = -as.numeric(scale(qb_rank_week)))      # + = better QB
hist <- d |> filter(season <= 2025L)
f_qb <- residual ~ qb_proj_z + bin + factor(season)

# 1. known before the game ---------------------------------------------------------
effect <- slope_by_pos(hist, f_qb, "qb_proj_z", .skill) |> mutate(p_holm = p.adjust(p, "holm"))
by_role <- map_dfr(.roles, \(x) boot_slope(filter(hist, role == x), f_qb, "qb_proj_z") |>
                     mutate(role = x, .before = 1))
others <- bind_rows(
  slope_by_pos(hist, residual ~ qb_rank_z + bin + factor(season), "qb_rank_z", .skill),
  slope_by_pos(hist, residual ~ qb_ppg_z + bin + factor(season), "qb_ppg_z", .skill),
  slope_by_pos(hist |> mutate(backup = as.numeric(qb_is_backup)),
               residual ~ backup + bin + factor(season), "backup", .skill)
)
# 2022's single source still lists QBs already ruled out: same test with the
# expected QB confirmed as the real starter
starter_only <- slope_by_pos(hist |> filter(qb_is_starter), f_qb, "qb_proj_z", .skill)
# one source's scale moves a team's QB and K together with no link to the points,
# so several-source rows are the fair view of how much the projection reacts
effect_ensemble <- slope_by_pos(hist |> filter(coverage_class == "ensemble"), f_qb,
                                "qb_proj_z", .skill)

# already priced in? within player-season, as in the Against Rank study
within <- hist |>
  filter(n() >= 4L, .by = c(season, ffa_id, pos)) |>
  mutate(backup = as.numeric(qb_is_backup)) |>
  mutate(proj_dev = projection - mean(projection),
         act_dev  = actual_points - mean(actual_points),
         z_dev    = qb_proj_z - mean(qb_proj_z),
         .by = c(season, ffa_id, pos))
backup_within <- hist |>
  filter(!is.na(qb_is_backup)) |>
  mutate(backup = as.numeric(qb_is_backup)) |>
  filter(n_distinct(backup) == 2L, .by = c(season, ffa_id, pos)) |>
  mutate(proj_dev = projection - mean(projection),
         act_dev  = actual_points - mean(actual_points),
         b_dev    = backup - mean(backup),
         .by = c(season, ffa_id, pos))
priced <- bind_rows(
  slope_by_pos(within, proj_dev ~ z_dev, "z_dev", .skill) |> mutate(what = "projeção", factor = "qb_proj_z"),
  slope_by_pos(within, act_dev ~ z_dev, "z_dev", .skill) |> mutate(what = "realizado", factor = "qb_proj_z"),
  slope_by_pos(backup_within, proj_dev ~ b_dev, "b_dev", .skill) |> mutate(what = "projeção", factor = "reserva"),
  slope_by_pos(backup_within, act_dev ~ b_dev, "b_dev", .skill) |> mutate(what = "realizado", factor = "reserva")
)

within_ens <- within |>
  filter(coverage_class == "ensemble") |>
  filter(n() >= 4L, .by = c(season, ffa_id, pos)) |>
  mutate(proj_dev = projection - mean(projection),
         act_dev  = actual_points - mean(actual_points),
         z_dev    = qb_proj_z - mean(qb_proj_z),
         .by = c(season, ffa_id, pos))
priced_ensemble <- bind_rows(
  slope_by_pos(within_ens, proj_dev ~ z_dev, "z_dev", .skill) |> mutate(what = "projeção"),
  slope_by_pos(within_ens, act_dev ~ z_dev, "z_dev", .skill) |> mutate(what = "realizado")
)

placebo <- perm_placebo(hist, "qb_proj_z", .skill)

# out of sample
oos <- oos_rows(d, "qb_proj_z")
verdict <- oos_verdict(oos)
by_season <- oos |>
  mutate(d_abs = abs(residual - shift) - abs(residual)) |>
  summarise(d_mae = mean(d_abs), n = n(), .by = c(pos, season))

verdict_ensemble <- oos_rows(filter(d, coverage_class == "ensemble"), "qb_proj_z") |>
  oos_verdict()

# a real backup starting: only the affected rows, the others have shift = 0
verdict_backup <- d |>
  mutate(backup = as.numeric(qb_is_backup)) |>
  oos_rows("backup") |>
  filter(backup == 1) |>
  oos_verdict()

# 2. known only after the game -----------------------------------------------------
# Spearman, and its normal-score equivalent for a Gaussian copula
rho_of <- function(rs) 2 * sin(pi * rs / 6)
played <- d |> filter(!is.na(qb_residual), qb_is_starter)

boot_cor <- function(g, B = 1000L) {
  blocks <- unname(split(seq_len(nrow(g)), g$team_game))
  est <- cor(g$residual, g$qb_residual, method = "spearman")
  bs <- replicate(B, {
    rows <- unlist(blocks[sample.int(length(blocks), replace = TRUE)], use.names = FALSE)
    cor(g$residual[rows], g$qb_residual[rows], method = "spearman")
  })
  tibble(n = nrow(g), spearman = est, lo = quantile(bs, .025, names = FALSE),
         hi = quantile(bs, .975, names = FALSE),
         pearson = cor(g$residual, g$qb_residual))
}
corr_role <- map_dfr(.roles, \(x) boot_cor(filter(played, season <= 2025L, role == x)) |>
                       mutate(role = x, .before = 1))
corr_2026 <- map_dfr(.roles, \(x) boot_cor(filter(played, season == 2026L, role == x)) |>
                       mutate(role = x, .before = 1))
corr_placebo <- played |>
  filter(season <= 2025L) |>
  mutate(qb_residual = sample(qb_residual), .by = c(season, week, role)) |>
  summarise(spearman = cor(residual, qb_residual, method = "spearman"), .by = role)

rho_train <- function(s) {
  played |>
    filter(season < s) |>
    summarise(rho = rho_of(cor(residual, qb_residual, method = "spearman")), .by = role)
}

# 3. stacks: QB + WR1 + TE1 of one team in one game --------------------------------
# Marginals stay the production pools; only the dependence between them changes.
.n_draws <- 4000L
pick_q <- function(v, u) sort(v)[pmax(ceiling(u * length(v)), 1L)]

stacks <- panel |>
  filter((pos == "QB" & ffa_id == qb_ffa_id) | role %in% c("WR1", "TE1")) |>
  mutate(slot = if_else(pos == "QB", "QB", role)) |>
  filter(n() == 3L, n_distinct(slot) == 3L, .by = team_game)

stack_scores <- map_dfr(.tests, function(s) {
  pc  <- pool_center(panel |> filter(season < s, !is.na(residual), !is.na(projection)))
  rho <- rho_train(s) |> deframe()
  map_dfr(split(filter(stacks, season == s), ~team_game, drop = TRUE), function(g) {
    v <- pmap(list(g$pos, g$projection, g$coverage_class),
              \(p, x, cc) dist_of(p, x, cc, pc)) |> set_names(g$slot)
    z0 <- rnorm(.n_draws)
    e  <- matrix(rnorm(.n_draws * 3L), ncol = 3L, dimnames = list(NULL, c("QB", "WR1", "TE1")))
    joint <- pick_q(v$QB, pnorm(z0)) +
      pick_q(v$WR1, pnorm(rho[["WR1"]] * z0 + sqrt(1 - rho[["WR1"]]^2) * e[, "WR1"])) +
      pick_q(v$TE1, pnorm(rho[["TE1"]] * z0 + sqrt(1 - rho[["TE1"]]^2) * e[, "TE1"]))
    indep <- pick_q(v$QB, pnorm(e[, "QB"])) + pick_q(v$WR1, pnorm(e[, "WR1"])) +
      pick_q(v$TE1, pnorm(e[, "TE1"]))
    y <- sum(g$actual_points)
    bind_rows(
      score_dist(indep, y) |> mutate(model = "independente", sim_var = var(indep), err = y - mean(indep)),
      score_dist(joint, y) |> mutate(model = "correlacionado", sim_var = var(joint), err = y - mean(joint))
    ) |>
      mutate(season = s, team_game = g$team_game[1])
  })
})
stack_summary <- stack_scores |>
  mutate(era = if_else(season <= 2025L, "2022-2025", "2026")) |>
  summarise(n = n(), cov80 = mean(in80), cov50 = mean(in50), pinball = mean(pinball),
            crps = mean(crps), var_ratio = var(err) / mean(sim_var), .by = c(era, model)) |>
  arrange(era, model)
stack_by_season <- stack_scores |>
  summarise(cov80 = mean(in80), pinball = mean(pinball), crps = mean(crps),
            var_ratio = var(err) / mean(sim_var), .by = c(season, model)) |>
  arrange(season, model)
stack_delta <- stack_scores |>
  select(season, team_game, model, pinball, crps) |>
  pivot_wider(names_from = model, values_from = c(pinball, crps)) |>
  mutate(era = if_else(season <= 2025L, "2022-2025", "2026"),
         d_pinball = pinball_correlacionado - pinball_independente,
         d_crps = crps_correlacionado - crps_independente) |>
  group_by(era) |>
  group_modify(function(g, ...) {
    bind_rows(boot_ratio(g$d_pinball, rep(1, nrow(g)), g$team_game) |> mutate(metric = "pinball"),
              boot_ratio(g$d_crps, rep(1, nrow(g)), g$team_game) |> mutate(metric = "crps"))
  }) |>
  ungroup()

# 4. the real league, 2026 W1-W8 ---------------------------------------------------
# 56 matchups: sensitivity, not proof. Re-simulated from each week's pre-kickoff
# projection with the current pool, as the persisted draws predate its centring.
espn <- readRDS("./data/espn_db.rds")
dec  <- readRDS("./data/decision_db.rds")
bt   <- nanoparquet::read_parquet("./web/data/history/matchup_backtest.parquet") |> as_tibble()

finals <- espn$espn_rosters |>
  filter(season == 2026L, tag == "final", is_starter) |>
  slice_max(timestamp, n = 1, with_ties = TRUE, by = week) |>
  transmute(week = as.integer(week), team_id, espn_id = as.integer(player_id), nfl_team = pro_team)
bridge <- bind_rows(
  dec$current_players |> transmute(espn_id = as.integer(espn_id), ffa_id = as.integer(ffa_id)),
  dec$free_agents |> transmute(espn_id = as.integer(player_id), ffa_id = as.integer(ffa_id))
) |>
  filter(!is.na(espn_id), !is.na(ffa_id)) |>
  distinct(espn_id, .keep_all = TRUE)
fc <- dec$player_forecasts |>
  inner_join(distinct(bt, week, run_id), by = c("run_id", "week")) |>
  transmute(week = as.integer(week), ffa_id = as.integer(ffa_id), pos, projection, coverage_class)
lineups <- finals |>
  left_join(bridge, by = "espn_id") |>
  left_join(fc, by = c("week", "ffa_id")) |>
  left_join(panel |> filter(season == 2026L) |> select(week, ffa_id, role), by = c("week", "ffa_id"))

pc_2026 <- pool_center(panel |> filter(season <= 2025L, !is.na(residual), !is.na(projection)))
rho_2026 <- rho_train(2026L) |> deframe()

league <- map_dfr(sort(unique(bt$week)), function(w) {
  lu <- lineups |> filter(week == w)
  n  <- 10000L
  teams <- unique(lu$nfl_team)
  z0 <- matrix(rnorm(n * length(teams)), ncol = length(teams), dimnames = list(NULL, teams))

  total <- function(tid, joint) {
    rows <- lu |> filter(team_id == tid)
    reduce(map(seq_len(nrow(rows)), function(i) {
      r <- rows[i, ]
      # no forecast, or the zero row of a ruled-out player: forecast 0, as production
      if (is.na(r$projection) || is.na(r$coverage_class)) return(rep(0, n))
      v <- dist_of(r$pos, r$projection, r$coverage_class, pc_2026)
      e <- player_noise[[as.character(r$espn_id)]]
      z <- if (joint && r$pos == "QB") {
        z0[, r$nfl_team]
      } else if (joint && !is.na(r$role)) {
        rho <- rho_2026[[r$role]]
        rho * z0[, r$nfl_team] + sqrt(1 - rho^2) * e
      } else e
      pick_q(v, pnorm(z))
    }), `+`)
  }
  player_noise <- map(set_names(as.character(unique(lu$espn_id))), \(.) rnorm(n))

  bt |>
    filter(week == w) |>
    pmap_dfr(function(matchup_id, home_team_id, away_team_id, winner,
                      home_points, away_points, ...) {
      side <- function(joint) {
        h <- total(home_team_id, joint)
        a <- total(away_team_id, joint)
        inside <- function(v, y) between(y, quantile(v, .1), quantile(v, .9))
        list(p = mean(h > a) + mean(h == a) / 2,
             hits = inside(h, home_points) + inside(a, away_points),
             sd = (sd(h) + sd(a)) / 2)
      }
      i <- side(FALSE)
      j <- side(TRUE)
      tibble(week = w, matchup_id, winner, p_indep = i$p, p_joint = j$p,
             hits_indep = i$hits, hits_joint = j$hits, sd_indep = i$sd, sd_joint = j$sd)
    })
})
league <- league |> filter(winner %in% c("HOME", "AWAY")) |> mutate(home_won = as.numeric(winner == "HOME"))
league_summary <- league |>
  summarise(n = n(), brier_indep = mean((p_indep - home_won)^2),
            brier_joint = mean((p_joint - home_won)^2),
            mean_abs_shift = mean(abs(p_joint - p_indep)),
            n_shift_2pp = sum(abs(p_joint - p_indep) > 0.02),
            max_shift = max(abs(p_joint - p_indep)),
            n_flip = sum((p_indep > .5) != (p_joint > .5)),
            cov80_indep = sum(hits_indep) / (2 * n()), cov80_joint = sum(hits_joint) / (2 * n()),
            sd_indep = mean(sd_indep), sd_joint = mean(sd_joint))
stack_exposure <- lineups |>
  filter(!is.na(pos)) |>
  summarise(stacked = any(nfl_team[pos == "QB"] %in% nfl_team[pos %in% c("WR", "TE")]),
            .by = c(week, team_id)) |>
  summarise(team_weeks = n(), share_stacked = mean(stacked))

qb <- list(effect = effect, by_role = by_role, others = others, starter_only = starter_only,
           priced = priced, placebo = placebo, verdict = verdict, by_season = by_season,
           corr_role = corr_role, corr_2026 = corr_2026, corr_placebo = corr_placebo,
           stack_summary = stack_summary, stack_by_season = stack_by_season,
           stack_delta = stack_delta, league = league, league_summary = league_summary,
           effect_ensemble = effect_ensemble, priced_ensemble = priced_ensemble,
           verdict_ensemble = verdict_ensemble, verdict_backup = verdict_backup,
           stack_exposure = stack_exposure)
saveRDS(qb, "./data/temp/analysis_qb_influence.rds")

# figures -------------------------------------------------------------------------
ar_verdict <- readRDS("./data/temp/analysis_against_rank.rds")$verdict
fig3 <- bind_rows(ar_verdict |> mutate(factor = "Against Rank"),
                  verdict |> mutate(factor = "Projeção do QB")) |>
  mutate(pos = factor(pos, levels = rev(c("QB", "RB", "WR", "TE", "K", "DST")))) |>
  ggplot(aes(d_mae, pos)) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(xintercept = -0.05, colour = "#52514e", linewidth = 0.3, linetype = "dashed") +
  geom_pointrange(aes(xmin = lo, xmax = hi), colour = .col_a, linewidth = 0.7, size = 0.45) +
  annotate("text", x = -0.05, y = Inf, label = "ganho mínimo", hjust = -0.05, vjust = 1.4,
           size = 3, colour = "#52514e") +
  facet_wrap(~factor) +
  scale_x_continuous(labels = scales::label_number(decimal.mark = ",", accuracy = 0.01)) +
  labs(x = "Mudança no erro absoluto médio, 2022-2025 (negativo = melhor)", y = NULL) +
  theme_report()
save_fig(fig3, "fig3_ganho_fora_da_amostra.png", height = 4)

fig4 <- bind_rows(corr_role |> mutate(era = "2020-2025"), corr_2026 |> mutate(era = "2026")) |>
  mutate(role = factor(role, levels = rev(.roles))) |>
  ggplot(aes(spearman, role, colour = era)) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = 0.5),
                  linewidth = 0.7, size = 0.45) +
  scale_colour_manual(values = c("2020-2025" = .col_a, "2026" = .col_b)) +
  scale_x_continuous(labels = num_br) +
  labs(x = "Correlação entre a surpresa do jogador e a do QB (Spearman)", y = NULL) +
  theme_report()
save_fig(fig4, "fig4_correlacao_qb.png", height = 4.6)

fig5 <- stack_by_season |>
  mutate(season = factor(season)) |>
  ggplot(aes(season, cov80, colour = model, group = model)) +
  geom_hline(yintercept = 0.8, colour = "#52514e", linewidth = 0.3, linetype = "dashed") +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.6) +
  geom_text(data = \(x) filter(x, season == "2026"), aes(label = model), hjust = -0.12,
            size = 3.3, colour = "#0b0b0b") +
  annotate("text", x = 0.6, y = 0.805, label = "alvo 80%", hjust = 0, vjust = 0,
           size = 3, colour = "#52514e") +
  scale_x_discrete(expand = expansion(add = c(0.4, 1.1))) +
  scale_colour_manual(values = c("correlacionado" = .col_a, "independente" = .col_b)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0.6, 0.9)) +
  labs(x = NULL, y = "Cobertura do intervalo P10-P90") +
  theme_report()
save_fig(fig5, "fig5_stack_cobertura.png", height = 4)
