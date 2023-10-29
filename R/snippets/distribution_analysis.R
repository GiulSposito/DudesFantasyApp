# exercicio para combinar probabilidades
library(dm)
library(tidyverse)
#library(fitdistrplus)

source("./R/transformation/simulation.R")

errors <- calcProjectionErrors(2023, 1:7)

ffa <- readRDS("./data/ffa_db.rds")
proj <- ffa$ffa_proj_source_points |> 
  filter(timestamp==max(timestamp), week==8)

id_map <- transmute(ffa$ffa_player_ids, id, playerId=as.integer(nfl_id))

projections <- applyErrorToProjection(proj, errors)

projections |> 
  filter(id==13589) |>
  ggplot(aes(x=points, fill=pos)) +
    geom_density(alpha=.5, bins = 30) +
  theme_minimal()


fit <- projections |> 
  filter(id==13589) |> 
  pull(points) |> 
  logspline::logspline()

projections |> 
  filter(id==13589) |> 
  pull(points) |> 
  hist(breaks = 15, col="red")

projections |> 
  filter(id==13589) |> 
  ggplot(aes(x=points)) +
  geom_density(fill="red", alpha=.5)


stt <- readRDS("./data/nfl_stats_db.rds")

likelihood <- stt$nfl_players_points |> 
  inner_join(id_map, by=join_by(playerId)) |> 
  filter(id==13589, week!=0) |> 
  pull(pts) |> 
  density()
  
data <- projections |> 
  filter(id==13589) |> 
  pull(points) |> 
  density()


# Calculate the posterior by multiplying the prior and likelihood
posterior <- data$y * likelihood$y

# Normalize the posterior to make it a proper density
posterior <- posterior / sum(posterior)

# Generate random indices based on posterior values
random_indices_posterior <- sample(length(data$x), size = 100, 
                                   replace = TRUE, prob = posterior)

# Use the randomly chosen indices to get corresponding values from density support points
random_numbers_posterior <- data$x[random_indices_posterior]

random_numbers_posterior

plot(data)
plot(likelihood)
plot(density(random_numbers_posterior))


x <- projections |> 
  filter(id==13589) |> 
  pull(points)

# RANDOM DRAW FROM EPDF ####

den <- density(x)
x_idx <- sample(length(den$x), 30, replace = T, prob=den$y)
x_hat <- den$x[x_idx]

# RANDOM DRAW FROM EPDF ####

den |> plot()
x_hat |> 
  hist(breaks = 500, col="red")

rnorm

tibble(
    points = sample(pull(filter(projections, id == 13589), points),1000, replace = TRUE),
    spline = logspline::rlogspline(1000, fit),
    density = sample(pull(filter(projections, id == 13589), points),1000, replace = TRUE) + rnorm(1000, 0, den$bw)
  ) |>
  pivot_longer(c(points, spline, density)) |>
  ggplot(aes(x = value, fill = name)) +
  geom_density(alpha = .5) +
  theme_minimal()


 |> 
  tibble(points=_) |> 
  ggplot(aes(x=points)) +
  geom_density(alpha=.5, bins = 30) +
  theme_minimal()


den <-  |> 
  density()
  
N <- 5000
newx <- projections |> 
  filter(id==13589) |> 
  pull(points) |> 
  sample(N, replace=TRUE) + rnorm(N, 0, den$bw)


tibble(points=newx) |>
  ggplot(aes(x=points)) +
  geom_histogram(alpha=.5, bins = 30) +
  theme_minimal()

  
  ecdf() |>
  knots() |>
  density(from = -10, to = 100)

approx( 
  cumsum(pdfden$y)/sum(pdfden$y),
  pdfden$x,
  runif(10))$y

approx(cumsum(pdfden$y) / sum(pdfden$y),
       pdfden$x, runif(.n))$y 



pdfden <- .dt %>%
  pull(pts.proj) %>%
  ecdf() %>%
  knots() %>%
  density(from = -10, to = 100)

ed(runif(1000))
  
  plot()
  
  
  fitdistrplus::descdist(discrete = F, boot=1500)




projections |> 
  filter(id==13589) |> 
  pull(points) |> 
  fitdistrplus::fitdist("logis") |> 
  plot()
  
rl


stt <- readRDS("./data/nfl_stats_db.rds")
plr <- readRDS("./data/nfl_players_db.rds")




map_id <- ffa$ffa_player_ids |> 
  transmute(id=id, playerId=as.integer(nfl_id))

points <- stt$nfl_players_points |> 
  filter(week!=0) |> 
  inner_join(map_id, by = join_by(playerId))

proj <- ffa$ffa_proj_source_points |> 
  filter(timestamp==max(timestamp), .by=c(season,week)) 

plrs <- plr$nfl_players |> 
  select(playerId, position, name)

proj |> 
  filter(week==8) |> 
  applyErrorToProjection(errors) |> 
  filter(id==13589) |> 
  pull(ptsProj) |> 
  descdist()

points |> 
  inner_join(plrs, by = join_by(playerId)) |> 
  filter(position=="QB") |> 
  ggplot(aes(x=pts, fill=position)) +
  geom_density(alpha=.5) +
  theme_light()

proj |> 
  filter(pos=="QB") |> 
  ggplot(aes(x=points, fill=pos)) +
  geom_density(alpha=.5) +
  theme_light()


points |> 
  inner_join(plrs, by = join_by(playerId)) |> 
  filter(position=="QB", id==13589) |> 
  ggplot(aes(x=pts, fill=position)) +
  geom_density(alpha=.5) +
  theme_light()

points |> 
  inner_join(plrs, by = join_by(playerId)) |> 
  filter(position=="QB", id==13589) |> 
  pull(pts) |> 
  fitdistrplus::descdist(discrete = F, boot = 1000)

dt <- points |> 
  inner_join(plrs, by = join_by(playerId)) |> 
  filter(position=="QB", id==13589) |> 
  pull(pts)
  
fitdist(dt, "norm", discrete = F) |> plot()
fitdist(dt, "norm", discrete = F) |> 
  cdfcomp()

fitdist(dt, "unif", discrete = F) |> plot()
fitdist(dt, "unif", discrete = F) |> summary()

fitdist(dt, "exp", discrete = F) |> plot()
fitdist(dt, "exp", discrete = F) |> summary()

fitdist(dt, "beta", discrete = F) |> plot()
fitdist(dt, "beta", discrete = F) |> summary()

fitdist(dt, "weibull", discrete = F) |> plot()
fitdist(dt, "weibull", discrete = F) |> 
  cdfcomp()

proj |> 
  filter(week==8, id==13589) |> 
  pull(points) |> 
  descdist(discrete = F, boot=1500)

proj |> 
  filter(week==8, id==13589) |> 
  pull(points) |> 
  fitdist("weibull") |> 
  cdfcomp()


points |> 
  inner_join(plrs, by = join_by(playerId)) |> 
  filter(position=="QB") |> 
  pull(pts) |> 
  fitdist("norm", discrete = F) |> 
  sum
