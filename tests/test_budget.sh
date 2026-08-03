#!/bin/sh
# test_budget.sh — cobre global/skills/agente-00c-runtime/scripts/budget.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/budget.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
ON="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_budget.sh: jq ausente — pulando\n'
  exit 0
fi

_init_with_onda() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.1.2).
  _iwo_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_iwo_home"
  env HOME="$_iwo_home" "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC budget tests" >/dev/null 2>&1
  capture "$ON" start --state-dir "$1"
}

scenario_status_imprime_3_linhas_tsv() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  capture "$SCRIPT" status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "tool_calls	0	80" || return 1
  assert_stdout_contains "wallclock	" || return 1
  assert_stdout_contains "state_size	" || return 1
}

scenario_check_inicial_passa() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check inicial" "$_CAPTURED_STDERR"; return 1; }
}

scenario_tool_calls_threshold_dispara_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # Writer via state-rw set: campo EN (schema-en-migration). O set canonicaliza
  # o doc p/ EN antes de aplicar, entao o reader le pelo path EN primario.
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.tool_calls_current_wave' --value '85'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tool_calls trigger" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "tool_calls	85	80" || return 1
}

scenario_state_size_threshold_dispara_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # Reduz threshold p/ valor menor que estado atual (campo EN — schema-en-migration)
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.state_size_threshold_bytes' --value '100'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state_size trigger" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "state_size	" || return 1
}

scenario_wallclock_threshold_dispara_exit_1() {
  # Onda ABERTA (start sem end — via _init_with_onda) com threshold forcado
  # a 0: qualquer wallclock >= 0 dispara. Distinto do cenario de onda
  # FECHADA em scenario_check_apos_start_pos_retomada_sem_falso_breach
  # (budget-resume-wallclock FASE 2.1): aqui a onda em avaliacao esta de
  # fato aberta (breach GENUINO); la a onda foi fechada e o `start` da
  # retomada precede o check (sem breach). Nao regredir esta distincao.
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # Reduz threshold p/ 0 -> qualquer wallclock dispara (campo EN — schema-en-migration)
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.wallclock_threshold_seconds' --value '0'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "wallclock trigger" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "wallclock	" || return 1
}

# ---------------------------------------------------------------------------
# budget-resume-wallclock (spec.md FR-004/SC-001/SC-002/SC-003) — retomada:
# `state-ondas.sh start` DEVE preceder `budget.sh check` para nao medir
# wallclock contra o current_wave_start de uma onda JA fechada (ver
# invariante "resume sempre segue onda fechada" em
# agente-00c-feature-orchestrator.md).
# ---------------------------------------------------------------------------

# Prepara o state "onda FECHADA com current_wave_start herdado no passado" —
# representa uniformemente os dois caminhos de retomada do feature-00c
# (pos-agendamento e pos-bloqueio-humano): ambos garantem onda anterior
# fechada antes do resume (CHK007/CHK023).
_prep_onda_fechada_wallclock_antigo() {
  _init_with_onda "$1"
  capture "$ON" end --state-dir "$1" --motivo-termino etapa_concluida_avancando
  capture "$RW" set --state-dir "$1" \
    --field '.budgets.current_wave_start' --value '"2020-01-01T00:00:00Z"'
}

# 2.1.2 — BUG CORRIGIDO: apos `state-ondas.sh start` (ordem corrigida do
# Loop, passo 3.bis), o check NAO deve disparar breach falso mesmo com o
# current_wave_start antigo herdado da onda anterior ja fechada.
scenario_check_apos_start_pos_retomada_sem_falso_breach() {
  _sd="$TMPDIR_TEST/state"
  _prep_onda_fechada_wallclock_antigo "$_sd"
  capture "$ON" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start pos-retomada" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "check pos-start nao deveria disparar breach" \
      "esperado exit 0, obtido $_CAPTURED_EXIT — stdout: $_CAPTURED_STDOUT"
    return 1
  fi
}

# 2.1.3 — GUARD DE NAO-REGRESSAO: no MESMO state preparado, mas SEM o
# `state-ondas.sh start` antes (ordem ANTIGA do Loop, o defeito em si),
# o check DEVE disparar breach — prova que a diferenca de comportamento
# esta na ORDEM das chamadas, nao numa mudanca de semantica dos helpers
# (nenhum dos dois scripts foi alterado por esta feature).
scenario_check_sem_start_pos_retomada_dispara_breach_antigo() {
  _sd="$TMPDIR_TEST/state"
  _prep_onda_fechada_wallclock_antigo "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "check sem start deveria disparar breach (ordem antiga)" \
      "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "wallclock	" || return 1
}

# 2.2.2 — EDGE CASE (delta ~0, quickstart.md Scenario 3): onda fechada ha
# poucos segundos (sem timestamp forcado no passado) seguida da ordem
# corrigida (start -> check) NAO deve disparar breach — mesma ausencia de
# falso-positivo de uma retomada tardia (2.1.2), agora numa retomada quase
# imediata.
scenario_check_apos_start_retomada_imediata_delta_zero_sem_breach() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  capture "$ON" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$ON" start --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "check retomada imediata nao deveria disparar breach" \
      "esperado exit 0, obtido $_CAPTURED_EXIT — stdout: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_check_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1"
    return 1
  fi
}

# Back-compat (schema-en-migration idiom §6): state pt-BR puro (chaves legadas
# .orcamentos.*) DEVE continuar sendo lido via fallback (.en // .pt). Fixture
# montada na mao para nao depender da migracao de state-rw/state-ondas; prova
# que o reader EN-com-fallback do budget.sh ainda dispara sobre dados pt-BR.
scenario_check_fallback_state_pt_br_legado() {
  _sd="$TMPDIR_TEST/legacy"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": 6,
  "orcamentos": {
    "tool_calls_onda_corrente": 90,
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576,
    "inicio_onda_corrente": null
  }
}
JSON
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "fallback pt-BR check" "esperado 1 (90>=80 via .orcamentos), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "tool_calls	90	80" || return 1
}

# Companheiro do anterior: status sobre o MESMO state pt-BR puro deve imprimir
# os valores lidos via fallback (tool_calls=90, threshold=80) sem veredito.
scenario_status_fallback_state_pt_br_legado() {
  _sd="$TMPDIR_TEST/legacy"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": 6,
  "orcamentos": {
    "tool_calls_onda_corrente": 90,
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576,
    "inicio_onda_corrente": null
  }
}
JSON
  capture "$SCRIPT" status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status fallback pt-BR" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "tool_calls	90	80" || return 1
  assert_stdout_contains "wallclock	0	5400" || return 1
}

# ==== Sidecar de ticks do hook PostToolUse (tool-call-ticks.log) ====

scenario_check_soma_sidecar_e_dispara_threshold() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # 78 no campo do state + 2 no sidecar do hook = 80 >= threshold 80.
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.tool_calls_current_wave' --value '78'
  printf 't1\nt2\n' > "$_sd/tool-call-ticks.log"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "check" "esperado exit 1 (78 campo + 2 sidecar = 80), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "tool_calls	80	80" || return 1
}

scenario_status_reflete_sidecar_sem_disparar() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  printf 't1\nt2\nt3\n' > "$_sd/tool-call-ticks.log"
  capture "$SCRIPT" status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "tool_calls	3	80" || return 1
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.1 / FR-002 / SC-003) ====
# Fixture minima por CHK032: init sob config global state_backend=sqlite
# (padrao test__state-read.sh) + onda aberta via state-ondas start (backend
# decidido pela presenca de state.db, nao pelo HOME nas chamadas seguintes).

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_init_sqlite_with_onda() {
  _isw_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_isw_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_isw_home/.claude/cstk/config"
  env HOME="$_isw_home" "$RW" init --state-dir "$1" \
    --execucao-id "x-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC budget sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
  capture "$ON" start --state-dir "$1"
}

scenario_sqlite_check_inicial_passa_sem_state_json_ausente() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite_with_onda "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "check sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
}

scenario_sqlite_tool_calls_threshold_dispara_exit_1_equivalente_json() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite_with_onda "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  # Sob sqlite `.budgets.tool_calls_current_wave` e derivado da onda aberta
  # (set direto e recusado); o sidecar do hook e backend-agnostico e soma na
  # mesma dimensao (contrato do budget.sh) — 85 ticks >= threshold 80.
  awk 'BEGIN{for(i=1;i<=85;i++)print "t"i}' > "$_sd/tool-call-ticks.log"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tool_calls trigger sqlite" "esperado 1, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"
    return 1
  fi
  # Veredito equivalente ao backend JSON (SC-003): mesma linha TSV.
  assert_stdout_contains "tool_calls	85	80" || return 1
}

scenario_sqlite_status_imprime_3_linhas_e_nao_cria_mirror() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite_with_onda "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status sqlite" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "tool_calls	0	80" || return 1
  assert_stdout_contains "wallclock	" || return 1
  assert_stdout_contains "state_size	" || return 1
  # Anti-mirror (FR-003): a leitura nao pode materializar state.json no state-dir.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "status criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
