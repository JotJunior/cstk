#!/bin/sh
# test_cycles.sh — cobre global/skills/agente-00c-runtime/scripts/cycles.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/cycles.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_cycles.sh: jq ausente — pulando\n'
  exit 0
fi

# state-rw.sh init (migrado) ja grava o container .budgets em EN no disco, logo
# os cenarios abaixo exercitam o caminho EN dos readers/writers de cycles.sh
# (.budgets.cycles_consumed_current_stage / .budgets.max_cycles_per_stage).
_init() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.2.2).
  _i_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_i_home"
  env HOME="$_i_home" "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC cycles tests" >/dev/null 2>&1
}

# Fixture pt-BR legado (schema-en-migration back-compat): escreve um state
# direto em disco com o container pt-BR .orcamentos.* SEM passar por state-rw
# (cujo canonicalizer converteria para EN). cycles.sh e direct-jq-on-file e
# nao canonicaliza — depende puramente do fallback (.en // .pt) nos readers.
# $2 = ciclos_max_por_etapa, $3 = ciclos_consumidos_etapa_corrente.
_init_legacy_pt() {
  mkdir -p "$1"
  jq -n --argjson max "$2" --argjson cur "$3" '{
    schema_version: 6,
    orcamentos: {
      ciclos_max_por_etapa: $max,
      ciclos_consumidos_etapa_corrente: $cur
    }
  }' > "$1/state.json"
}

scenario_count_inicial_zero() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_tick_incrementa_sequencial() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  for n in 1 2 3; do
    capture "$SCRIPT" tick --state-dir "$_sd"
    assert_stdout_contains "$n" || return 1
  done
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "3" || return 1
}

scenario_tick_progress_made_zera() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd" --progress-made
  assert_stdout_contains "0" || return 1
}

scenario_tick_acima_de_max_exit_3() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  for _ in 1 2 3 4 5; do
    capture "$SCRIPT" tick --state-dir "$_sd"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tick legal" "$_CAPTURED_EXIT"; return 1; }
  done
  capture "$SCRIPT" tick --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "tick > 5" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "loop_em_etapa" || return 1
}

scenario_check_acima_de_max_exit_3() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  # state-rw.sh init grava .budgets em EN; o set usa o path EN para que o
  # valor caia onde o reader de cycles.sh procura primeiro.
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.cycles_consumed_current_stage' --value '6'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check > 5" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_reset_zera_contador() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd"
  capture "$SCRIPT" reset --state-dir "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1"
    return 1
  fi
}

# ===== back-compat pt-BR (schema-en-migration: reader-fallback) =====

scenario_count_le_state_legado_pt() {
  # Reader-fallback: count deve ler .orcamentos.ciclos_consumidos_etapa_corrente
  # de um state pt-BR puro (sem o container EN .budgets).
  _sd="$TMPDIR_TEST/legacy"
  _init_legacy_pt "$_sd" 5 4
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "4" || return 1
}

scenario_tick_le_pt_e_escreve_en() {
  # Reader-fallback no read + writer EN no write: tick le o valor pt-BR (4),
  # incrementa para 5 e grava em .budgets.cycles_consumed_current_stage.
  # O proximo count entao prefere o ramo EN (5) sobre o pt-BR stale (4).
  _sd="$TMPDIR_TEST/legacy"
  _init_legacy_pt "$_sd" 5 4
  capture "$SCRIPT" tick --state-dir "$_sd"
  assert_stdout_contains "5" || return 1
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tick legado pt" "$_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "5" || return 1
}

scenario_check_le_state_legado_pt_acima_de_max_exit_3() {
  # Reader-fallback: check sobre state pt-BR puro com contador (6) acima do
  # max pt-BR (5) deve abortar com exit 3, sem nunca ler o container EN.
  _sd="$TMPDIR_TEST/legacy"
  _init_legacy_pt "$_sd" 5 6
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check legado pt > max" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "loop_em_etapa" || return 1
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.2 / FR-002 / SC-003) ====
# Fixture minima por CHK032: init sob config global state_backend=sqlite
# (padrao test__state-read.sh). Mutacoes de tick/reset roteiam por
# state-rw.sh set (coluna execution.cycles_consumed_current_stage).

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
    --descricao "POC cycles sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_tick_incrementa_e_count_persiste() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" tick --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tick sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "tick sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
  capture "$SCRIPT" tick --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  # Persistencia no state.db: count le o valor gravado pelo set.
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
}

scenario_sqlite_tick_acima_de_max_exit_3_equivalente_json() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  for _ in 1 2 3 4 5; do
    capture "$SCRIPT" tick --state-dir "$_sd"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tick legal sqlite" "$_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  done
  capture "$SCRIPT" tick --state-dir "$_sd"
  # Veredito equivalente ao backend JSON (SC-003): exit 3 + loop_em_etapa.
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "tick > 5 sqlite" "esperado 3, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "loop_em_etapa" || return 1
  # Estado intacto (contrato runtime-interfaces §1 / CHECK do schema): o
  # estouro nao e persistido — contador permanece no max e um novo tick
  # re-dispara o veredito de aborto.
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "5" || return 1
  capture "$SCRIPT" tick --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "re-tick sqlite pos-estouro" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sqlite_progress_reset_e_anti_mirror() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" tick --state-dir "$_sd"
  capture "$SCRIPT" tick --state-dir "$_sd" --progress-made
  assert_stdout_contains "0" || return 1
  capture "$SCRIPT" tick --state-dir "$_sd"
  capture "$SCRIPT" reset --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reset sqlite" "$_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
  # Anti-mirror (FR-003): nenhuma operacao pode materializar state.json
  # dentro do state-dir sqlite.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "cycles criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
