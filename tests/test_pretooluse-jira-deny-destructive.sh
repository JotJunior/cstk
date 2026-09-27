#!/bin/sh
# test_pretooluse-jira-deny-destructive.sh — cobre
# plugins/cstk-jira/hooks/pretooluse-jira-deny-destructive.sh (cstk-jira,
# FASE 5.2 "Hooks do Ciclo de Vida" — guarda de exclusao via Rovo MCP).
#
# Ref: docs/specs/cstk-jira/contracts/hooks.md "Comportamento de
#      pretooluse-jira-deny-destructive.sh"; contracts/rovo-mcp.md
#      "Tools proibidas"; tasks.md 5.2.5/5.2.6.
#
# _find_scripts (tests/run.sh) so escaneia plugins/cstk-jira/scripts/*.sh —
# hooks/ fica fora do escaneio por convencao (mesmo tratamento de
# test_posttooluse-jira-sync.sh/test_pretooluse-bash-guard.sh). Por isso
# este arquivo esta na allowlist de _is_internal_test em tests/run.sh
# (existence-guarded).
#
# O script sob teste NAO aceita tool_input via argv — le JSON do stdin
# (contrato do harness). Invocamos via `_run_hook` (printf | script), mesmo
# idioma de test_posttooluse-jira-sync.sh::_run_hook.
#
# Invariantes cobertos:
#   PJD-1 tool_name casando deleteJiraIssue + config presente -> exit 2 +
#         stderr citando FR-012 (5.2.2/5.2.5)
#   PJD-2 tool_name casando executeDestructive + config presente -> exit 2
#         + stderr citando FR-012 (5.2.5)
#   PJD-3 tool_name casando (qualquer prefixo mcp__X__) + config AUSENTE ->
#         exit 0, stdout vazio (5.2.3/5.2.6/FR-017/SC-006)
#   PJD-4 tool_name NAO casando (ex.: mcp__jira__getJiraIssue) + config
#         presente -> exit 0 (defesa redundante do matcher, 5.2.1)
#   PJD-5 prefixo arbitrario de instalacao do Rovo MCP
#         (mcp__atlassian-rovo-mcp-server__deleteJiraIssue) + config
#         presente -> exit 2 (research Decision 1 — qualquer prefixo casa)
#
# Mutation guard (verificado manualmente nesta onda, nao permanece como
# scenario — a suite de mutation dedicada e tasks.md 8.4.3/8.4.4): comentar
# a linha `mcp__*__deleteJiraIssue | mcp__*__executeDestructive) ;;` do
# script (deixando so `*) exit 0 ;;`) faz PJD-1/PJD-2/PJD-5 falharem (exit 0
# em vez de exit 2) — confirma que a asserção positiva depende do match,
# nao de outro efeito colateral do script.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/hooks/pretooluse-jira-deny-destructive.sh"

# _run_hook JSON -> invoca o hook com JSON via stdin. NUNCA chama `capture`
# aqui (nested capture corromperia os tmpfiles do `capture` externo usado
# por assert_exit).
_run_hook() {
  printf '%s' "$1" | "$SCRIPT"
}

_config_present() {
  mkdir -p "$1/.claude/cstk-jira"
  printf 'config_version=1\nsync_autonomous=on\n' > "$1/.claude/cstk-jira/config"
}

_json_pretooluse() {
  # $1 cwd, $2 tool_name
  printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"issueIdOrKey":"DEMO-1"}}' \
    "$1" "$2"
}

scenario_delete_jira_issue_com_config_bloqueia() {
  _config_present "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__deleteJiraIssue")
  assert_exit 2 _run_hook "$_J" || return 1
  assert_stderr_contains "FR-012" || return 1
  return 0
}

scenario_execute_destructive_com_config_bloqueia() {
  _config_present "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__executeDestructive")
  assert_exit 2 _run_hook "$_J" || return 1
  assert_stderr_contains "FR-012" || return 1
  return 0
}

# PJD-3 (5.2.3/5.2.6/FR-017/SC-006): sem config, guarda e no-op mesmo com
# tool_name casando o matcher.
scenario_sem_config_no_op() {
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__deleteJiraIssue")
  assert_exit 0 _run_hook "$_J" || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout_vazio" "stdout nao vazio: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

# PJD-4 (5.2.1): tool_name que NAO casa o deny-list (leitura, nao exclusao)
# nunca e bloqueada, mesmo com config presente.
scenario_tool_nao_destrutiva_no_op() {
  _config_present "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__getJiraIssue")
  assert_exit 0 _run_hook "$_J" || return 1
  return 0
}

# PJD-5 (research Decision 1): qualquer prefixo de instalacao do Rovo MCP
# casa o matcher — nao so "atlassian".
scenario_prefixo_arbitrario_bloqueia() {
  _config_present "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian-rovo-mcp-server__deleteJiraIssue")
  assert_exit 2 _run_hook "$_J" || return 1
  assert_stderr_contains "FR-012" || return 1
  return 0
}

# ==== modo project-create (r02 FASE 19 tarefa 19.2, FR-024) ====
#
#   PJD-6 createJiraProject + execucao 00c ativa + config presente -> exit 2
#   PJD-7 createJiraProject sem execucao ativa (sessao interativa pura) +
#         config presente -> exit 0 (o gate e o prompt do Claude Code + a
#         confirmacao da skill jira-setup)
#   PJD-8 createJiraProject + execucao ativa SEM config -> exit 0
#         (FR-017/SC-006: plugin nao configurado nao muda comportamento)

_active_lock() {
  mkdir -p "$1/.claude/feature-00c-state/cstk-jira/.lock"
}

scenario_create_project_com_execucao_ativa_e_config_bloqueia() {
  _config_present "$TMPDIR_TEST"
  _active_lock "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__createJiraProject")
  assert_exit 2 _run_hook "$_J" || return 1
  assert_stderr_contains "FR-024" || return 1
  return 0
}

scenario_create_project_sem_execucao_ativa_no_op() {
  _config_present "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__createJiraProject")
  assert_exit 0 _run_hook "$_J" || return 1
  return 0
}

scenario_create_project_execucao_ativa_sem_config_no_op() {
  _active_lock "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__createJiraProject")
  assert_exit 0 _run_hook "$_J" || return 1
  return 0
}

run_all_scenarios
