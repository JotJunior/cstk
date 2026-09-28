#!/bin/sh
# test_jira-title.sh — cobre plugins/cstk-jira/scripts/jira-title.sh
# (cstk-jira, FASE 6 tarefa 6.2.3/6.2.8).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity LocalWorkItem;
#      docs/specs/cstk-jira/checklists/api.md CHK012 (mesmo efeito
#      observavel entre caminho MCP e REST); plugins/cstk-jira/scripts/
#      jira-sync.sh `_js_cmd_convert` (unico outro chamador ate agora).
#
# `jira-title.sh` e POSIX sh puro (sem jq/rede) — nao precisa de nenhum
# stub/fixture, so exercita a composicao de string.
#
# Invariantes cobertos:
#   JTL-1 compose --kind epic: imprime o titulo tal-e-qual
#   JTL-2 compose --kind subtask: imprime o titulo tal-e-qual (phase/local-
#         key informados sao ignorados)
#   JTL-3 compose --kind task: imprime "[<2 primeiras palavras de phase>]
#         <local-key> <title>" (paridade byte-a-byte com o formato coberto
#         por test_jira-sync.sh SY-10 "[FASE 1] 1.1 Titulo da tarefa")
#   JTL-4 compose --kind task sem --phase -> exit 2, uso incorreto
#   JTL-5 compose --kind task sem --local-key -> exit 2, uso incorreto
#   JTL-6 compose --kind invalido -> exit 2
#   JTL-7 compose sem --title -> exit 2
#   JTL-8 subcomando desconhecido -> exit 2
#   JTL-9 sem subcomando / --help -> exit 0, imprime uso

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-title.sh"

scenario_compose_epic_titulo_tal_e_qual() {
  assert_exit 0 "$SCRIPT" compose --kind epic --title "Titulo do Epic" || return 1
  assert_stdout_contains "Titulo do Epic" || return 1
}

scenario_compose_subtask_titulo_tal_e_qual_ignora_phase_e_key() {
  assert_exit 0 "$SCRIPT" compose --kind subtask --phase "FASE 9 - Ignorado" \
    --local-key "9.9.9" --title "Sub um" || return 1
  [ "$_CAPTURED_STDOUT" = "Sub um" ] \
    || { _fail "subtask_tal_e_qual" "esperado 'Sub um', obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_compose_task_formato_fase_key_titulo() {
  assert_exit 0 "$SCRIPT" compose --kind task --phase "FASE 6 - Skills Interativas" \
    --local-key "6.2" --title "Skill jira-convert" || return 1
  [ "$_CAPTURED_STDOUT" = "[FASE 6] 6.2 Skill jira-convert" ] \
    || { _fail "task_format" "esperado '[FASE 6] 6.2 Skill jira-convert', obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_compose_task_paridade_com_jira_sync_sy10() {
  # Mesmos valores exercitados por test_jira-sync.sh SY-10
  # ("[FASE 1] 1.1 Titulo da tarefa") — paridade byte-a-byte (CHK012).
  assert_exit 0 "$SCRIPT" compose --kind task --phase "FASE 1 - Sincronizacao" \
    --local-key "1.1" --title "Titulo da tarefa" || return 1
  [ "$_CAPTURED_STDOUT" = "[FASE 1] 1.1 Titulo da tarefa" ] \
    || { _fail "task_paridade_sy10" "esperado '[FASE 1] 1.1 Titulo da tarefa', obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_compose_task_sem_phase_exit2() {
  assert_exit 2 "$SCRIPT" compose --kind task --local-key "1.1" --title "X" || return 1
}

scenario_compose_task_sem_local_key_exit2() {
  assert_exit 2 "$SCRIPT" compose --kind task --phase "FASE 1 - X" --title "X" || return 1
}

scenario_compose_kind_invalido_exit2() {
  assert_exit 2 "$SCRIPT" compose --kind bogus --title "X" || return 1
}

scenario_compose_sem_title_exit2() {
  assert_exit 2 "$SCRIPT" compose --kind epic || return 1
}

scenario_subcomando_desconhecido_exit2() {
  assert_exit 2 "$SCRIPT" bogus-sub || return 1
}

scenario_sem_subcomando_imprime_uso_exit0() {
  assert_exit 0 "$SCRIPT" || return 1
  assert_stdout_contains "jira-title.sh" || return 1
}

run_all_scenarios
