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
#   HS-16 resumo pos-drain (task 13.4.1): ConflictRecord PENDENTE
#         originado em reconcile/convert (sem evento outbox `conflict`
#         correspondente) APARECE no resumo (conflict=1) — antes desta
#         tarefa a contagem vinha so do outbox e nunca via esse conflito
#   HS-17 resumo pos-drain (task 13.4.1): ConflictRecord JA RESOLVIDO
#         (resolution != pending) NAO aparece — mesmo com um evento outbox
#         `conflict` remanescente, o resumo nao acusa conflito pendente
#   HS-18 r02 FASE 20 tarefa 20.1.2/20.1.3: worktree SEM ProjectConfig
#         local mas com config na worktree principal (`sync_autonomous=on`)
#         -> hook resolve via `jira-config.sh resolve-path` e enfileira
#         normalmente; `runtime/` (outbox) e criado no cwd do WORKTREE,
#         NUNCA na principal (fila/lock por worktree, FR-023)

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

# _config_on_full_milestone_off: ProjectConfig COMPLETO e valido
# (`jira-config.sh validate` exit 0 — os campos minimos de `_config_on`
# NAO bastam: `_js_cmd_milestone_resolve` chama `validate` ANTES de
# checar `milestone_mode`, entao config invalido faz `status` cair no
# fallback `milestone=unresolved`, mascarando `milestone_mode=off`) +
# `milestone_mode=off` — usado pelos cenarios de resumo "saudavel" (task
# 21.3.1/21.3.2) para que `milestone=off` seja um caminho feliz de
# verdade (nao dependa do config estar incompleto).
_config_on_full_milestone_off() {
  mkdir -p "$1/.claude/cstk-jira"
  cat > "$1/.claude/cstk-jira/config" <<'EOF'
config_version=1
site_host=cstk-test.atlassian.net
project_key=DEMO
board_id=1
issue_type_epic=10001
issue_type_task=10004
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
milestone_mode=off
EOF
}

_feature_lock() {
  mkdir -p "$1/.claude/feature-00c-state/$2/.lock"
}

# _hs_setup_worktree: repo git minimo em $TMPDIR_TEST/main (commit inicial
# SEM ProjectConfig) + worktree linkado em $TMPDIR_TEST/wt (r02 FASE 20
# tarefa 20.1.2/20.1.3 — mesmo racional de
# test_jira-config.sh::_jc_setup_worktree / test_parallel-launch.sh::
# _pl_git_repo).
_hs_setup_worktree() {
  mkdir -p "$TMPDIR_TEST/main"
  (
    cd "$TMPDIR_TEST/main" || exit 1
    git init -q .
    git config user.email "test@test.local"
    git config user.name "cstk test"
    printf 'x\n' > README.md
    git add README.md
    git commit -q -m init
    git worktree add -q -b hs-test-branch "$TMPDIR_TEST/wt" HEAD
  )
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

_conflicts_file() {
  printf '%s\n' "$1/.claude/cstk-jira/runtime/conflicts.tsv"
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
  # task 21.3.1: config COMPLETO + milestone_mode=off — com o resumo agora
  # tambem espelhando milestone=/links_unrepresentable=/links_stale=
  # (achado 21.3), o config MINIMO de `_config_on` faria `jira-config.sh
  # validate` falhar dentro de `milestone resolve` e `status` cair no
  # fallback `milestone=unresolved`, que NAO e mais um caminho feliz —
  # ruido falso que nada tem a ver com o outbox estar saudavel.
  _config_on_full_milestone_off "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  # outbox so tem o evento recem-enfileirado (queued=1), sem
  # conflict/auth_failed/deferred, milestone=off e links zerados (sem
  # jira-links.tsv) — nenhuma linha "resumo pos-drain" deve aparecer
  # (evita ruido no caminho feliz).
  grep -q 'resumo pos-drain' "$(_hooklog "$TMPDIR_TEST")" \
    && { _fail "resumo_noise" "resumo pos-drain apareceu com outbox saudavel: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

# HS-16 (task 13.4.1): ConflictRecord pendente originado em reconcile/
# convert nunca gera evento outbox `conflict` correspondente — o resumo
# precisa contar `runtime/conflicts.tsv` diretamente (via `pending=` de
# `jira-sync.sh status`), nao a contagem `conflict=` do outbox.
scenario_resumo_conflito_reconcile_pendente_aparece() {
  _config_on "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira/runtime"
  cat > "$(_conflicts_file "$TMPDIR_TEST")" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	9.1	DEMO-9	manual_edit	pending
EOF
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  grep -q 'resumo pos-drain (demo):.*conflict=1' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "resumo_reconcile_conflict_missing" "conflito de reconcile pendente nao apareceu no resumo: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

# HS-17 (task 13.4.1): ConflictRecord ja fechado (`resolve`, qualquer
# --choice) nao pode reaparecer no resumo so porque um evento outbox
# `conflict` remanescente ainda existe (cenario que a contagem antiga, por
# evento outbox, acusaria para sempre).
scenario_resumo_conflito_resolvido_nao_aparece() {
  # task 21.3.1: config completo + milestone_mode=off (mesmo motivo de
  # scenario_resumo_pos_drain_omitido_quando_saudavel — sem isto,
  # milestone=unresolved do config minimo faria o resumo aparecer por um
  # motivo nao relacionado ao conflito ja resolvido que este teste cobre).
  _config_on_full_milestone_off "$TMPDIR_TEST"
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira/runtime"
  cat > "$(_outbox "$TMPDIR_TEST")" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	conflict
EOF
  cat > "$(_conflicts_file "$TMPDIR_TEST")" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	keep_jira
EOF
  _J=$(_json_task "$TMPDIR_TEST" 5.2 fail)
  assert_exit 0 _run_hook "$_J" task || return 1
  grep -q 'resumo pos-drain' "$(_hooklog "$TMPDIR_TEST")" \
    && { _fail "resumo_resolved_conflict_noise" "conflito ja resolvido ainda apareceu no resumo: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

# HS-20 (task 21.3.1/21.3.2, achado 21.3): resumo pos-drain agora tambem
# espelha `milestone=`/`links_unrepresentable=` — marco `blocked:1.0.0`
# (`milestone_release=1.0.0` + `jira-milestones.tsv` com `state=blocked`,
# resolucao 100% local, sem CHANGELOG.md/round) e 2 arestas
# `unrepresentable` em `jira-links.tsv` aparecem no resumo mesmo com
# outbox/conflicts totalmente saudaveis — o gate do resumo agora considera
# estes 2 sinais novos, nao so deferred/conflict/auth_failed (r01/13.4.1).
# Mutation (parar de parsear/anexar os campos novos) MUST falhar este
# teste.
scenario_resumo_milestone_blocked_e_links_unrepresentable_aparecem() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/config" <<'EOF'
config_version=1
site_host=cstk-test.atlassian.net
project_key=DEMO
board_id=1
issue_type_epic=10001
issue_type_task=10004
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
milestone_release=1.0.0
EOF
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n1.0.0\trelease\t30001\tDEMO\tblocked\n' \
    > "$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv"
  printf 'from_phase\tto_phase\tblocker_key\tblocked_key\tlink_type_id\tstate\treason\n1\t2\t\t\t\tunrepresentable\tno_link_type\n2\t3\t\t\t\tunrepresentable\tno_link_type\n' \
    > "$TMPDIR_TEST/docs/specs/demo/jira-links.tsv"
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  grep -q 'resumo pos-drain (demo):.*milestone=blocked:1.0.0' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "hs20_milestone_missing" "milestone=blocked:1.0.0 nao apareceu no resumo: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  grep -q 'resumo pos-drain (demo):.*links_unrepresentable=2' "$(_hooklog "$TMPDIR_TEST")" \
    || { _fail "hs20_links_missing" "links_unrepresentable=2 nao apareceu no resumo: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

# HS-21 (task 21.3.2, caminho feliz): marco RESOLVIDO (milestone=1.0.0,
# nao blocked) + jira-links.tsv sem nenhuma linha unrepresentable/stale +
# outbox/conflicts saudaveis => resumo byte-identico ao r01/13.4.1
# (nenhuma linha "resumo pos-drain"). Marco resolvido (nao unresolved/
# blocked) e links=0 sao os 2 novos campos no seu proprio caminho feliz —
# nunca disparam o resumo sozinhos.
scenario_resumo_milestone_resolvido_e_links_zerados_nao_aparece() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/config" <<'EOF'
config_version=1
site_host=cstk-test.atlassian.net
project_key=DEMO
board_id=1
issue_type_epic=10001
issue_type_task=10004
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
milestone_release=1.0.0
EOF
  _feature_lock "$TMPDIR_TEST" demo
  _jira_map "$TMPDIR_TEST" demo
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n1.0.0\trelease\t30001\tDEMO\tcurrent\n' \
    > "$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv"
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  grep -q 'resumo pos-drain' "$(_hooklog "$TMPDIR_TEST")" \
    && { _fail "hs21_noise" "resumo pos-drain apareceu com marco resolvido e links zerados: $(cat "$(_hooklog "$TMPDIR_TEST")" 2>/dev/null)"; return 1; }
  return 0
}

# _install_state_rw_stub_field FIELD_DOTTED VALUE -> stub de `state-rw.sh`
# (runtime agente-00c-runtime) que so responde ao caminho pontuado EXATO
# `.FIELD_DOTTED` — duplicado de tests/cstk/test_jira-sync.sh (SY-67)
# porque harness.sh nao compartilha helpers entre arquivos de teste. Um
# stub tolerante a qualquer --field mascararia a regressao 13.1.1 (o hook
# pedindo o campo top-level errado continuaria "funcionando" por acidente).
_install_state_rw_stub_field() {
  _field="$1"
  _val="$2"
  _scripts_dir="$TMPDIR_TEST/stubroot-hook/skills/agente-00c-runtime/scripts"
  mkdir -p "$TMPDIR_TEST/stubroot-hook/lib" "$_scripts_dir"
  cat > "$_scripts_dir/state-rw.sh" <<EOF
#!/bin/sh
[ "\$1" = "get" ] || exit 2
shift
_dir=""
_f=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --state-dir) _dir=\$2; shift 2 ;;
    --field) _f=\$2; shift 2 ;;
    *) shift ;;
  esac
done
[ -f "\$_dir/state.db" ] || exit 1
[ "\$_f" = ".$_field" ] || exit 1
printf '%s\n' "$_val"
EOF
  chmod +x "$_scripts_dir/state-rw.sh"
  export CSTK_LIB="$TMPDIR_TEST/stubroot-hook/lib"
}

# HS-18 (task 14.1.1, regressao da 13.1.1): agente-00c sob backend state.db,
# em worktree cujo basename() DIFERE do canonical_project real. Antes da
# 14.1.1, `_pjs_resolve_canonical_project` pedia
# `resolve-state-field --field canonical_project` (campo top-level, sempre
# null sob state.db) e caia SEMPRE no fallback basename(cwd) — que nao tem
# `jira-map.tsv`, entao o sync autonomo virava no-op silencioso. Com o
# campo corrigido (`execution.canonical_project`) e um stub que so responde
# a esse caminho pontuado exato, o feature resolvido e o CANONICO (tem
# jira-map.tsv) e o outbox e enfileirado normalmente.
scenario_state_db_agente00c_canonical_project_diferente_do_basename_nao_vira_noop() {
  _config_on "$TMPDIR_TEST"
  mkdir -p "$TMPDIR_TEST/.claude/agente-00c-state/.lock"
  : > "$TMPDIR_TEST/.claude/agente-00c-state/state.db"
  _install_state_rw_stub_field "execution.canonical_project" "cstk-jira-canon"
  # basename($TMPDIR_TEST) e o path aleatorio do mktemp — nunca
  # "cstk-jira-canon"; jira-map.tsv so existe sob o nome canonico.
  _jira_map "$TMPDIR_TEST" "cstk-jira-canon"
  _J=$(_json_task "$TMPDIR_TEST" 5.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -f "$(_outbox "$TMPDIR_TEST")" ] \
    || { _fail "hs18_outbox_missing" "outbox nao foi criado — hook provavelmente caiu no basename (regressao 13.1.1) e nao achou jira-map.tsv"; return 1; }
  _line=$(awk -F '\t' 'NR==2' "$(_outbox "$TMPDIR_TEST")")
  printf '%s' "$_line" | grep -q '	cstk-jira-canon	5.1	pass	hook-record-task	0	queued$' \
    || { _fail "hs18_outbox_line" "linha gravada incorreta (esperado feature=cstk-jira-canon): $_line"; return 1; }
  return 0
}

scenario_worktree_sem_config_local_usa_principal_runtime_fica_local() {
  _hs_setup_worktree
  mkdir -p "$TMPDIR_TEST/main/.claude/cstk-jira"
  printf 'config_version=1\nsync_autonomous=on\n' \
    > "$TMPDIR_TEST/main/.claude/cstk-jira/config"
  _feature_lock "$TMPDIR_TEST/wt" demo
  _jira_map "$TMPDIR_TEST/wt" demo
  _J=$(_json_task "$TMPDIR_TEST/wt" 1.1 pass)
  assert_exit 0 _run_hook "$_J" task || return 1
  [ -f "$(_outbox "$TMPDIR_TEST/wt")" ] \
    || { _fail "hs19_runtime_local_missing" "outbox nao foi criado no worktree — config da principal deveria ter sido resolvido e o sync deveria ter prosseguido"; return 1; }
  [ -e "$TMPDIR_TEST/main/.claude/cstk-jira/runtime" ] \
    && { _fail "hs19_runtime_leak_principal" "runtime vazou para a worktree principal (deveria ficar sempre no cwd)"; return 1; }
  return 0
}

run_all_scenarios
