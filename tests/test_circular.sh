#!/bin/sh
# test_circular.sh — cobre global/skills/agente-00c-runtime/scripts/circular.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/circular.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_circular.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.2.4).
  _i_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_i_home"
  env HOME="$_i_home" "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC circular tests" >/dev/null 2>&1
}

_push() {
  capture "$SCRIPT" push --state-dir "$1" --problema "$2" --solucao "$3"
}

scenario_push_inicial_acumula() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _push "$_sd" "Test failing on null body" "Add nil check"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "push" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1   # buffer size = 1
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "0	" || return 1
}

scenario_normalizacao_lowercase_mesmo_hash() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _push "$_sd" "TEST FAILING ON NULL BODY" "fix1"
  _ph1=$(printf '%s' "$_CAPTURED_STDOUT" | awk '{print $1}')
  _push "$_sd" "test failing on null body" "fix2"
  _ph2=$(printf '%s' "$_CAPTURED_STDOUT" | awk '{print $1}')
  if [ "$_ph1" != "$_ph2" ]; then
    _fail "normalizacao lowercase" "hashes diferem para mesmo problema case-different"
    return 1
  fi
}

scenario_normalizacao_pontuacao() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _push "$_sd" "Test, failing on null body!" "fix1"
  _ph1=$(printf '%s' "$_CAPTURED_STDOUT" | awk '{print $1}')
  _push "$_sd" "Test failing on null body" "fix2"
  _ph2=$(printf '%s' "$_CAPTURED_STDOUT" | awk '{print $1}')
  if [ "$_ph1" != "$_ph2" ]; then
    _fail "normalizacao pontuacao" "hashes diferem"
    return 1
  fi
}

scenario_buffer_fifo_max_6() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  for i in 1 2 3 4 5 6 7 8; do
    _push "$_sd" "Problema $i" "Solucao $i"
  done
  _size=$(jq '.circular_movement_history | length' "$_sd/state.json")
  if [ "$_size" != 6 ]; then
    _fail "buffer FIFO" "esperado 6, obtido $_size"
    return 1
  fi
  # Os mais antigos (1, 2) saem; mais recentes (7, 8) entram
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "0	" || return 1   # 6 entries, indices 0..5
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "$(printf '%s' "Problema 1" | tr '[:upper:]' '[:lower:]')"; then
    _fail "buffer FIFO" "Problema 1 (deveria ter saido) ainda presente"
    return 1
  fi
}

scenario_detect_sem_repeticao_exit_0() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _push "$_sd" "Problema A" "Solucao 1"
  _push "$_sd" "Problema B" "Solucao 2"
  capture "$SCRIPT" detect --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sem repeticao" "$_CAPTURED_EXIT"; return 1; }
}

scenario_detect_3_repeticoes_exit_3() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _push "$_sd" "Problema A" "Solucao 1"
  _push "$_sd" "Problema B" "Solucao 2"
  _push "$_sd" "Problema A" "Solucao 3"
  _push "$_sd" "Problema B" "Solucao 4"
  _push "$_sd" "Problema A" "Solucao 5"
  capture "$SCRIPT" detect --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "3 repeticoes" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "movimento circular detectado" || return 1
  assert_stdout_contains "	3" || return 1   # contagem de problem_hash A
}

scenario_clear_esvazia_buffer() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _push "$_sd" "Problema A" "Solucao 1"
  _push "$_sd" "Problema A" "Solucao 2"
  _push "$_sd" "Problema A" "Solucao 3"
  capture "$SCRIPT" clear --state-dir "$_sd"
  capture "$SCRIPT" detect --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apos clear" "$_CAPTURED_EXIT"; return 1; }
  _size=$(jq '.circular_movement_history | length' "$_sd/state.json")
  [ "$_size" = 0 ] || { _fail "buffer nao zerado" "size=$_size"; return 1; }
}

scenario_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" detect --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1"
    return 1
  fi
}

# Back-compat (schema-en-migration): readers (.en // .pt). Um state pt-BR
# legado (container historico_movimento_circular + folhas problema_hash/
# solucao_hash) precisa continuar sendo lido por detect/list via fallback,
# antes do migrate do command-pai convergir o disco para EN.
_write_legacy_pt_state() {
  # $1 = state-dir. Escreve um state.json minimo no schema pt-BR antigo, com
  # 3 repeticoes do mesmo problema_hash (dispara detect exit 3).
  _sd="$1"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": 1,
  "historico_movimento_circular": [
    { "problema_hash": "aaa111", "solucao_hash": "sol1", "timestamp": "2026-01-01T00:01:00Z" },
    { "problema_hash": "bbb222", "solucao_hash": "sol2", "timestamp": "2026-01-01T00:02:00Z" },
    { "problema_hash": "aaa111", "solucao_hash": "sol3", "timestamp": "2026-01-01T00:03:00Z" },
    { "problema_hash": "aaa111", "solucao_hash": "sol4", "timestamp": "2026-01-01T00:04:00Z" }
  ]
}
JSON
}

scenario_backcompat_pt_detect_le_via_fallback() {
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_pt_state "$_sd"
  capture "$SCRIPT" detect --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "back-compat pt detect" "esperado exit 3 lendo schema pt-BR, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "movimento circular detectado" || return 1
  # problema_hash aaa111 aparece 3x -> reader-fallback (.problem_hash // .problema_hash)
  assert_stdout_contains "aaa111	3" || return 1
}

scenario_backcompat_pt_list_le_via_fallback() {
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_pt_state "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "back-compat pt list" "$_CAPTURED_STDERR"; return 1; }
  # Folhas pt (problema_hash/solucao_hash) emergem via fallback do reader.
  assert_stdout_contains "aaa111" || return 1
  assert_stdout_contains "sol1" || return 1
}

scenario_backcompat_pt_push_converge_para_en() {
  # push sobre state pt-BR vivo: acumula via fallback e grava container EN.
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_pt_state "$_sd"
  _push "$_sd" "Novo problema apos legado" "nova solucao"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "push sobre legado" "$_CAPTURED_STDERR"; return 1; }
  # Writer emite EN: container .circular_movement_history passa a existir e
  # contem os 4 itens legados + 1 novo = 5.
  _size_en=$(jq '.circular_movement_history | length' "$_sd/state.json")
  if [ "$_size_en" != 5 ]; then
    _fail "push converge EN" "esperado 5 em circular_movement_history, obtido $_size_en"
    return 1
  fi
  # A nova entrada usa folhas EN (problem_hash/solution_hash).
  _last_en=$(jq -r '.circular_movement_history[-1] | has("problem_hash") and has("solution_hash")' "$_sd/state.json")
  [ "$_last_en" = "true" ] || { _fail "push folha EN" "ultima entrada sem problem_hash/solution_hash"; return 1; }
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.2 / FR-002 / SC-003) ====
# Fixture minima por CHK032: init sob config global state_backend=sqlite
# (padrao test__state-read.sh). push/clear roteiam por state-rw.sh set
# (coluna json execution.circular_movement_history).

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
    --descricao "POC circular sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_push_acumula_e_list_persiste() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _push "$_sd" "Test failing on null body" "Add nil check"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "push sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "push sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
  assert_stdout_contains "	1" || return 1   # buffer size = 1
  _push "$_sd" "Another distinct problem" "another fix"
  assert_stdout_contains "	2" || return 1
  # Persistencia no state.db: list le o que o set gravou.
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list sqlite" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "0	" || return 1
  assert_stdout_contains "1	" || return 1
}

scenario_sqlite_detect_exit_3_equivalente_json() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _push "$_sd" "same recurring problem" "fix A"
  _push "$_sd" "same recurring problem" "fix B"
  capture "$SCRIPT" detect --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "detect < threshold sqlite" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _push "$_sd" "same recurring problem" "fix C"
  capture "$SCRIPT" detect --state-dir "$_sd"
  # Veredito equivalente ao backend JSON (SC-003): exit 3 + diagnostico.
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "detect >= 3 sqlite" "esperado 3, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "movimento circular" || return 1
}

scenario_sqlite_clear_esvazia_e_anti_mirror() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _push "$_sd" "p1" "s1"
  _push "$_sd" "p2" "s2"
  capture "$SCRIPT" clear --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "clear sqlite" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd"
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "clear sqlite" "buffer nao esvaziou: $_CAPTURED_STDOUT"
    return 1
  fi
  # Anti-mirror (FR-003): nenhuma operacao pode materializar state.json
  # dentro do state-dir sqlite.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "circular criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
