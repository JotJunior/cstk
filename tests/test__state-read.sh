#!/bin/sh
# test__state-read.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/_state-read.sh
# (sibling sourceable de materializacao — feature state-db-runtime-parity,
# FASE 1 task 1.2).
#
# Ref: docs/specs/state-db-runtime-parity/contracts/runtime-interfaces.md §4
#      docs/specs/state-db-runtime-parity/tasks.md 1.2.5
#      spec FR-001/FR-003/FR-004/FR-012
#
# Nota (1.2.3 / FR-012): a ausencia REAL de `sqlite3` no host nao e simulada
# via PATH-stub (gotcha conhecido: stub de PATH nao esconde binario de
# /usr/bin de forma portavel — falso-pass local, quebra no CI). A obrigacao
# do helper e PROPAGAR a falha rapida do `state-rw.sh read`; isso e coberto
# por (a) fake STATE_READ_RW reproduzindo o modo de falha (hermetico) e
# (b) state.db corrompido contra o state-rw.sh real (integracao).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test__state-read.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_state-read.sh
. "$_R/_state-read.sh"

# Sourced a partir do teste, `dirname $0` apontaria para tests/ — usar o
# override documentado no header do helper.
STATE_READ_RW="$_R/state-rw.sh"
export STATE_READ_RW

MIN_SQLITE_VER="3.45.1"

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

# Fixture: state-dir JSON via state-rw.sh init com HOME falso sem config
# (backend default json).
_mk_json_state_dir() {
  _mj_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_mj_home"
  _mj_sd="$TMPDIR_TEST/sd-json"
  env HOME="$_mj_home" "$_R/state-rw.sh" init --state-dir "$_mj_sd" \
    --execucao-id "exec-sr-json" --projeto-alvo-path "/tmp/p-sr" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    >/dev/null 2>&1 || return 1
  printf '%s\n' "$_mj_sd"
}

# Fixture: state-dir SQLite via config global state_backend=sqlite simulada
# com HOME falso (padrao test_state-rw.sh scenario_init_sqlite_*).
_mk_sqlite_state_dir() {
  _ms_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_ms_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_ms_home/.claude/cstk/config"
  _ms_sd="$TMPDIR_TEST/sd-sqlite"
  env HOME="$_ms_home" "$_R/state-rw.sh" init --state-dir "$_ms_sd" \
    --execucao-id "exec-sr-sqlite" --projeto-alvo-path "/tmp/p-sr" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    >/dev/null 2>&1 || return 1
  [ -f "$_ms_sd/state.db" ] || return 1
  printf '%s\n' "$_ms_sd"
}

# ==== Backend JSON (FR-004: zero mudanca) ====

scenario_json_devolve_proprio_state_json() {
  _sd=$(_mk_json_state_dir) || { _fail "fixture json" "init falhou"; return 1; }
  _out=$(state_read_materialize "$_sd") || { _fail "materialize json" "exit != 0"; return 1; }
  [ "$_out" = "$_sd/state.json" ] || { _fail "path devolvido" "obtido '$_out'"; return 1; }
  jq -e '.execution.id' "$_out" >/dev/null 2>&1 || { _fail "state.json legivel por jq" ""; return 1; }
}

scenario_json_state_dir_vazio_devolve_path_sem_criar_nada() {
  # FR-004: cada consumidor preserva seu proprio tratamento de "state.json
  # ausente" — o helper e so path builder no backend JSON.
  _sd="$TMPDIR_TEST/sd-vazio"
  mkdir -p "$_sd"
  _out=$(state_read_materialize "$_sd") || { _fail "materialize dir vazio" "exit != 0"; return 1; }
  [ "$_out" = "$_sd/state.json" ] || { _fail "path devolvido" "obtido '$_out'"; return 1; }
  [ ! -e "$_sd/state.json" ] || { _fail "helper NAO deve criar state.json" ""; return 1; }
  _n=$(find "$_sd" -mindepth 1 | wc -l | tr -d ' ')
  [ "$_n" = "0" ] || { _fail "state-dir deve permanecer vazio" "obtido $_n entradas"; return 1; }
}

scenario_state_dir_vazio_argumento_e_erro_de_uso() {
  _rc=0
  state_read_materialize "" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" = "2" ] || { _fail "arg vazio => exit 2 (uso)" "obtido $_rc"; return 1; }
}

# ==== Backend SQLite (materializacao real via state-rw.sh read) ====

scenario_sqlite_materializa_fora_do_state_dir_legivel_por_jq() {
  _sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _sd=$(_mk_sqlite_state_dir) || { _fail "fixture sqlite" "init falhou"; return 1; }
  _out=$(state_read_materialize "$_sd") || { _fail "materialize sqlite" "exit != 0"; return 1; }
  [ -f "$_out" ] || { _fail "tmp materializado existe" "path '$_out'"; return 1; }
  case "$_out" in
    "$_sd"/*) _fail "tmp DENTRO do state-dir (FR-003)" "path '$_out'"; return 1 ;;
  esac
  _id=$(jq -r '.execution.id' "$_out" 2>/dev/null)
  [ "$_id" = "exec-sr-sqlite" ] || { _fail "doc materializado legivel" "obtido id '$_id'"; return 1; }
  rm -f -- "$_out" 2>/dev/null
}

scenario_sqlite_anti_mirror_nenhum_arquivo_novo_no_state_dir() {
  _sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _sd=$(_mk_sqlite_state_dir) || { _fail "fixture sqlite" "init falhou"; return 1; }
  _before=$(find "$_sd" -mindepth 1 | LC_ALL=C sort)
  _out=$(state_read_materialize "$_sd") || { _fail "materialize sqlite" "exit != 0"; return 1; }
  _after=$(find "$_sd" -mindepth 1 | LC_ALL=C sort)
  [ "$_before" = "$_after" ] || { _fail "anti-mirror FR-003: state-dir alterado" "diff: antes='$_before' depois='$_after'"; return 1; }
  [ ! -e "$_sd/state.json" ] || { _fail "espelho state.json criado (FR-003)" ""; return 1; }
  rm -f -- "$_out" 2>/dev/null
}

scenario_sqlite_state_db_corrompido_propaga_falha_nao_muda() {
  # Integracao FR-012: state-rw.sh read REAL falha (db corrompido) =>
  # materialize propaga exit != 0, nao imprime path, nao vaza tmp.
  command -v sqlite3 >/dev/null 2>&1 || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _sd="$TMPDIR_TEST/sd-corrompido"
  mkdir -p "$_sd"
  printf 'isto nao e um sqlite db\n' > "$_sd/state.db"
  _tmps_antes=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'state-read.*' 2>/dev/null | wc -l | tr -d ' ')
  _rc=0
  _out=$(state_read_materialize "$_sd" 2>/dev/null) || _rc=$?
  [ "$_rc" != "0" ] || { _fail "db corrompido => exit != 0" "exit 0, out '$_out'"; return 1; }
  [ -z "$_out" ] || { _fail "falha nao deve imprimir path" "obtido '$_out'"; return 1; }
  _tmps_depois=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'state-read.*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$_tmps_antes" = "$_tmps_depois" ] || { _fail "tmp orfao vazou apos falha" "antes=$_tmps_antes depois=$_tmps_depois"; return 1; }
}

scenario_sqlite_read_falha_propaga_exit_e_stderr_fake_rw() {
  # Hermetico FR-012 (1.2.3): reproduz o modo de falha "sqlite3 ausente"
  # com um state-rw.sh fake — o helper deve propagar exit + stderr.
  _sd="$TMPDIR_TEST/sd-fake-fail"
  mkdir -p "$_sd"
  : > "$_sd/state.db"
  _fake="$TMPDIR_TEST/fake-state-rw.sh"
  cat > "$_fake" <<'FAKE'
#!/bin/sh
printf 'state-rw: read: sqlite3 nao encontrado no PATH (simulacao FR-012)\n' >&2
exit 1
FAKE
  chmod +x "$_fake"
  _err="$TMPDIR_TEST/fake-fail.stderr"
  _rc=0
  _out=$(STATE_READ_RW="$_fake" state_read_materialize "$_sd" 2>"$_err") || _rc=$?
  [ "$_rc" = "1" ] || { _fail "propaga exit do read" "obtido $_rc"; return 1; }
  [ -z "$_out" ] || { _fail "falha nao deve imprimir path" "obtido '$_out'"; return 1; }
  grep -q 'sqlite3 nao encontrado' "$_err" || { _fail "stderr do read propagado" "obtido: $(cat "$_err")"; return 1; }
}

# ==== Cleanup (contract §4: trap EXIT INT TERM) ====

scenario_cleanup_remove_tmps_e_e_idempotente() {
  _sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _sd=$(_mk_sqlite_state_dir) || { _fail "fixture sqlite" "init falhou"; return 1; }
  _t1=$(state_read_materialize "$_sd") || { _fail "materialize 1" ""; return 1; }
  _t2=$(state_read_materialize "$_sd") || { _fail "materialize 2" ""; return 1; }
  [ -f "$_t1" ] && [ -f "$_t2" ] || { _fail "tmps existem antes do cleanup" ""; return 1; }
  state_read_cleanup || { _fail "cleanup exit 0" ""; return 1; }
  [ ! -e "$_t1" ] || { _fail "cleanup removeu tmp 1" "sobrou $_t1"; return 1; }
  [ ! -e "$_t2" ] || { _fail "cleanup removeu tmp 2" "sobrou $_t2"; return 1; }
  state_read_cleanup || { _fail "cleanup idempotente exit 0" ""; return 1; }
}

scenario_cleanup_sem_materializacao_e_noop_exit_0() {
  state_read_cleanup || { _fail "cleanup vazio exit 0" ""; return 1; }
}

run_all_scenarios
