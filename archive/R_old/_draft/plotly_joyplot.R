library(tidyverse)
library(plotly)

p <- tibble(
  value = round(rnorm(100),1),
  class = rep(LETTERS[1:5], 20)
) %>% 
  ggplot(aes(x=value, y=class, fill=class)) +
  geom_density_ridges(scale=2, color="white", alpha=.7) +
  theme_ridges()

plotly::ggplotly(p)

huron <- data.frame(year = 1875:1972, level = as.vector(LakeHuron))
h <- ggplot(huron, aes(year))

h + geom_ribbon(aes(ymin=0, ymax=level+1))
h + geom_area(aes(y = level))

h +
  geom_ribbon(aes(ymin = level - 1, ymax = level + 1), fill = "grey70") +
  geom_line(aes(y = level))


p <- tibble(
  value = round(rnorm(100),1),
  class = rep(LETTERS[1:5], 20)
) %>% 
  ggplot(aes(x=value, y=class, fill=class)) +
  geom_violin(color="white", alpha=.7, scale=2, trim = F,draw_quantiles = c(0.25, 0.5, 0.75)) +
  theme_light()
  
  
tibble(
  value = round(rnorm(100),1),
  class = rep(LETTERS[1:5], 20)
) %>% 
  plot_ly(x=~value, y=~class, type="violin", split=~class, side="positive", orientation="h")
                      
                      
                      