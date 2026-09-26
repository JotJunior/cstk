#!/bin/sh
# test_posttooluse-jira-sync.sh — cobre
# plugins/cstk-jira/hooks/posttooluse-jira-sync.sh (cstk-jira, FASE 5.1
# "Hooks do Ciclo de Vida" — sync autonomo).
#
# Ref: docs/specs/cstk-jira/contracts/hooks.md "Comportamento de
#      posttooluse-jira-sync.sh"; data-model.md Entity OutboxEvent;
#      tasks.md 5.1.8/5.1.9/5.1.10.
#
# _find_scripts (tests/run.sh) so escaneia plugins/cstk-jira/scripts/*.sh —
# hooks/ fica fora do escaneio por convencao (mesmo tratamento de
# test_pretooluse-bash-guard.sh/test_posttooluse-tool-call-tick.sh do plugin
# cstk). Por isso este arquivo esta na allowlist de _is_internal_test em
# tests/run.sh (existence-guarded).
#
# O script sob teste NAO aceita tool_input via argv — le JSON do stdin
# (contrato do harness) e recebe o MODO (task/wave/bash) como $1 vindo do
# proprio hooks.json. Invocamos via
# `sh -c 'printf "%s" "$1" | "$2" "$3"' _ "$json" "$SCRIPT" "$modo"` (mesmo
# idioma de test_pretooluse-bash-guard.sh, positional params evitam
# problemas de quoting com aspas duplas no JSON).
#
# Invariantes cobertos:
#   HS-1  config ausente -> exit 0, stdout vazio, NENHUM arquivo criado sob
#         .claude/cstk-jira/ (5.1.8/SC-006)
#   HS-2  sync_autonomous=off -> exit 0, no-op total
#   HS-3  zero candidatos (.lock) -> exit 0 + 1 linha em runtime/hook.log
#   HS-4  dois candidatos (.lock) -> exit 0 + 1 linha em runtime/hook.log
#   HS-5  sem jira-map.tsv (feature nunca convertida) -> exit 0, outbox
#         nunca criado
#   HS-6  modo task, caminho feliz -> outbox.tsv com 1 linha
#         (feature/local_key/desired_state/source corretos)
#   HS-7  modo wave -> outbox.tsv com local_key=* desired_state=reconcile
#         source=hook-close-wave
#   HS-8  modo bash com comando IRRELEVANTE -> exit 0, outbox nunca criado
#   HS-9  modo bash com "state-ondas.sh record-task" (valores entre aspas,
#         como no JSON bruto escapado) -> outbox com task-id/outcome
#         extraidos corretamente
#   HS-10 modo bash com "state-ondas.sh end" -> outbox com
#         local_key=* desired_state=reconcile
#   HS-11 falha interna simulada (runtime/ sem permissao de escrita) ->
#         hook AINDA sai exit 0 (fail-open, 5.1.9)
#   HS-12 nao-exfiltracao: session_id sintetico no tool_input NUNCA aparece
#         em stdout, hook.log ou outbox.tsv (5.1.10/CHK013)
#   HS-13 diagnostico do drain (FASE 12 tarefa 12.7.1): ProjectConfig
#         invalido (fixture so tem config_version/sync_autonomous) ->
#         drain nao roda, diagnostico "ProjectConfig invalido/ausente" e
#         anexado a runtime/hook.log (antes era descartado)
#   HS-14 resumo pos-drain: outbox com evento auth_failed pre-existente ->
#         hook.log ganha linha "resumo pos-drain" citando
#         auth_failed=1 (data-model.md ConflictRecord "resumo emitido pelo
#         hook")
#   HS-15 resumo pos-drain OMITIDO quando outbox esta saudavel
#         (deferred=0 conflict=0 auth_failed=0) — sem ruido no caminho
#         feliz

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/hooks/posttooluse-jira-sync.sh"

# _run_hook JSON MODE -> invoca o hook com JSON via stdin + modo via argv.
# NUNCA chama `capture` aqui (nested capture corromperia os tmpfiles do
# `capture` externo usado por assert_exit — variaveis globais
# _TMP_OUT/_TMP_ERR sao compartilhadas entre chamadas aninhadas). Deixa o
# `capture`/`assert_exit` do CHAMADOR redirecionar stdout/stderr.
_run_hook() {
  printf '%s' "$1" | "$SCRIPT" "$2"
}

_config_on() {
  mkdir -p "$1/.claude/cstk-jira"
  printf 'config_version=1\nsync_autonomous=on\n' > "$1/.claude/cstk-jira/config"
}

_config_off() {
  mkdir -p "$1/.claude/cstk-jira"
  printf 'config_version=1\nsync_autonomous=off\n' > "$1/.claude/cstk-jira/config"
}

_feature_lock() {
  mkdir -p "$1/.claude/feature-00c-state/$2/.lock"
}

_jira_map() {
  mkdir -p "$1/docs/specs/$2"
  printf 'local_key\tkind\tjira_id\tjira_key\tstate\n' > "$1/docs/specs/$2/jira-map.tsv"
}

_outbox() {
  printf '%s\n' "$1/.claude/cstk-jira/runtime/outbox.tsv"
}

_hooklog() {
  printf '%s\n' "$1/.claude/cstk-jira/runtime/hook.log"
}

_json_task() {
  # $1 cwd, $2 task_id, $3 outcome, $4 session_id (opcional)
  printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"mcp__cstk-state__record_task","tool_input":{"session_id":"%s","task_id":"%s","outcome":"%s"}}' \
    "$1" "${4:-sess-000}" "$2" "$3"
}

_json_wave() {
  printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"mcp__cstk-state__close_wave","tool_input":{"session_id":"sess-000"}}' "$1"
}

_json_bash() {
  # $1 cwd, $2 command (ja com aspas internas escapadas pelo chamador)
  printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2"
}

scenario_config_ausente_no_op_total() {
  _J=$(_json_task "$TMPDIR_TEST" 1.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout_vazio" "stdout nao vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -d "$TMPDIR_TEST/.claude/cstk-jira" ] && { _fail "no_files" ".claude/cstk-jira foi criado sem config previo"; return 1; }
  return 0
}

scenario_sync_autonomous_off_no_op() {
  _config_off "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 1.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -f "$(_outbox "$TMPDIR_TEST")" ] && { _fail "no_outbox" "outbox criado com sync_autonomous=off"; return 1; }
  return 0
}

scenario_zero_candidatos_loga_e_no_op() {
  _config_on "$TMPDIR_TEST"
  _J=$(_json_task "$TMPDIR_TEST" 1.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -f "$(_hooklog "$TMPDIR_TEST")" ] || { _fail "hooklog_missing" "hook.log nao foi criado com 0 candidatos"; return 1; }
  grep -q 'candidatos=0' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "hooklog_content" "hook.log nao registrou candidatos=0"; return 1; }
  return 0
}

scenario_dois_candidatos_loga_e_no_op() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _feature_lock "$TMPDIR_TEST" outra
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 1.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  grep -q 'candidatos=2' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "hooklog_content" "hook.log nao registrou candidatos=2"; return 1; }
  [ -f "$(_outbox "$TMPDIR_TEST")" ] && { _fail "no_outbox" "outbox criado com candidatos ambiguos"; return 1; }
  return 0
}

scenario_sem_jira_map_no_op() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 1.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -f "$(_outbox "$TMPDIR_TEST")" ] && { _fail "no_outbox" "outbox criado sem jira-map.tsv (feature nunca convertida)"; return 1; }
  return 0
}

scenario_modo_task_caminho_feliz_enfileira() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -f "$(_outbox "$TMPDIR_TEST")" ] || { _fail "outbox_missing" "outbox.tsv nao foi criado"; return 1; }
  _line=$(awk -F '\t' 'NR==2' "$(_outbox "$TMPDIR_TEST")")
  printf '%s' "$_line" | grep -q '	demo	5.1	pass	hook-record-task	0	queued$' \
    || { _fail "outbox_line" "linha gravada incorreta: $_line"; return 1; }
  return 0
}

scenario_modo_wave_enfileira_reconcile() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_wave "$TMPDIR_TEST")
  assert_exit 0 _run_hook "$_J" wave || return 1
  _line=$(awk -F '\t' 'NR==2' "$(_outbox "$TMPDIR_TEST")")
  printf '%s' "$_line" | grep -q '	demo	\*	reconcile	hook-close-wave	0	queued$' \
    || { _fail "outbox_line" "linha gravada incorreta: $_line"; return 1; }
  return 0
}

scenario_modo_bash_comando_irrelevante_no_op() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_bash "$TMPDIR_TEST" "ls -la /tmp")
  assert_exit 0 _run_hook "$_J" bash || return 1
  [ -f "$(_outbox "$TMPDIR_TEST")" ] && { _fail "no_outbox" "outbox criado para comando Bash irrelevante"; return 1; }
  return 0
}

scenario_modo_bash_record_task_com_aspas_extrai_flags() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _cmd='state-ondas.sh record-task --state-dir \"/x/feature-00c-state/demo\" --task-id \"5.2\" --outcome fail'
  _J=$(_json_bash "$TMPDIR_TEST" "$_cmd")
  assert_exit 0 _run_hook "$_J" bash || return 1
  _line=$(awk -F '\t' 'NR==2' "$(_outbox "$TMPDIR_TEST")")
  printf '%s' "$_line" | grep -q '	demo	5.2	fail	hook-record-task	0	queued$' \
    || { _fail "outbox_line" "linha gravada incorreta: $_line"; return 1; }
  return 0
}

scenario_modo_bash_end_enfileira_reconcile() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_bash "$TMPDIR_TEST" "state-ondas.sh end --motivo-termino etapa_concluida_avancando")
  assert_exit 0 _run_hook "$_J" bash || return 1
  _line=$(awk -F '\t' 'NR==2' "$(_outbox "$TMPDIR_TEST")")
  printf '%s' "$_line" | grep -q '	demo	\*	reconcile	hook-close-wave	0	queued$' \
    || { _fail "outbox_line" "linha gravada incorreta: $_line"; return 1; }
  return 0
}

# HS-11 (5.1.9): falha simulada dentro do hook (runtime/ sem permissao de
# escrita, forcando enqueue/drain a falharem) -> hook ainda sai exit 0.
scenario_falha_interna_fail_open() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  chmod 500 "$TMPDIR_TEST/.claude/cstk-jira" || return 2
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task
  _rc=$?
  chmod 755 "$TMPDIR_TEST/.claude/cstk-jira" 2>/dev/null || :
  [ "$_rc" -eq 0 ] || return 1
  return 0
}

# HS-12 (5.1.10/CHK013): session_id sintetico nunca aparece em stdout,
# hook.log ou outbox.tsv.
scenario_nao_exfiltra_session_id() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _secret="SESSION-SECRET-abcdef123456"
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass "$_secret")
  assert_exit 0 _run_hook "$_J" task || return 1
  case "$_CAPTURED_STDOUT" in
    *"$_secret"*) _fail "leak_stdout" "session_id vazou em stdout"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"$_secret"*) _fail "leak_stderr" "session_id vazou em stderr"; return 1 ;;
  esac
  if grep -rq "$_secret" "$TMPDIR_TEST/.claude/cstk-jira" 2>/dev/null; then
    _fail "leak_files" "session_id vazou em algum arquivo sob .claude/cstk-jira"
    return 1
  fi
  return 0
}

scenario_diagnostico_drain_nao_e_descartado() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  # _config_on so grava config_version/sync_autonomous — jira-config.sh
  # validate falha por campos obrigatorios ausentes; o drain emite o
  # diagnostico em stderr e (12.7.1) ele passa a ser anexado ao hook.log.
  grep -q '^.*drain:.*ProjectConfig invalido/ausente' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "drain_diag_missing" "diagnostico do drain nao apareceu em hook.log: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

scenario_resumo_pos_drain_com_auth_failed() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira/runtime"
  cat > "$(_outbox "$TMPDIR_TEST")" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	1	auth_failed
EOF
  _J=$(_json_task "$TMPDIR_TEST" 5.2 fail)
  assert_exit 0 _run_hook "$_J" task || return 1
  grep -q 'resumo pos-drain (demo):.*auth_failed=1' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "resumo_missing" "resumo pos-drain com auth_failed=1 nao apareceu em hook.log: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

scenario_resumo_pos_drain_omitido_quando_saudavel() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  # outbox so tem o evento recem-enfileirado (queued=1), sem
  # conflict/auth_failed/deferred — nenhuma linha "resumo pos-drain" deve
  # aparecer (evita ruido no caminho feliz).
  grep -q 'resumo pos-drain' "$(_hooklog "$TMPDIR_TEST")" \
    && { _fail "resumo_noise" "resumo pos-drain apareceu com outbox saudavel: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

run_all_scenarios
