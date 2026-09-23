#!/bin/sh
# test_wave-summary.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/wave-summary.sh.
#
# Feature: wave-close-summary
# Ref: docs/specs/wave-close-summary/quickstart.md (Scenarios 1-8)
#      docs/specs/wave-close-summary/contracts/wave-summary-cli.md
#      docs/specs/wave-close-summary/data-model.md
#      docs/specs/wave-close-summary/tasks.md FASE 5
#
# Cobertura:
#   Dispatch: sem args / subcomando desconhecido / -h/--help -> exit 2
#   emit — uso invalido: sem --state-dir, --wave malformado, flag desconhecida
#   Scenario 1: onda normal (Markdown + JSON), repetido sob backend SQLite (S)
#   Scenario 2: threshold_proxy_atingido (sem ATENCAO) vs bloqueio_humano (ATENCAO)
#   Scenario 3: nao medido (otel_usage ausente) vs zero medido (0 tokens/custo)
#   Scenario 4: tool_calls=0 com/sem contador ativo (tick-mode manual/hook)
#   Scenario 5: nenhum texto livre de decisoes/bloqueios vaza; next_instruction
#     saneada (ESC removido, segredo sintetico filtrado)
#   Scenario 6: primeira onda sem decisoes; tarefas aplicavel vs nao aplicavel
#   Scenario 7: falhas best-effort (state-dir ausente, JSON corrompido, onda
#     inexistente, jq fora do PATH via shim com allowlist)
#   Scenario 8: determinismo (stdout byte-identico), read-only (hash/arquivos
#     inalterados), paridade entre layout agente-00c-state e feature-00c-state
#
# Convencao de exit code de scenario (interpretada pelo runner):
#   0 PASS, 1 FAIL, 2 ERROR (pre-req faltando — jq ausente, mktemp falhou)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/wave-summary.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
HASH_LIB="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_hash.sh"

# Sourceado para 9.2.1 (hash do estado antes/depois do emit — nao executavel).
# shellcheck disable=SC1090
. "$HASH_LIB"

# ---------- helpers locais ----------

_wsm_have_jq() {
  command -v jq >/dev/null 2>&1
}

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

# Fixture base minima: onda-001 fechada, sem decisoes/bloqueios/tasks.
# Scenarios sobrescrevem/estendem conforme necessario.
_wsm_base_state() {
  cat <<'JSON'
{
  "schema_version": 1,
  "current_stage": "execute-task",
  "next_instruction": "Continuar etapa execute-task.",
  "execution": {
    "status": "em_andamento",
    "target_project_path": "/tmp/proj-wsm"
  },
  "waves": [
    {
      "id": "onda-001",
      "termination_reason": "etapa_concluida_avancando",
      "executed_stages": ["specify"],
      "tool_calls": 5,
      "wallclock_seconds": 120,
      "otel_usage": null
    }
  ],
  "decisions": [],
  "human_blocks": [],
  "tasks": []
}
JSON
}

# _wsm_write_fixture_scenario1 -> onda-002 fechada com 3 decisoes propria +
# 1 de onda-001, otel_usage preenchido, tool_calls=18.
_wsm_write_fixture_scenario1() {
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": 1,
  "current_stage": "execute-task",
  "next_instruction": "Continuar etapa execute-task.",
  "execution": {
    "status": "em_andamento",
    "target_project_path": "/tmp/proj-wsm"
  },
  "waves": [
    {
      "id": "onda-001",
      "termination_reason": "etapa_concluida_avancando",
      "executed_stages": ["specify"],
      "tool_calls": 5,
      "wallclock_seconds": 60,
      "otel_usage": null
    },
    {
      "id": "onda-002",
      "termination_reason": "etapa_concluida_avancando",
      "executed_stages": ["clarify", "plan"],
      "tool_calls": 18,
      "wallclock_seconds": 295,
      "otel_usage": {"total_tokens": 12345, "total_cost_usd": 0.42}
    }
  ],
  "decisions": [
    {"wave_id": "onda-001", "context": "x"},
    {"wave_id": "onda-002", "context": "x"},
    {"wave_id": "onda-002", "context": "x"},
    {"wave_id": "onda-002", "context": "x"}
  ],
  "human_blocks": [],
  "tasks": []
}
JSON
}

# ==== Dispatch ====

scenario_sem_args_exit2() {
  capture sh "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "deveria ser vazio"; return 1; }
}

scenario_subcomando_desconhecido_exit2() {
  capture sh "$SCRIPT" bogus
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
}

scenario_help_exit2() {
  capture sh "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1
  capture sh "$SCRIPT" -h
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit -h" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== emit: uso invalido ====

scenario_emit_sem_state_dir_exit2() {
  capture sh "$SCRIPT" emit
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--state-dir obrigatorio" || return 1
}

scenario_emit_wave_malformado_exit2() {
  mktemp_test || return 2
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --wave "nao-e-onda"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "wave invalido" || return 1
}

scenario_emit_flag_desconhecida_exit2() {
  mktemp_test || return 2
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --bogus
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== Scenario 1: onda normal ====

scenario_1_onda_normal_markdown() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wsm_write_fixture_scenario1
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "deveria ser vazio, obtido: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "### Resumo da onda onda-002" || return 1
  assert_stdout_contains "etapa concluida, avancando" || return 1
  assert_stdout_contains "Decisoes registradas na onda: 3" || return 1
}

scenario_1_onda_normal_json() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wsm_write_fixture_scenario1
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e '.' >/dev/null \
    || { _fail "json invalido" "$_CAPTURED_STDOUT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" \
    | jq -e '.wave_id == "onda-002" and .decisions_count == 3 and .termination_reason == "etapa_concluida_avancando"' >/dev/null \
    || { _fail "campos" "valores inesperados: $_CAPTURED_STDOUT"; return 1; }
}

scenario_1_sqlite_onda_normal() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  _sqlite3_adequate || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  mktemp_test || return 2
  _sd="$TMPDIR_TEST/state-sqlite"
  _home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  env HOME="$_home" "$RW" init --state-dir "$_sd" \
    --execucao-id "x-wsm-sqlite" --projeto-alvo-path "/tmp/proj-wsm" \
    --descricao "POC wave-summary sqlite" >/dev/null 2>&1 \
    || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "fixture sqlite" "state.db ausente"; return 1; }

  # Fixture construida via runtime canonico (state-ondas.sh + state-decisions.sh)
  # em vez de injecao manual de JSON: o schema sqlite tem CHECK constraints
  # (context/rationale >= 20 chars, options_considered >= 1 item, etc.) que o
  # caminho real ja satisfaz por construcao — evita reproduzir o DDL aqui.
  _so="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh"
  _sdt="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh"

  "$_so" start --state-dir "$_sd" >/dev/null 2>&1 \
    || { _fail "fixture sqlite" "onda-001 start falhou"; return 1; }
  "$_so" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando >/dev/null 2>&1 \
    || { _fail "fixture sqlite" "onda-001 end falhou"; return 1; }

  "$_so" start --state-dir "$_sd" >/dev/null 2>&1 \
    || { _fail "fixture sqlite" "onda-002 start falhou"; return 1; }
  _i=1
  while [ "$_i" -le 3 ]; do
    "$_sdt" register --state-dir "$_sd" --agente "test-fixture" --etapa "clarify" \
      --contexto "decisao sintetica de fixture onda-002 numero $_i" \
      --opcoes '["a","b"]' --escolha "a" \
      --justificativa "justificativa sintetica de fixture onda-002 numero $_i" \
      --score 2 >/dev/null 2>&1 \
      || { _fail "fixture sqlite" "register decisao $_i falhou"; return 1; }
    _i=$((_i + 1))
  done
  "$_so" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando >/dev/null 2>&1 \
    || { _fail "fixture sqlite" "onda-002 end falhou"; return 1; }

  capture sh "$SCRIPT" emit --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "### Resumo da onda onda-002" || return 1
  assert_stdout_contains "Decisoes registradas na onda: 3" || return 1
  # Anti-mirror: leitura nao materializa state.json dentro do state-dir sqlite.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "emit criou state.json dentro do state-dir sqlite"
    return 1
  fi

  # 9.1.1 (converge FASE 9, ref 5.2.2): a saida do emit sobre state.db deve
  # ser IDENTICA a saida do emit sobre o MESMO estado materializado em
  # state.json (outro state-dir) — paridade real entre backends, nao so
  # fixtures equivalentes escritas a mao duas vezes.
  _sql_out="$_CAPTURED_STDOUT"
  _sd_json="$TMPDIR_TEST/state-sqlite-materialized"
  mkdir -p "$_sd_json" || { _fail "9.1.1 setup" "mkdir materializado falhou"; return 1; }
  "$RW" read --state-dir "$_sd" > "$_sd_json/state.json" 2>/dev/null \
    || { _fail "9.1.1 setup" "state-rw.sh read --state-dir $_sd falhou"; return 1; }
  [ -s "$_sd_json/state.json" ] \
    || { _fail "9.1.1 setup" "state.json materializado vazio"; return 1; }
  capture sh "$SCRIPT" emit --state-dir "$_sd_json"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "9.1.1 emit json materializado" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  [ "$_sql_out" = "$_CAPTURED_STDOUT" ] \
    || { _fail "9.1.1 paridade sqlite-vs-json" "saida do backend sqlite diverge da saida do backend json materializado"; return 1; }
}

# ==== Scenario 2: limite operacional vs bloqueio humano ====

scenario_2_threshold_sem_atencao() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "current_stage": "plan",
  "next_instruction": null,
  "execution": {"status": "em_andamento", "target_project_path": "/tmp/proj-wsm"},
  "waves": [{"id": "onda-001", "termination_reason": "threshold_proxy_atingido", "executed_stages": [], "tool_calls": 3, "wallclock_seconds": 30, "otel_usage": null}],
  "decisions": [], "human_blocks": [], "tasks": []
}
JSON
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "pausa por limite operacional" || return 1
  assert_stdout_not_contains "ATENCAO" || return 1
}

scenario_2_bloqueio_humano_com_atencao() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "current_stage": "clarify",
  "next_instruction": null,
  "execution": {"status": "aguardando_humano", "target_project_path": "/tmp/proj-wsm"},
  "waves": [{"id": "onda-001", "termination_reason": "bloqueio_humano", "executed_stages": [], "tool_calls": 3, "wallclock_seconds": 30, "otel_usage": null}],
  "decisions": [],
  "human_blocks": [
    {"id": "block-001", "status": "aguardando"},
    {"id": "block-002", "status": "respondido"}
  ],
  "tasks": []
}
JSON
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "bloqueio humano pendente" || return 1
  assert_stdout_contains "[ATENCAO: requer resposta do operador]" || return 1
  assert_stdout_contains "Bloqueios pendentes: 1 (block-001)" || return 1
}

# ==== Scenario 3: nao medido vs zero medido ====

scenario_3_otel_ausente_nao_medido() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wsm_base_state > "$TMPDIR_TEST/state.json"
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Consumo (OTel): nao medido" || return 1
  assert_stdout_not_contains "0 tokens" || return 1

  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --json
  printf '%s' "$_CAPTURED_STDOUT" | jq -e '.cost.total_tokens == null and .cost.measured == false' >/dev/null \
    || { _fail "json" "cost deveria ser null/false: $_CAPTURED_STDOUT"; return 1; }
}

scenario_3_otel_zero_medido() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "current_stage": "execute-task",
  "next_instruction": null,
  "execution": {"status": "em_andamento", "target_project_path": "/tmp/proj-wsm"},
  "waves": [{"id": "onda-001", "termination_reason": "etapa_concluida_avancando", "executed_stages": [], "tool_calls": 1, "wallclock_seconds": 10, "otel_usage": {"total_tokens": 0, "total_cost_usd": 0}}],
  "decisions": [], "human_blocks": [], "tasks": []
}
JSON
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0 tokens" || return 1

  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --json
  printf '%s' "$_CAPTURED_STDOUT" | jq -e '.cost.total_tokens == 0 and .cost.measured == true' >/dev/null \
    || { _fail "json" "cost deveria ser 0/true: $_CAPTURED_STDOUT"; return 1; }
}

# ==== Scenario 4: tool_calls=0 com/sem contador ativo ====

_wsm_mkproj_no_plugin_env() {
  # Ecoa "HOME=<path>" "CLAUDE_PLUGIN_ROOT=" prontos p/ env(1) — isola de
  # qualquer plugin/instalacao real da maquina que roda a suite.
  _home="$TMPDIR_TEST/.home-sem-plugin"
  mkdir -p "$_home"
  printf '%s' "$_home"
}

scenario_4_tool_calls_zero_sem_hook_nao_medido() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _pap="$TMPDIR_TEST/proj-sem-hook"
  mkdir -p "$_pap/.claude"
  cat > "$TMPDIR_TEST/state.json" <<JSON
{
  "current_stage": "execute-task",
  "next_instruction": null,
  "execution": {"status": "em_andamento", "target_project_path": "$_pap"},
  "waves": [{"id": "onda-001", "termination_reason": "etapa_concluida_avancando", "executed_stages": [], "tool_calls": 0, "wallclock_seconds": 10, "otel_usage": null}],
  "decisions": [], "human_blocks": [], "tasks": []
}
JSON
  _home=$(_wsm_mkproj_no_plugin_env)
  capture env HOME="$_home" CLAUDE_PLUGIN_ROOT='' sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "Chamadas de ferramenta: nao medido" || return 1
}

scenario_4_tool_calls_zero_com_hook_ativo() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _pap="$TMPDIR_TEST/proj-com-hook"
  mkdir -p "$_pap/.claude/hooks"
  printf '#!/bin/sh\nexit 0\n' > "$_pap/.claude/hooks/posttooluse-tool-call-tick.sh"
  chmod +x "$_pap/.claude/hooks/posttooluse-tool-call-tick.sh"
  printf '{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/posttooluse-tool-call-tick.sh"}]}]}}' \
    > "$_pap/.claude/settings.json"
  cat > "$TMPDIR_TEST/state.json" <<JSON
{
  "current_stage": "execute-task",
  "next_instruction": null,
  "execution": {"status": "em_andamento", "target_project_path": "$_pap"},
  "waves": [{"id": "onda-001", "termination_reason": "etapa_concluida_avancando", "executed_stages": [], "tool_calls": 0, "wallclock_seconds": 10, "otel_usage": null}],
  "decisions": [], "human_blocks": [], "tasks": []
}
JSON
  _home=$(_wsm_mkproj_no_plugin_env)
  capture env HOME="$_home" CLAUDE_PLUGIN_ROOT='' sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "Chamadas de ferramenta: 0" || return 1
}

# ==== Scenario 5: nenhum texto livre vaza ====

scenario_5_texto_livre_nao_vaza() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "current_stage": "clarify",
  "next_instruction": "Segredo sintetico Bearer sk-CANARY-SECRET-TOKEN-0001 apos \u001b[31m escape",
  "execution": {"status": "aguardando_humano", "target_project_path": "/tmp/proj-wsm"},
  "waves": [{"id": "onda-001", "termination_reason": "bloqueio_humano", "executed_stages": [], "tool_calls": 1, "wallclock_seconds": 5, "otel_usage": null}],
  "decisions": [
    {"wave_id": "onda-001", "context": "CANARY-DEC-CTX segredo Bearer sk-CANARY-SECRET-TOKEN-0001", "rationale": "CANARY-DEC-RAT"}
  ],
  "human_blocks": [
    {"id": "block-001", "status": "aguardando", "question": "CANARY-BLK-Q segredo Bearer sk-CANARY-SECRET-TOKEN-0001"}
  ],
  "tasks": []
}
JSON
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_not_contains "CANARY-DEC-CTX" || return 1
  assert_stdout_not_contains "CANARY-DEC-RAT" || return 1
  assert_stdout_not_contains "CANARY-BLK-Q" || return 1
  assert_stdout_not_contains "sk-CANARY-SECRET-TOKEN-0001" || return 1
  # ESC (0x1b) nunca deve aparecer literal na saida.
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "$(printf '\033')"; then
    _fail "ESC vazou" "$_CAPTURED_STDOUT"
    return 1
  fi

  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --json
  assert_stdout_not_contains "CANARY-DEC-CTX" || return 1
  assert_stdout_not_contains "CANARY-DEC-RAT" || return 1
  assert_stdout_not_contains "CANARY-BLK-Q" || return 1
  assert_stdout_not_contains "sk-CANARY-SECRET-TOKEN-0001" || return 1
}

# ==== Scenario 6: primeira onda, zero decisoes, tarefas ====

scenario_6_zero_decisoes_tarefas_aplicavel() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "current_stage": "converge",
  "next_instruction": null,
  "execution": {"status": "em_andamento", "target_project_path": "/tmp/proj-wsm"},
  "waves": [{"id": "onda-001", "termination_reason": "etapa_concluida_avancando", "executed_stages": ["execute-task"], "tool_calls": 2, "wallclock_seconds": 15, "otel_usage": null}],
  "decisions": [],
  "human_blocks": [],
  "tasks": [
    {"wave_id": "onda-001", "outcome": "pass"},
    {"wave_id": "onda-001", "outcome": "pass"},
    {"wave_id": "onda-001", "outcome": "fail"},
    {"wave_id": "onda-000", "outcome": "pass"}
  ]
}
JSON
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "Decisoes registradas na onda: 0" || return 1
  assert_stdout_contains "Tarefas: 2 concluidas, 1 falharam" || return 1
}

scenario_6_sem_execute_task_tarefas_nao_aplicavel() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "current_stage": "plan",
  "next_instruction": null,
  "execution": {"status": "em_andamento", "target_project_path": "/tmp/proj-wsm"},
  "waves": [{"id": "onda-001", "termination_reason": "etapa_concluida_avancando", "executed_stages": ["plan"], "tool_calls": 2, "wallclock_seconds": 15, "otel_usage": null}],
  "decisions": [], "human_blocks": [], "tasks": []
}
JSON
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Tarefas: nao aplicavel" || return 1
}

# ==== Scenario 7: falhas best-effort ====

scenario_7_state_dir_inexistente_exit1() {
  mktemp_test || return 2
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "deveria ser vazio"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -c .)
  [ "$_n" = 1 ] || { _fail "stderr" "esperada 1 linha, obtidas $_n: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "wave-summary:" || return 1
}

scenario_7_json_corrompido_exit1() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  printf '{invalido' > "$TMPDIR_TEST/state.json"
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "deveria ser vazio"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -c .)
  [ "$_n" = 1 ] || { _fail "stderr" "esperada 1 linha, obtidas $_n"; return 1; }
}

scenario_7_waves_vazio_exit3() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  printf '{"waves": []}' > "$TMPDIR_TEST/state.json"
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "deveria ser vazio"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -c .)
  [ "$_n" = 1 ] || { _fail "stderr" "esperada 1 linha, obtidas $_n"; return 1; }
}

scenario_7_wave_inexistente_exit3() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wsm_base_state > "$TMPDIR_TEST/state.json"
  capture sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" --wave onda-999
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -c .)
  [ "$_n" = 1 ] || { _fail "stderr" "esperada 1 linha, obtidas $_n"; return 1; }
}

scenario_7_jq_fora_do_path_exit1() {
  mktemp_test || return 2
  _wsm_base_state > "$TMPDIR_TEST/state.json"
  _shim="$TMPDIR_TEST/shimbin-nojq"
  mkdir -p "$_shim"
  for _cmd in sh grep printf find sort chmod mkdir cat rm ls tr wc cp mktemp basename dirname cut head sed; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  capture env PATH="$_shim" sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -c .)
  [ "$_n" = 1 ] || { _fail "stderr" "esperada 1 linha, obtidas $_n"; return 1; }
  assert_stderr_contains "jq nao encontrado" || return 1
}

# ==== Scenario 8: determinismo, read-only, paridade de modos ====

scenario_8_determinismo_stdout_identico() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wsm_write_fixture_scenario1
  _a=$(sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST")
  _b=$(sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST")
  [ "$_a" = "$_b" ] || { _fail "determinismo" "saidas divergem entre 2 execucoes"; return 1; }
}

scenario_8_read_only_sem_arquivo_novo() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wsm_write_fixture_scenario1
  _before=$(find "$TMPDIR_TEST" -maxdepth 1 -type f | sort)
  # 9.2.1 (converge FASE 9, ref 5.5.2, I-4): hash do proprio arquivo de estado
  # antes do emit — uma escrita in-place preservaria o nome/lista de arquivos
  # do state-dir (find acima nao detectaria), mas mudaria o conteudo/hash.
  _hash_before=$(_hash_sha256_file "$TMPDIR_TEST/state.json") \
    || { _fail "9.2.1 setup" "hash antes falhou"; return 1; }
  sh "$SCRIPT" emit --state-dir "$TMPDIR_TEST" >/dev/null
  _after=$(find "$TMPDIR_TEST" -maxdepth 1 -type f | sort)
  [ "$_before" = "$_after" ] || { _fail "read-only" "arquivo novo criado no state-dir"; return 1; }
  _hash_after=$(_hash_sha256_file "$TMPDIR_TEST/state.json") \
    || { _fail "9.2.1 setup" "hash depois falhou"; return 1; }
  [ "$_hash_before" = "$_hash_after" ] \
    || { _fail "9.2.1 read-only hash" "hash de state.json mudou apos emit (before=$_hash_before after=$_hash_after)"; return 1; }
}

scenario_8_paridade_agente00c_vs_feature00c_layout() {
  _wsm_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  # 9.2.2 (converge FASE 9, ref 5.5.3): caminhos REAIS de layout, nao nomes
  # arbitrarios — <projeto>/.claude/agente-00c-state/ (sem short-name, 1 por
  # projeto) vs <projeto>/.claude/feature-00c-state/<short-name>/.
  _short="demo-feature"
  _agente00c_dir="$TMPDIR_TEST/.claude/agente-00c-state"
  _feature00c_dir="$TMPDIR_TEST/.claude/feature-00c-state/$_short"
  mkdir -p "$_agente00c_dir" "$_feature00c_dir"
  _wsm_write_fixture_scenario1
  cp "$TMPDIR_TEST/state.json" "$_agente00c_dir/state.json"
  cp "$TMPDIR_TEST/state.json" "$_feature00c_dir/state.json"
  _a=$(sh "$SCRIPT" emit --state-dir "$_agente00c_dir")
  _b=$(sh "$SCRIPT" emit --state-dir "$_feature00c_dir")
  [ "$_a" = "$_b" ] || { _fail "paridade" "layouts produzem saida divergente"; return 1; }
}

run_all_scenarios "$0"
