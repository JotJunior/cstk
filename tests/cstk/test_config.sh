#!/bin/sh
# test_config.sh — cobre cli/lib/config.sh (resolvedor + delegacao pura
# para state-backend.sh).
#
# Ref: docs/specs/state-backend-config/tasks.md FASE 4, task 4.1.3
#      docs/specs/state-backend-config/research.md Decision 2
#
# ESCOPO: config.sh e SOMENTE uma fronteira de resolucao+delegacao. O
# comportamento de state-backend.sh em si (parsing, allowlist, escrita
# atomica, capability) e coberto por tests/test_state-backend.sh; aqui
# cobrimos apenas: (a) o resolvedor de 3 camadas (PATH, repo via CSTK_LIB,
# instalado), e (b) que args/exit code atravessam VERBATIM — usando um
# script stub controlavel em vez do state-backend.sh real, para isolar o
# contrato da fronteira do comportamento interno do script delegado.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB_DIR="$REPO_ROOT/cli/lib"

# _write_stub PATH_TO_SCRIPT -> grava um stub POSIX executavel que ecoa
# "STUB:<subcomando> <args...>" em stdout e sai com $STUB_EXIT (default 0).
# Usado para testar delegacao verbatim sem depender do comportamento real
# de state-backend.sh (ex.: presenca/versao de sqlite3 no ambiente do CI).
_write_stub() {
  _ws_path="$1"
  mkdir -p "$(dirname "$_ws_path")" || return 1
  cat > "$_ws_path" <<'STUB'
#!/bin/sh
printf 'STUB:%s\n' "$*"
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$_ws_path"
}

# _stage_config DEST_LIB_DIR -> copia o cli/lib/config.sh REAL (sob teste)
# para um diretorio de CSTK_LIB fabricado. Necessario porque `CSTK_LIB` e
# usado tanto para localizar config.sh (`. "$CSTK_LIB/config.sh"`) quanto,
# dentro dele, para computar o caminho de camada (2) relativo
# (`$CSTK_LIB/../../global/skills/...`) — os cenarios de resolvedor
# precisam de um CSTK_LIB fabricado, entao a copia do arquivo real e o
# jeito de exercitar o COMPORTAMENTO real sem depender da arvore do repo.
_stage_config() {
  _sc_dest="$1"
  mkdir -p "$_sc_dest" || return 1
  cp "$CSTK_LIB_DIR/config.sh" "$_sc_dest/config.sh" || return 1
}

# ==== Resolvedor de 3 camadas ====

# Camada (2): layout de repo relativo a CSTK_LIB. HOME vazio garante que a
# camada (3) nao poderia resolver por acidente (mesma licao de campo de
# _state_migrate_script_path: nao pode depender exclusivamente de ~/.claude).
scenario_resolver_camada_repo_via_cstk_lib() {
  _repo="$TMPDIR_TEST/repo"
  _lib="$_repo/cli/lib"
  _script="$_repo/global/skills/agente-00c-runtime/scripts/state-backend.sh"
  _stage_config "$_lib" || { _error "fixture" "stage config falhou"; return 2; }
  _write_stub "$_script" || { _error "fixture" "stub falhou"; return 2; }

  # A funcao imprime o caminho RELATIVO nao-normalizado ($CSTK_LIB/../../...),
  # entao a expectativa e construida do mesmo jeito (mesmo padrao usado por
  # `_state_migrate_script_path`/test_state.sh para a camada repo).
  _expected="$_lib/../../global/skills/agente-00c-runtime/scripts/state-backend.sh"
  _out=$(HOME="$TMPDIR_TEST/home-vazio" CSTK_LIB="$_lib" PATH="/usr/bin:/bin" sh -c '
    . "$CSTK_LIB/config.sh"
    _config_state_backend_script_path
  ' 2>/dev/null) || { _fail "resolucao via repo falhou" ""; return 1; }
  [ "$_out" = "$_expected" ] || { _fail "camada repo nao resolveu o script esperado" "obtido=$_out esperado=$_expected"; return 1; }
}

# Camada (3): layout instalado em $HOME/.claude/skills/..., quando CSTK_LIB
# nao aponta para nenhum repo com o script (camada 2 ausente).
scenario_resolver_camada_instalado_via_home() {
  _home="$TMPDIR_TEST/home-instalado"
  _script="$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"
  _lib_vazio="$TMPDIR_TEST/lib-sem-script/cli/lib"
  _stage_config "$_lib_vazio" || { _error "fixture" "stage config falhou"; return 2; }
  _write_stub "$_script" || { _error "fixture" "stub falhou"; return 2; }

  _out=$(HOME="$_home" CSTK_LIB="$_lib_vazio" PATH="/usr/bin:/bin" sh -c '
    . "$CSTK_LIB/config.sh"
    _config_state_backend_script_path
  ' 2>/dev/null) || { _fail "resolucao via instalado falhou" ""; return 1; }
  [ "$_out" = "$_script" ] || { _fail "camada instalado nao resolveu o script esperado" "obtido=$_out esperado=$_script"; return 1; }
}

# Camada (1): PATH via `command -v` — tem prioridade sobre repo e instalado.
scenario_resolver_camada_path_tem_prioridade() {
  _pathbin="$TMPDIR_TEST/pathbin"
  _path_script="$_pathbin/state-backend.sh"
  mkdir -p "$_pathbin" || { _error "fixture" "mkdir falhou"; return 2; }
  _write_stub "$_path_script" || { _error "fixture" "stub falhou"; return 2; }

  # Tambem cria um script no layout de repo, para confirmar que o do PATH
  # vence (ordem de prioridade: PATH > repo > instalado).
  _repo="$TMPDIR_TEST/repo2"
  _lib="$_repo/cli/lib"
  _repo_script="$_repo/global/skills/agente-00c-runtime/scripts/state-backend.sh"
  _stage_config "$_lib" || { _error "fixture" "stage config falhou"; return 2; }
  _write_stub "$_repo_script" || { _error "fixture" "stub falhou"; return 2; }

  _out=$(HOME="$TMPDIR_TEST/home-vazio2" CSTK_LIB="$_lib" PATH="$_pathbin:/usr/bin:/bin" sh -c '
    . "$CSTK_LIB/config.sh"
    _config_state_backend_script_path
  ' 2>/dev/null) || { _fail "resolucao via PATH falhou" ""; return 1; }
  [ "$_out" = "$_path_script" ] || { _fail "camada PATH nao teve prioridade" "obtido=$_out esperado=$_path_script"; return 1; }
}

# Nenhuma camada resolve -> as funcoes de delegacao devem falhar com
# diagnostico em stderr + exit 1 (nao 0, nao silencioso).
scenario_resolver_nenhuma_camada_disponivel_falha_exit_1() {
  _lib_vazio="$TMPDIR_TEST/lib-vazio/cli/lib"
  _stage_config "$_lib_vazio" || { _error "fixture" "stage config falhou"; return 2; }

  capture env HOME="$TMPDIR_TEST/home-vazio3" CSTK_LIB="$_lib_vazio" PATH="/usr/bin:/bin" sh -c '
    . "$CSTK_LIB/config.sh"
    config_state_backend_capability
  '
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "script ausente deveria falhar exit 1" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"nao encontrado"*) : ;;
    *) _fail "diagnostico nao cita script ausente" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== Delegacao verbatim (args + exit code) ====

# Fixture comum: script no layout de repo, resolvido via CSTK_LIB.
_setup_repo_stub() {
  _srs_repo="$TMPDIR_TEST/repo-deleg"
  _srs_lib="$_srs_repo/cli/lib"
  _srs_script="$_srs_repo/global/skills/agente-00c-runtime/scripts/state-backend.sh"
  _stage_config "$_srs_lib" || return 1
  _write_stub "$_srs_script" || return 1
  return 0
}

scenario_delegacao_capability_repassa_args_e_exit0() {
  _setup_repo_stub || { _error "fixture" ""; return 2; }
  capture env HOME="$TMPDIR_TEST/home-x1" CSTK_LIB="$_srs_lib" PATH="/usr/bin:/bin" STUB_EXIT=0 sh -c '
    . "$CSTK_LIB/config.sh"
    config_state_backend_capability
  '
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "capability deveria repassar exit 0" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    "STUB:capability"*) : ;;
    *) _fail "subcomando nao repassado verbatim" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_delegacao_resolve_repassa_exit_customizado() {
  _setup_repo_stub || { _error "fixture" ""; return 2; }
  capture env HOME="$TMPDIR_TEST/home-x2" CSTK_LIB="$_srs_lib" PATH="/usr/bin:/bin" STUB_EXIT=1 sh -c '
    . "$CSTK_LIB/config.sh"
    config_state_backend_resolve
  '
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "resolve deveria repassar exit customizado verbatim" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    "STUB:resolve"*) : ;;
    *) _fail "subcomando nao repassado verbatim" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# Exit 3 (recusado por pre-condicao) e o caso mais importante de
# enable-sqlite (P8/FR-004A) — confirma que a fronteira NAO normaliza nem
# absorve esse exit code.
scenario_delegacao_enable_sqlite_repassa_exit_3_e_argumentos() {
  _setup_repo_stub || { _error "fixture" ""; return 2; }
  capture env HOME="$TMPDIR_TEST/home-x3" CSTK_LIB="$_srs_lib" PATH="/usr/bin:/bin" STUB_EXIT=3 sh -c '
    . "$CSTK_LIB/config.sh"
    config_state_backend_enable_sqlite --algum-arg valor
  '
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "enable-sqlite deveria repassar exit 3 verbatim" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    "STUB:enable-sqlite --algum-arg valor"*) : ;;
    *) _fail "argumentos nao repassados verbatim" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

run_all_scenarios
