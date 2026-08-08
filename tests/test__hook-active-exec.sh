#!/bin/sh
# test__hook-active-exec.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/_hook-active-exec.sh (helper
# sourceable de deteccao tri-estado de execucao ativa, feature
# hooks-db-parity FASE 2).
#
# Ref: docs/specs/hooks-db-parity/contracts/hook-active-exec.md
#      docs/specs/hooks-db-parity/quickstart.md Cenarios 0, 4, 5, 6, 8, 9, 10
#
# O arquivo sob teste e sourceable (nao executavel), expondo a funcao de
# shell `hook_active_exec`. Cada scenario roda em subshell FRESCO via
# `sh -c '... . "$1" ... hook_active_exec "$2" ...' _ HELPER CWD BUSY`
# (nunca prefixo de atribuicao direto sobre uma chamada de funcao — bash
# em modo POSIX, que e /bin/sh no macOS, VAZA a atribuicao apos a chamada
# de uma funcao, ao contrario de dash; verificado empiricamente nesta
# maquina). Este idioma tambem espelha o uso real em producao: cada
# invocacao do hook e um PROCESSO NOVO.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

HELPER="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_hook-active-exec.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test__hook-active-exec.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi

# _run_helper CWD [BUSY_MS] -> invoca hook_active_exec num processo `sh`
# novo; popula _CAPTURED_*.
_run_helper() {
  _rh_cwd="$1"
  _rh_busy="${2:-}"
  capture sh -c '
    . "$1"
    if [ -n "$3" ]; then
      HAE_BUSY_TIMEOUT_MS="$3"
      export HAE_BUSY_TIMEOUT_MS
    fi
    hook_active_exec "$2"
  ' _ "$HELPER" "$_rh_cwd" "$_rh_busy"
}

# _active_feature_json CWD SHORT STATUS -> fixture feature-00c ativa, backend JSON.
_active_feature_json() {
  mkdir -p "$1/.claude/feature-00c-state/$2"
  printf '{"execution":{"status":"%s"}}' "$3" \
    > "$1/.claude/feature-00c-state/$2/state.json"
}

# _active_agente_json CWD STATUS -> fixture agente-00c ativa, backend JSON.
_active_agente_json() {
  mkdir -p "$1/.claude/agente-00c-state"
  printf '{"execution":{"status":"%s"}}' "$2" > "$1/.claude/agente-00c-state/state.json"
}

# _sqlite_state_db CWD SHORT STATUS -> fixture feature-00c ativa, backend
# SQLite. WAL habilitado (paridade com state-db-schema.sh, producao real),
# tabela `execution` minima com a unica coluna que o helper le.
_sqlite_state_db() {
  _ssd_dir="$1/.claude/feature-00c-state/$2"
  mkdir -p "$_ssd_dir"
  sqlite3 "$_ssd_dir/state.db" "PRAGMA journal_mode=WAL; CREATE TABLE execution(status TEXT); INSERT INTO execution VALUES('$3');" >/dev/null 2>&1
}

# _sqlite_state_db_agente CWD STATUS -> idem, para agente-00c-state.
_sqlite_state_db_agente() {
  _ssda_dir="$1/.claude/agente-00c-state"
  mkdir -p "$_ssda_dir"
  sqlite3 "$_ssda_dir/state.db" "PRAGMA journal_mode=WAL; CREATE TABLE execution(status TEXT); INSERT INTO execution VALUES('$2');" >/dev/null 2>&1
}

# _make_shim_path_no_sqlite: PATH completo (symlinks) MENOS sqlite3.
# Armadilha conhecida do repositorio (memoria de projeto
# feedback_test_path_stub_cannot_hide_usrbin.md): um PATH minimo/stub nao
# esconde binarios que o SUT resolve por caminho absoluto (/usr/bin,
# /opt/homebrew/bin, ...); o teste MUST montar um PATH completo com
# symlinks para tudo, exceto o binario sob supressao.
_make_shim_path_no_sqlite() {
  _shim="$TMPDIR_TEST/shimbin-no-sqlite"
  mkdir -p "$_shim"
  for _cmd in sh jq basename dirname sed sort printf cat mktemp find rm \
              tr wc mkdir ls cp mv chmod grep cut env command date; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# ==== 2.3.1 — execucao ativa sob state.json -> exit 0, tri-estado correto ====

scenario_json_ativo_feature00c_exit0_tristate_correto() {
  _active_feature_json "$TMPDIR_TEST" "demo" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
  case "$_CAPTURED_STDOUT" in
    feature-00c*"$TMPDIR_TEST/.claude/feature-00c-state/demo"*json*) : ;;
    *) _fail "tri-estado" "esperado 'feature-00c<TAB>DIR<TAB>json', obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_json_ativo_aguardando_humano_tambem_conta() {
  _active_feature_json "$TMPDIR_TEST" "demo" "aguardando_humano"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
}

# ==== 2.3.2 — execucao ativa sob state.db -> exit 0 (G2: db vence sobre json) ====

scenario_sqlite_ativo_exit0() {
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
  case "$_CAPTURED_STDOUT" in
    feature-00c*sqlite) : ;;
    *) _fail "backend" "esperado backend=sqlite, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_g2_state_db_vence_sobre_state_json_no_mesmo_dir() {
  # Mesmo state-dir com os DOIS arquivos: json diz concluida (inativa),
  # db diz em_andamento (ativa). G2: state.db vence.
  _active_feature_json "$TMPDIR_TEST" "demo" "concluida"
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
  case "$_CAPTURED_STDOUT" in
    feature-00c*sqlite) : ;;
    *) _fail "G2" "esperado sqlite vencer sobre json no mesmo dir; obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ==== 2.3.3 — nenhum state presente -> exit 1, nunca 2 (G4, FR-007) ====

scenario_sem_state_algum_exit1_nunca_2() {
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 1 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_dir_feature00c_existe_mas_vazio_exit1() {
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/x"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 1 || return 1
}

# ==== 2.3.4 — state.db presente + sqlite3 ausente -> exit 2, nunca 1 (G5) ====

scenario_sqlite3_ausente_state_db_presente_exit2_nunca_1() {
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  _shim=$(_make_shim_path_no_sqlite)
  capture env PATH="$_shim" sh -c '
    . "$1"
    hook_active_exec "$2"
  ' _ "$HELPER" "$TMPDIR_TEST"
  assert_exit_captured 2 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "esperado vazio (G5+contrato), obtido: $_CAPTURED_STDERR"; return 1; }
}

# ==== 2.3.5 — state.db corrompido -> exit 2 ====

scenario_state_db_corrompido_exit2() {
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo"
  printf 'not a database' > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.db"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 2 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
}

# ==== 2.3.6 — multiplos state-dirs simultaneos -> G1 ====

scenario_g1_agente00c_vence_sobre_feature00c() {
  _active_agente_json "$TMPDIR_TEST" "em_andamento"
  _active_feature_json "$TMPDIR_TEST" "zzz" "em_andamento"
  _sqlite_state_db "$TMPDIR_TEST" "aaa" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
  case "$_CAPTURED_STDOUT" in
    agente-00c*) : ;;
    *) _fail "G1" "esperado agente-00c vencer; obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_g1_menor_short_name_lexicografico_entre_feature00c() {
  # backend misto: bbb (json) e aaa (sqlite) — G1 exige "aaa" vencer
  # independente do backend de cada state-dir concorrente.
  _active_feature_json "$TMPDIR_TEST" "bbb" "em_andamento"
  _sqlite_state_db "$TMPDIR_TEST" "aaa" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
  case "$_CAPTURED_STDOUT" in
    feature-00c*"/aaa"*) : ;;
    *) _fail "G1 lexicografico" "esperado 'aaa' vencer; obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ==== 2.3.7 — status terminal -> exit 1 (fora de escopo) ====

scenario_status_concluida_exit1() {
  _sqlite_state_db "$TMPDIR_TEST" "demo" "concluida"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 1 || return 1
}

scenario_status_abortada_exit1() {
  _active_feature_json "$TMPDIR_TEST" "demo" "abortada"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 1 || return 1
}

# ==== 2.3.8 — stderr SEMPRE vazio (nao so no caso feliz) ====

scenario_stderr_sempre_vazio_caso_feliz() {
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr caso feliz" "esperado vazio, obtido: $_CAPTURED_STDERR"; return 1; }
}

scenario_stderr_sempre_vazio_db_corrompido() {
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo"
  printf 'not a database' > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.db"
  _run_helper "$TMPDIR_TEST"
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr db corrompido" "esperado vazio, obtido: $_CAPTURED_STDERR"; return 1; }
}

scenario_stderr_sempre_vazio_sem_state() {
  _run_helper "$TMPDIR_TEST"
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr sem state" "esperado vazio, obtido: $_CAPTURED_STDERR"; return 1; }
}

scenario_stderr_sempre_vazio_uso_incorreto_cwd_vazio() {
  _run_helper ""
  assert_exit_captured 3 || return 1
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr cwd vazio" "esperado vazio, obtido: $_CAPTURED_STDERR"; return 1; }
}

# ==== 2.3.9 — G7: nenhuma escrita/criacao de arquivo/diretorio ====

scenario_g7_helper_nao_escreve_nenhum_arquivo() {
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  # Sidecars -shm/-wal ficam FORA da comparacao: sao artefatos legitimos
  # do motor no fallback rw sobre um db WAL em repouso (nota de escopo do
  # contrato hook-active-exec.md / cabecalho do helper, research Decision
  # 1.a). A persistencia deles pos-fixture varia por plataforma (macOS os
  # mantem; Linux os remove no close), o que tornava este cenario
  # plataforma-dependente — vide FAIL do release v6.4.0 no CI Ubuntu.
  _before=$(find "$TMPDIR_TEST" -type f | grep -v -E -- '-(shm|wal)$' | LC_ALL=C sort)
  _run_helper "$TMPDIR_TEST"
  _after=$(find "$TMPDIR_TEST" -type f | grep -v -E -- '-(shm|wal)$' | LC_ALL=C sort)
  [ "$_before" = "$_after" ] || {
    _fail "G7" "conjunto de arquivos (excluindo sidecars -shm/-wal) mudou apos a chamada (antes/depois):
before: $_before
after:  $_after"
    return 1
  }
}

scenario_g7_helper_nao_cria_diretorio() {
  _active_feature_json "$TMPDIR_TEST" "demo" "em_andamento"
  _before=$(find "$TMPDIR_TEST" -type d | LC_ALL=C sort)
  _run_helper "$TMPDIR_TEST"
  _after=$(find "$TMPDIR_TEST" -type d | LC_ALL=C sort)
  [ "$_before" = "$_after" ] || { _fail "G7 dirs" "diretorios mudaram; antes: $_before; depois: $_after"; return 1; }
}

# ==== SEC-M3: teto defensivo de 100 state-dirs (task 1.4) ====

scenario_sec_m3_teto_100_dirs_estourado_produz_indeterminada() {
  _i=0
  while [ "$_i" -lt 105 ]; do
    _d=$(printf 'a%03d' "$_i")
    _active_feature_json "$TMPDIR_TEST" "$_d" "concluida"
    _i=$((_i + 1))
  done
  # nome que ordena DEPOIS de todos os 105 dirs terminais acima -> nunca
  # alcancado antes do teto.
  _active_feature_json "$TMPDIR_TEST" "zzz-ativo" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 2 || return 1
}

scenario_sec_m3_dentro_do_teto_encontra_ativo() {
  _i=0
  while [ "$_i" -lt 90 ]; do
    _d=$(printf 'a%03d' "$_i")
    _active_feature_json "$TMPDIR_TEST" "$_d" "concluida"
    _i=$((_i + 1))
  done
  _active_feature_json "$TMPDIR_TEST" "zzz-ativo" "em_andamento"
  _run_helper "$TMPDIR_TEST"
  assert_exit_captured 0 || return 1
}

# ==== SEC-M2: busy_timeout opcional via HAE_BUSY_TIMEOUT_MS ====

scenario_busy_timeout_opcional_metricas_50ms() {
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  _run_helper "$TMPDIR_TEST" "50"
  assert_exit_captured 0 || return 1
}

# ==== Latencia informal (nao-gateante — gate real e FASE 6/6.1) ====
# Registra apenas um DIAGNOSTICO best-effort da ordem de grandeza, sem
# impor teto aqui (o teto automatizado com mediana N=20 e o hook completo
# e tarefa da FASE 6 — este scenario e so um canario informativo).

scenario_latencia_informal_um_state_dir_sqlite() {
  if ! command -v perl >/dev/null 2>&1; then
    printf '# latencia informal: perl ausente, skip\n'
    return 0
  fi
  _sqlite_state_db "$TMPDIR_TEST" "demo" "em_andamento"
  _t0=$(perl -MTime::HiRes=time -e 'printf "%.6f", time' 2>/dev/null) || return 0
  _run_helper "$TMPDIR_TEST"
  _t1=$(perl -MTime::HiRes=time -e 'printf "%.6f", time' 2>/dev/null) || return 0
  _ms=$(LC_NUMERIC=C awk -v a="$_t0" -v b="$_t1" 'BEGIN{printf "%.2f", (b-a)*1000}' 2>/dev/null) || _ms="?"
  printf '# latencia informal (1 dir, sqlite): %sms (referencia; gate real = FASE 6)\n' "$_ms"
}

# ==== 2.3.10 — registro no run.sh + convencao 1:1 ====
# (verificado por tests/run.sh::_expected_test_for_script e
# --check-coverage; nenhum scenario adicional necessario aqui — o proprio
# NOME deste arquivo, test__hook-active-exec.sh, satisfaz a convencao
# test_<basename-sem-.sh> para plugins/cstk/skills/agente-00c-runtime/scripts/
# _hook-active-exec.sh.)

# assert_exit_captured EXPECTED -> variante de assert_exit que usa a
# captura ja feita por _run_helper (sem re-executar comando).
assert_exit_captured() {
  _expected="$1"
  if [ "$_CAPTURED_EXIT" -eq "$_expected" ]; then
    return 0
  fi
  _fail "assert_exit_captured" "esperado exit=$_expected, obtido exit=$_CAPTURED_EXIT (stdout=$_CAPTURED_STDOUT stderr=$_CAPTURED_STDERR)"
  return 1
}

run_all_scenarios
exit $?
