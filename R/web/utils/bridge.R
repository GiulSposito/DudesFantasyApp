# ffa_id -> ESPN player_id as the decision engine bridged it for THIS run
# (bridge_espn_to_ffa() output persisted in current_players + free_agents).
#
# analytical_db$player_ids$espn_id is a historical xref and is stale for a
# slice of veterans (e.g. McCaffrey 18279 vs ESPN's 3117251), so marts that
# expose an ESPN id prefer this map and only fall back to the xref.
run_espn_bridge <- function(src, run) {
  rostered <- src$decision_db$current_players |>
    filter(run_id == run$run_id, !is.na(ffa_id), !is.na(espn_id)) |>
    transmute(ffa_id = as.integer(ffa_id), run_espn_id = as.integer(espn_id))
  fa <- src$decision_db$free_agents |>
    filter(run_id == run$run_id, !is.na(ffa_id), !is.na(player_id)) |>
    transmute(ffa_id = as.integer(ffa_id), run_espn_id = as.integer(player_id))

  bind_rows(rostered, fa) |> distinct(ffa_id, .keep_all = TRUE)
}
