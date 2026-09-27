#!/bin/sh
# test_jira-setup.sh — cobre plugins/cstk-jira/scripts/jira-setup.sh
# (cstk-jira, FASE 6 tarefa 6.1).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity ProjectConfig; docs/specs/
#      cstk-jira/checklists/ux.md CHK004/CHK006; docs/specs/cstk-jira/
#      contracts/jira-rest.md R5 (roundtrip onda-011: transitions
#      To Do/In Progress/In Review/Done) e R8 (roundtrip onda-011:
#      hierarchyLevel Epic=1/Subtask=-1/Task=0/Story=0); tasks.md
#      6.1.9-6.1.10.
#
# Invariantes cobertos:
#   JS-1  check-status-mapping: fail == pass -> exit 1, diagnostico LISTA
#         os status descobertos (ux CHK004)
#   JS-2  check-status-mapping: valor mapeado fora da lista descoberta ->
#         exit 1, diagnostico lista os status disponiveis
#   JS-3  check-status-mapping: mapeamento valido -> exit 0
#   JS-4  check-status-mapping: uso incorreto (menos de 5 args) -> exit 2
#   JS-5  write-config: campo obrigatorio ausente -> exit 1, NADA gravado
#         no caminho final (6.1.5/6.1.10 — sem estado parcial valido)
#   JS-6  write-config: config completo e valido -> exit 0, arquivo gravado
#         com todos os campos
#   JS-7  write-config: status_fail == status_pass -> exit 1 (delega a
#         jira-config.sh validate), NADA gravado
#   JS-8  write-config: KEY=VALUE malformado -> exit 2, NADA gravado
#   JS-9  fixture createmeta (R8) + json-get extrai id/name/hierarchyLevel/
#         subtask conforme schema documentado (cobre 6.1.3 indiretamente:
#         a extracao que a skill usa para listar os tipos e confirmar)
#   JS-10 fixture transitions (R5) + json-get extrai transitions[].to.name,
#         e o resultado alimenta check-status-mapping (cobre 6.1.4)
#   JS-11 write-config bem-sucedido devolve eventos `auth_failed` do outbox
#         a `queued` (FASE 12 tarefa 12.6.1, FR-016 / data-model.md
#         OutboxEvent auth_failed->queued), delegando a
#         `jira-sync.sh requeue-auth-failed`
#   JS-12 write-config que FALHA (config invalido) NAO reenfileira nada —
#         o outbox permanece intocado (reenfileirar so faz sentido apos
#         reconfiguracao bem-sucedida)
#   JS-13 resolve-link-type: exatamente 1 tipo com inward E outward
#         contendo "block" (case-insensitive) -> imprime o ID, exit 0
#         (r02 FASE 18 tarefa 18.2.1/18.2.3)
#   JS-14 resolve-link-type: 0 candidatos -> exit 1, diagnostico
#         "unrepresentable reason=no_link_type" (18.2.1/18.2.3)
#   JS-15 resolve-link-type: 2+ candidatos ambiguos -> exit 1, diagnostico
#         "unrepresentable reason=ambiguous_link_type", NUNCA escolhe o
#         primeiro (18.2.1/18.2.3)
#   JS-16 resolve-link-type: comparacao e case-insensitive (inward/outward
#         em maiusculas tambem casam a raiz "block")
#   JS-17 resolve-link-type: candidato so com "block" no inward (outward
#         sem a raiz) NAO conta — exige as DUAS frases (research.md
#         Decision R2-6)
#   JS-18 resolve-link-type: nao aceita argumentos posicionais -> exit 2
#   JS-19 resolve-link-type: stdin vazio -> exit 1 reason=no_link_type

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-setup.sh"
JIRA_IO="$REPO_ROOT/plugins/cstk-jira/scripts/jira-io.sh"

# Fixture R8 (createmeta) — valores REAIS do roundtrip onda-011
# (contracts/jira-rest.md R8: cstk.atlassian.net projeto SCRUM).
_FIXTURE_CREATEMETA='{
  "issueTypes": [
    {"id": "10000", "name": "Epic", "hierarchyLevel": 1, "subtask": false},
    {"id": "10001", "name": "Story", "hierarchyLevel": 0, "subtask": false},
    {"id": "10002", "name": "Task", "hierarchyLevel": 0, "subtask": false},
    {"id": "10003", "name": "Subtask", "hierarchyLevel": -1, "subtask": true}
  ]
}'

# Fixture R5 (transitions) — nomes de status REAIS do roundtrip onda-011
# (contracts/jira-rest.md R5: GET /rest/api/3/issue/SCRUM-6/transitions).
_FIXTURE_TRANSITIONS='{
  "transitions": [
    {"id": "11", "name": "To Do", "to": {"id": "1", "name": "To Do"}, "isLooped": false},
    {"id": "21", "name": "In Progress", "to": {"id": "2", "name": "In Progress"}, "isLooped": false},
    {"id": "31", "name": "In Review", "to": {"id": "3", "name": "In Review"}, "isLooped": false},
    {"id": "41", "name": "Done", "to": {"id": "4", "name": "Done"}, "isLooped": false}
  ]
}'

scenario_check_status_mapping_fail_igual_pass_exit1_lista_status() {
  assert_exit 1 "$SCRIPT" check-status-mapping \
    "To Do" "In Progress" "Done" "Done" \
    "To Do" "In Progress" "In Review" "Done" || return 1
  assert_stderr_contains "status_fail e status_pass" || return 1
  assert_stderr_contains "To Do, In Progress, In Review, Done" || return 1
}

scenario_check_status_mapping_valor_fora_da_lista_exit1() {
  assert_exit 1 "$SCRIPT" check-status-mapping \
    "To Do" "In Progress" "Done" "Cancelado" \
    "To Do" "In Progress" "In Review" "Done" || return 1
  assert_stderr_contains "nao esta entre os status descobertos" || return 1
  assert_stderr_contains "To Do, In Progress, In Review, Done" || return 1
}

scenario_check_status_mapping_valido_exit0() {
  assert_exit 0 "$SCRIPT" check-status-mapping \
    "To Do" "In Progress" "Done" "In Review" \
    "To Do" "In Progress" "In Review" "Done" || return 1
}

scenario_check_status_mapping_uso_incorreto_exit2() {
  assert_exit 2 "$SCRIPT" check-status-mapping "To Do" "In Progress" || return 1
}

# ==== check-link-type (r02 FASE 18 tarefa 18.1.1/18.1.3) ====

scenario_check_link_type_id_presente_exit0() {
  assert_exit 0 "$SCRIPT" check-link-type 10000 10000 10001 10002 10003 || return 1
}

scenario_check_link_type_id_ausente_exit1_lista_candidatos() {
  assert_exit 1 "$SCRIPT" check-link-type 99999 10000 10001 10002 10003 || return 1
  assert_stderr_contains "nao esta entre os candidatos" || return 1
  assert_stderr_contains "10000, 10001, 10002, 10003" || return 1
}

scenario_check_link_type_uso_incorreto_exit2() {
  assert_exit 2 "$SCRIPT" check-link-type 10000 || return 1
}

scenario_write_config_campo_obrigatorio_ausente_exit1_nada_gravado() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 env CSTK_JIRA_CONFIG="./.claude/cstk-jira/config" "$SCRIPT" write-config \
    config_version=1 site_host=example.atlassian.net project_key=CSTK \
    issue_type_epic=1 issue_type_task=2 issue_type_subtask=3 \
    status_pending="To Do" status_in_progress="In Progress" \
    status_pass=Done status_fail=Failed sync_autonomous=on || return 1
  assert_stderr_contains "NADA foi gravado" || return 1
  [ ! -e "$TMPDIR_TEST/.claude/cstk-jira/config" ] \
    || { _fail "nada_gravado" "config final foi criado apesar da falha de validacao"; return 1; }
}

scenario_write_config_completo_valido_exit0_grava_todos_campos() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 env CSTK_JIRA_CONFIG="./.claude/cstk-jira/config" "$SCRIPT" write-config \
    config_version=1 site_host=example.atlassian.net project_key=CSTK board_id=42 \
    issue_type_epic=10000 issue_type_task=10002 issue_type_subtask=10003 \
    status_pending="To Do" status_in_progress="In Progress" \
    status_pass=Done status_fail="In Review" sync_autonomous=on || return 1
  [ -f "$TMPDIR_TEST/.claude/cstk-jira/config" ] \
    || { _fail "gravado" "config final nao foi criado"; return 1; }
  grep -q '^board_id=42$' "$TMPDIR_TEST/.claude/cstk-jira/config" \
    || { _fail "conteudo" "board_id ausente/incorreto no config gravado"; return 1; }
}

scenario_write_config_fail_igual_pass_exit1_nada_gravado() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 env CSTK_JIRA_CONFIG="./.claude/cstk-jira/config" "$SCRIPT" write-config \
    config_version=1 site_host=example.atlassian.net project_key=CSTK board_id=42 \
    issue_type_epic=10000 issue_type_task=10002 issue_type_subtask=10003 \
    status_pending="To Do" status_in_progress="In Progress" \
    status_pass=Done status_fail=Done sync_autonomous=on || return 1
  [ ! -e "$TMPDIR_TEST/.claude/cstk-jira/config" ] \
    || { _fail "nada_gravado" "config final foi criado com status_fail == status_pass"; return 1; }
}

scenario_write_config_kv_malformado_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 env CSTK_JIRA_CONFIG="./.claude/cstk-jira/config" "$SCRIPT" write-config \
    config_version=1 site_host_sem_igual || return 1
  [ ! -e "$TMPDIR_TEST/.claude/cstk-jira/config" ] \
    || { _fail "nada_gravado" "config final foi criado apesar de KEY=VALUE malformado"; return 1; }
}

scenario_fixture_createmeta_extrai_campos_do_schema_r8() {
  _out=$(printf '%s' "$_FIXTURE_CREATEMETA" \
    | "$JIRA_IO" json-get '.issueTypes[] | "\(.id)\t\(.name)\t\(.hierarchyLevel)\t\(.subtask)"')
  printf '%s\n' "$_out" | grep -q '^10000	Epic	1	false$' \
    || { _fail "epic" "linha de Epic nao extraida como esperado: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -q '^10003	Subtask	-1	true$' \
    || { _fail "subtask" "linha de Subtask nao extraida como esperado: $_out"; return 1; }
}

scenario_fixture_transitions_alimenta_check_status_mapping() {
  _statuses_raw=$(printf '%s' "$_FIXTURE_TRANSITIONS" \
    | "$JIRA_IO" json-get '.transitions[].to.name')
  # Split so por linha (NUNCA por espaco — nomes de status como "To Do" tem
  # espaco interno; IFS=newline preserva cada status como 1 argumento).
  _old_ifs=$IFS
  IFS='
'
  # shellcheck disable=SC2086 # split intencional por linha (IFS=newline)
  set -- $_statuses_raw
  IFS=$_old_ifs
  assert_exit 0 "$SCRIPT" check-status-mapping \
    "To Do" "In Progress" "Done" "In Review" "$@" || return 1
  assert_exit 1 "$SCRIPT" check-status-mapping \
    "To Do" "In Progress" "Done" "Done" "$@" || return 1
}

scenario_write_config_sucesso_reenfileira_auth_failed() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "./.claude/cstk-jira/runtime"
  cat > "./.claude/cstk-jira/runtime/outbox.tsv" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	1	auth_failed
EOF
  assert_exit 0 env CSTK_JIRA_CONFIG="./.claude/cstk-jira/config" "$SCRIPT" write-config \
    config_version=1 site_host=example.atlassian.net project_key=CSTK board_id=42 \
    issue_type_epic=10000 issue_type_task=10002 issue_type_subtask=10003 \
    status_pending="To Do" status_in_progress="In Progress" \
    status_pass=Done status_fail="In Review" sync_autonomous=on || return 1
  assert_stdout_contains "1 evento(s) auth_failed reenfileirado(s) para queued" || return 1
  awk -F '\t' '$1=="e1"' "./.claude/cstk-jira/runtime/outbox.tsv" | grep -q '	queued$' \
    || { _fail "write_config_requeues_auth_failed" "evento e1 continua auth_failed apos write-config bem-sucedido"; return 1; }
  return 0
}

scenario_write_config_falho_nao_reenfileira_auth_failed() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "./.claude/cstk-jira/runtime"
  cat > "./.claude/cstk-jira/runtime/outbox.tsv" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	1	auth_failed
EOF
  assert_exit 1 env CSTK_JIRA_CONFIG="./.claude/cstk-jira/config" "$SCRIPT" write-config \
    config_version=1 site_host=example.atlassian.net project_key=CSTK \
    issue_type_epic=1 issue_type_task=2 issue_type_subtask=3 \
    status_pending="To Do" status_in_progress="In Progress" \
    status_pass=Done status_fail=Failed sync_autonomous=on || return 1
  awk -F '\t' '$1=="e1"' "./.claude/cstk-jira/runtime/outbox.tsv" | grep -q '	auth_failed$' \
    || { _fail "write_config_failed_no_requeue" "evento e1 foi reenfileirado apesar de write-config ter falhado"; return 1; }
  return 0
}

# ==== resolve-link-type (r02 FASE 18 tarefa 18.2.1/18.2.3) ====

scenario_resolve_link_type_unico_candidato_exit0() {
  capture sh -c "printf '10000\tis blocked by\tblocks\n10001\tis cloned by\tclones\n' | \"$SCRIPT\" resolve-link-type"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "js13_exit" "esperado exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "10000" ] \
    || { _fail "js13_stdout" "esperado '10000', obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_resolve_link_type_zero_candidatos_no_link_type() {
  capture sh -c "printf '10001\tis cloned by\tclones\n10002\tis duplicated by\tduplicates\n' | \"$SCRIPT\" resolve-link-type"
  [ "$_CAPTURED_EXIT" = "1" ] || { _fail "js14_exit" "esperado exit 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "unrepresentable reason=no_link_type" || return 1
}

scenario_resolve_link_type_ambiguo_nao_escolhe_primeiro() {
  capture sh -c "printf '10000\tis blocked by\tblocks\n10005\tBlockage\tblocking\n' | \"$SCRIPT\" resolve-link-type"
  [ "$_CAPTURED_EXIT" = "1" ] || { _fail "js15_exit" "esperado exit 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "unrepresentable reason=ambiguous_link_type" || return 1
  case "$_CAPTURED_STDOUT" in
    10000|10005) _fail "js15_no_arbitrary" "resolve-link-type imprimiu um ID mesmo com ambiguidade: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_resolve_link_type_case_insensitive() {
  capture sh -c "printf '10000\tIS BLOCKED BY\tBLOCKS\n' | \"$SCRIPT\" resolve-link-type"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "js16_exit" "esperado exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "10000" ] \
    || { _fail "js16_stdout" "esperado '10000', obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_resolve_link_type_exige_inward_e_outward() {
  # inward casa "block", outward NAO -> nao conta como candidato (AND, nao OR)
  capture sh -c "printf '10000\tis blocked by\trelates to\n' | \"$SCRIPT\" resolve-link-type"
  [ "$_CAPTURED_EXIT" = "1" ] || { _fail "js17_exit" "esperado exit 1 (outward sem raiz block nao deveria casar), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "unrepresentable reason=no_link_type" || return 1
}

scenario_resolve_link_type_argumento_posicional_exit2() {
  assert_exit 2 "$SCRIPT" resolve-link-type 10000 || return 1
}

scenario_resolve_link_type_stdin_vazio_no_link_type() {
  capture sh -c "printf '' | \"$SCRIPT\" resolve-link-type"
  [ "$_CAPTURED_EXIT" = "1" ] || { _fail "js19_exit" "esperado exit 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "unrepresentable reason=no_link_type" || return 1
}

run_all_scenarios
