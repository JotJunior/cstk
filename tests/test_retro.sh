#!/bin/sh
# test_retro.sh — cobre global/skills/agente-00c-runtime/scripts/retro.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/retro.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_retro.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.2.6).
  _i_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_i_home"
  env HOME="$_i_home" "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC retro tests" >/dev/null 2>&1
}

# _read_consumed STATE_DIR — le o contador via path EN + fallback pt-BR.
# (state-rw.sh init ja emite EN; o fallback cobre states legados pt-BR.)
_read_consumed() {
  jq -r '
    ((.budgets // .orcamentos) // {})
    | .retro_executions_consumed // .retro_execucoes_consumidas // 0
  ' "$1/state.json"
}

# _seed_pt_state STATE_DIR — cria um state.json legado em chaves pt-BR
# (.orcamentos.retro_execucoes_*) sem passar pelo state-rw.sh init (que ja
# converge para EN). Prova o reader-fallback (.en // .pt) de back-compat.
_seed_pt_state() {
  mkdir -p "$1"
  cat > "$1/state.json" <<'PTSTATE'
{
  "schema_version": 1,
  "orcamentos": {
    "retro_execucoes_max_por_feature": 2,
    "retro_execucoes_consumidas": 0
  }
}
PTSTATE
}

scenario_count_inicial_0_2() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
}

scenario_check_inicial_passa() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check 0/2" "$_CAPTURED_EXIT"; return 1; }
}

scenario_consume_incrementa() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" consume --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2/2" || return 1
}

scenario_check_no_limite_exit_3() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check 2/2" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_consume_terceira_vez_exit_3_sem_modificar() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  _before=$(_read_consumed "$_sd")
  capture "$SCRIPT" consume --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "consume 3rd" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "consume negado" || return 1
  _after=$(_read_consumed "$_sd")
  if [ "$_before" != "$_after" ]; then
    _fail "consume negado MUTOU estado" "before=$_before after=$_after"
    return 1
  fi
}

scenario_reset_zera() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" reset --state-dir "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
}

scenario_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1"
    return 1
  fi
}

# ---- back-compat: reader-fallback sobre state legado pt-BR (.orcamentos) ----
# (schema-en-migration §6: >=1 fixture pt-BR provando que o reader EN+fallback
#  ainda le states gravados com chaves pt-BR antigas.)

scenario_pt_state_count_le_via_fallback() {
  _sd="$TMPDIR_TEST/pt"
  _seed_pt_state "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
}

scenario_pt_state_check_le_via_fallback() {
  _sd="$TMPDIR_TEST/pt"
  _seed_pt_state "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check pt 0/2" "$_CAPTURED_EXIT"; return 1; }
}

scenario_pt_state_consume_converge_para_en() {
  # 1o consume sobre state pt-BR legado: reader le consumed=0 via fallback
  # (.orcamentos); writer grava na chave EN (.budgets.retro_executions_consumed).
  # Prova convergencia EN-on-disk + que o reader EN ja enxerga o novo valor.
  _sd="$TMPDIR_TEST/pt"
  _seed_pt_state "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  _v=$(jq -r '.budgets.retro_executions_consumed' "$_sd/state.json")
  [ "$_v" = 1 ] || { _fail "writer EN" "esperado .budgets.retro_executions_consumed=1, obtido $_v"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1/2" || return 1
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.2 / FR-002 / SC-003) ====
# Fixture minima por CHK032: init sob config global state_backend=sqlite +
# retro-execucao CONSUMIDA (research §fixture item 6: com o default 0 do init
# o caminho de contagem nao-trivial nunca roda). consume/reset roteiam por
# state-rw.sh set (coluna int execution.retro_executions_consumed).

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_init_sqlite() {
  _is_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_is_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_is_home/.claude/cstk/config"
  env HOME="$_is_home" "$RW" init --state-dir "$1" \
    --execucao-id "x-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC retro sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_consume_incrementa_e_count_persiste() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" consume --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "consume sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "consume sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
  # Persistencia no state.db (retro-execucao consumida na fixture — caminho
  # de contagem nao-trivial): count le 1/2 e check ainda passa (1 < 2).
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1/2" || return 1
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check sqlite 1/2" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sqlite_limite_check_e_consume_negado_equivalente_json() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2o consume sqlite" "$_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  # Veredito equivalente ao backend JSON (SC-003): no limite, check exit 3 e
  # 3o consume negado SEM modificar estado (guard pre-write = CHECK do schema).
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "check no limite sqlite" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "limite atingido" || return 1
  capture "$SCRIPT" consume --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "3o consume sqlite" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "consume negado" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2/2" || return 1
}

scenario_sqlite_reset_zera_e_anti_mirror() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" reset --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reset sqlite" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
  # Anti-mirror (FR-003): nenhuma operacao pode materializar state.json
  # dentro do state-dir sqlite.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "retro criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
