# Ad-hoc analysis: does the opposing defense's Against Rank explain what the
# projection misses? Report: docs/analysis_against_rank_qb.md.
#
# Run from the project root: source("R/snippets/analysis_against_rank.R")
# Leaves the tables in `ar` and saves them to data/temp/analysis_against_rank.rds.

source("./R/snippets/analysis_matchup_panel.R")

set.seed(20261106)
.pos_all <- c("QB", "RB", "WR", "TE", "K", "DST")

d    <- panel |> filter(week >= 4L, !is.na(opp_z))
hist <- d |> filter(season <= 2025L)
f_opp <- residual ~ opp_z + bin + factor(season)

# 1. descriptive, by rank band ----------------------------------------------------
band <- function(r) cut(r, c(0, 8, 16, 24, 32),
                        labels = c("1-8 difícil", "9-16", "17-24", "25-32 fácil"))
descr <- hist |>
  mutate(band = band(opp_rank)) |>
  group_by(pos, band) |>
  group_modify(function(g, ...) {
    r <- boot_ratio(g$residual, rep(1, nrow(g)), g$team_game)
    tibble(n = nrow(g), proj = mean(g$projection), actual = mean(g$actual_points),
           resid = r$est, resid_lo = r$lo, resid_hi = r$hi,
           realized = sum(g$actual_points) / sum(g$projection))
  }) |>
  ungroup()

# 2. already priced in? -----------------------------------------------------------
# Within player-season, so a player's level does not pollute the slope: how much the
# projection moves per SD of matchup, against how much the points really move.
within <- hist |>
  filter(n() >= 4L, .by = c(season, ffa_id, pos)) |>
  mutate(proj_dev = projection - mean(projection),
         act_dev  = actual_points - mean(actual_points),
         z_dev    = opp_z - mean(opp_z),
         .by = c(season, ffa_id, pos))
priced <- bind_rows(
  slope_by_pos(within, proj_dev ~ z_dev, "z_dev") |> mutate(what = "projeção"),
  slope_by_pos(within, act_dev ~ z_dev, "z_dev") |> mutate(what = "realizado")
)

# 3. what is left after the projection (primary test) -----------------------------
effect <- slope_by_pos(hist, f_opp, "opp_z") |> mutate(p_holm = p.adjust(p, "holm"))

early <- slope_by_pos(panel |> filter(week %in% 2:3, season <= 2025L, !is.na(opp_z)),
                      f_opp, "opp_z")

tier_of <- function(x) cut(x, c(-Inf, 6, 12, Inf), labels = c("<6", "6-12", ">=12"))
by_tier <- hist |>
  mutate(tier = tier_of(projection)) |>
  group_by(tier) |>
  group_modify(\(g, ...) slope_by_pos(g, residual ~ opp_z + factor(season), "opp_z")) |>
  ungroup()
by_coverage <- hist |>
  group_by(coverage_class) |>
  group_modify(\(g, ...) slope_by_pos(g, f_opp, "opp_z")) |>
  ungroup()

# rank or magnitude? shape?
shape <- map_dfr(.pos_all, function(p) {
  g <- hist |> filter(pos == p)
  rank_z <- as.numeric(scale(g$opp_rank))
  m_z <- lm(f_opp, g)
  m_r <- lm(residual ~ rank_z + bin + factor(season), g)
  gam <- mgcv::gam(residual ~ s(opp_rank, k = 6) + bin + factor(season), data = g)
  tibble(pos = p, aic_z = AIC(m_z), aic_rank = AIC(m_r), aic_gam = AIC(gam),
         edf = sum(gam$edf[grepl("opp_rank", names(coef(gam)))]),
         r2_add = summary(m_z)$r.squared -
           summary(lm(residual ~ bin + factor(season), g))$r.squared)
})

# 4. spread -----------------------------------------------------------------------
spread <- hist |>
  mutate(third = cut(opp_z, quantile(opp_z, 0:3 / 3), include.lowest = TRUE,
                     labels = c("difícil", "média", "fácil")), .by = pos) |>
  summarise(n = n(), sd = sd(residual),
            p10 = quantile(residual, .1), p90 = quantile(residual, .9),
            width = p90 - p10, .by = c(pos, third)) |>
  arrange(match(pos, .pos_all), third)
spread_slope <- hist |>
  mutate(abs_dev = abs(residual - fitted(lm(f_opp, pick(everything())))), .by = pos) |>
  slope_by_pos(abs_dev ~ opp_z + bin + factor(season), "opp_z")

# 5. robustness with ranks that really existed before the game --------------------
real_rank <- function(data, col, label) {
  data |>
    filter(!is.na(.data[[col]])) |>
    mutate(real_z = as.numeric(scale(.data[[col]])), .by = pos) |>
    slope_by_pos(residual ~ real_z + bin, "real_z") |>
    mutate(source = label)
}
robust <- bind_rows(
  real_rank(panel |> filter(season == 2025L, week >= 4L), "nflcom_rank", "NFL.com 2025"),
  real_rank(panel |> filter(season == 2026L, week >= 5L), "espn_rank", "ESPN 2026 W5-W8")
)

placebo <- perm_placebo(hist, "opp_z", .pos_all)

# out of sample -------------------------------------------------------------------
oos <- oos_rows(d, "opp_z")
verdict <- oos_verdict(oos) |> arrange(match(pos, .pos_all))
by_season <- oos |>
  mutate(d_abs = abs(residual - shift) - abs(residual)) |>
  summarise(d_mae = mean(d_abs), n = n(), .by = c(pos, season))
# exploratory: only players with several sources, the bulk of real starters
verdict_ensemble <- oos_rows(filter(d, coverage_class == "ensemble"), "opp_z") |>
  oos_verdict() |>
  arrange(match(pos, .pos_all))

# simulation: production distribution against the same one shifted by beta * z, and
# against that shift plus a pool scaled by the spread slope (exploratory: spread
# is where the matchup signal looked strongest in step 4)
check_baseline()

spread_gain <- function(train) {
  train |>
    mutate(abs_dev = abs(residual - fitted(lm(f_opp, pick(everything())))), .by = pos) |>
    summarise(gain = coef(lm(abs_dev ~ opp_z + bin + factor(season)))[["opp_z"]] / mean(abs_dev),
              .by = pos)
}

sim_scores <- map_dfr(c(2022:2025, 2026L), function(s) {
  pc <- pool_center(panel |> filter(season < s, !is.na(residual), !is.na(projection)))
  gain <- spread_gain(d |> filter(season < s))
  rows <- oos |> filter(season == s) |> left_join(gain, by = "pos")
  map_dfr(seq_len(nrow(rows)), function(i) {
    r <- rows[i, ]
    y <- r$actual_points
    base  <- dist_of(r$pos, r$projection, r$coverage_class, pc)
    shift <- dist_of(r$pos, r$projection, r$coverage_class, pc, r$shift)
    # scale the centred spread around the shifted centre
    mid   <- mean(shift)
    scale <- mid + (shift - mid) * max(1 + r$gain * r$opp_z, 0.5)
    bind_rows(score_dist(base, y) |> mutate(model = "produção"),
              score_dist(shift, y) |> mutate(model = "média"),
              score_dist(scale, y) |> mutate(model = "média + dispersão")) |>
      mutate(pos = r$pos, season = s, team_game = r$team_game, row = i)
  })
})
sim_summary <- sim_scores |>
  mutate(era = if_else(season <= 2025L, "2022-2025", "2026")) |>
  summarise(n = n(), pinball = mean(pinball), crps = mean(crps),
            cov80 = mean(in80), cov50 = mean(in50), .by = c(era, pos, model)) |>
  arrange(era, match(pos, .pos_all), model)

# paired against production, block bootstrap
sim_delta <- sim_scores |>
  select(season, pos, team_game, row, model, crps) |>
  pivot_wider(names_from = model, values_from = crps) |>
  pivot_longer(c("média", "média + dispersão"), names_to = "model", values_to = "crps") |>
  mutate(d_crps = crps - `produção`, era = if_else(season <= 2025L, "2022-2025", "2026")) |>
  group_by(era, pos, model) |>
  group_modify(\(g, ...) boot_ratio(g$d_crps, rep(1, nrow(g)), g$team_game) |>
                 mutate(seasons_better = sum(tapply(g$d_crps, g$season, mean) < 0))) |>
  ungroup()

ar <- list(descr = descr, priced = priced, effect = effect, early = early,
           by_tier = by_tier, by_coverage = by_coverage, shape = shape, spread = spread,
           spread_slope = spread_slope, robust = robust, placebo = placebo,
           verdict = verdict, by_season = by_season, sim_summary = sim_summary,
           sim_delta = sim_delta, verdict_ensemble = verdict_ensemble)
saveRDS(ar, "./data/temp/analysis_against_rank.rds")

# figures -------------------------------------------------------------------------
pos_order <- function(x) factor(x, levels = rev(.pos_all))

fig1 <- descr |>
  mutate(pos = factor(pos, levels = .pos_all),
         band = factor(sub(" .*", "", band), levels = c("1-8", "9-16", "17-24", "25-32"))) |>
  ggplot(aes(band, resid)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_pointrange(aes(ymin = resid_lo, ymax = resid_hi), colour = .col_a,
                  linewidth = 0.7, size = 0.45) +
  facet_wrap(~pos, nrow = 2) +
  scale_y_continuous(labels = num_br) +
  labs(x = "Against Rank do adversário (1-8 = defesas mais difíceis)",
       y = "Realizado menos projetado (pontos)") +
  theme_report()
save_fig(fig1, "fig1_residuo_por_rank.png", height = 5.2)

fig2 <- priced |>
  mutate(pos = pos_order(pos), what = factor(what, levels = c("projeção", "realizado"))) |>
  ggplot(aes(est, pos, colour = what)) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = 0.5),
                  linewidth = 0.7, size = 0.45) +
  scale_colour_manual(values = c("projeção" = .col_a, "realizado" = .col_b)) +
  scale_x_continuous(labels = num_br) +
  labs(x = "Pontos por 1 desvio-padrão de adversário mais fácil", y = NULL) +
  theme_report()
save_fig(fig2, "fig2_precificado.png", height = 4.4)
