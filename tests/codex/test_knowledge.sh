#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_ingestion_is_idempotent_and_runtime_model_are_preserved() {
  t_ready || return; t_good open_wave || return; t_pause || return
  assert_exit 0 sh "$REPO_ROOT/cli/cstk" recall --ingest --state-dir "$CX_STATE" || return
  _kn_provenance=$(sqlite3 "$CSTK_KNOWLEDGE_DB" 'SELECT execution_provenance FROM executions;')
  [ "$(sqlite3 "$CSTK_KNOWLEDGE_DB" 'SELECT count(*) FROM executions;')" = 1 ] && [ "$(cj_get "$_kn_provenance" /runtime)" = codex ] && [ "$(cj_get "$_kn_provenance" /model)" = null ]
}
scenario_empty_or_degraded_recall_is_audited() { t_ready || return; t_good open_wave || return; _kn_doc=$(t_state); _kn_events=$(cj_each "$_kn_doc" /events); printf '%s\n' "$_kn_events" | grep -F 'recall_consulted' >/dev/null && [ "$(cj_length "$CX_OFFERED")" = 0 ]; }
scenario_recalled_source_ids_are_checked_and_used_with_provenance() {
  t_ready || return
  mkdir -p "$T_PROJECT/.claude/feature-00c-state/source-feature"
  _kn_source=$T_PROJECT/.claude/feature-00c-state/source-feature
  sh "$T_RUNTIME/state-rw.sh" init --state-dir "$_kn_source" --execucao-id source-execution --projeto-alvo-path "$T_PROJECT" --descricao 'Audited local feature source execution' --canonical-project canonical-project --runtime claude-code >/dev/null || return
  sh "$T_RUNTIME/state-rw.sh" set --state-dir "$_kn_source" --field .decisions --value '[{"id":"dec-001","wave_id":"onda-001","stage":"specify","agent":"fixture","context":"Create an audited local feature","options_considered":["local"],"choice":"local","justification":"Create an audited local feature with observed source artifacts.","justification_score":3,"evidence":"Existing source implementation inspected.","references":["spec.md"],"timestamp":"2026-10-03T00:00:00Z"}]' >/dev/null || return
  assert_exit 0 sh "$REPO_ROOT/cli/cstk" recall --ingest --state-dir "$_kn_source" || return
  t_good open_wave || return
  [ "$(cj_length "$CX_OFFERED")" -gt 0 ] || { _fail recall 'expected source offered'; return 1; }
  t_evidence spec.md
  t_good complete "$(printf '{"evidence_paths":["docs/specs/test-feature/spec.md"],"rationale":"Actual artifact and recalled source inspected before completion.","used_sources":%s}' "$CX_OFFERED")" || return
  printf '%s\n' "$(t_state)" | grep -F 'recall_used' >/dev/null
}
run_all_scenarios
