# Web bundle - privacy modes (contract section 36).
#
#   private : may expose team names + manager display names (default)
#   public  : strip manager real names + owner/member ids
#
# Central per-mart strip list. Anything not listed passes through untouched.

library(tidyverse)

.PRIVACY_STRIP <- list(
  teams = c("owner_name", "owner_ids", "owners", "owner_id")
)

# df   : a mart tibble
# mart : mart name ("teams", "trade_recommendations", ...)
# mode : "private" | "public"
apply_privacy <- function(df, mart, mode = c("private", "public")) {
  mode <- match.arg(mode)
  if (mode != "public") return(df)
  drop <- .PRIVACY_STRIP[[mart]]
  if (is.null(drop)) return(df)
  df |> select(-any_of(drop))
}
