#!/bin/sh
# test_session-scope.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/session-scope.sh
# (issues #189/#190/#191: projeto-alvo != raiz da sessao). Regra de ouro.
#
# Cobertura:
#   resolve: CLAUDE_PROJECT_DIR (hook) vence; sem ela, pwd -P (tool Bash);
#            CLAUDE_PROJECT_DIR inexistente e ignorada (cai em cwd)
#   check:   aligned (mesmo path; symlink canonizado); diverged exit 4 +
#            linha `refused` no enforcement-log do ALVO; subdiretorio da
#            raiz NAO e alinhado; bypass por flag e por env => exit 0 +
#            `bypass-allowed` + AVISO em stderr; --quiet; alvo inexistente
#            exit 1; sem --projeto-alvo-path exit 2; falha de escrita do
#            log nao muda veredito
#   verdict: puro (sem log/stderr, ignora bypass, recusa --allow-outside)
#   mutation: neutralizar a comparacao derruba os cenarios de divergencia
#   -h/--help; subcomando desconhecido

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/session-scope.sh"

# _expect_exit N -> confere o exit da ultima captura (assert_exit do harness
# re-executa o comando; aqui a captura ja aconteceu com cwd controlado).
_expect_exit() {
  [ "$_CAPTURED_EXIT" = "$1" ] && return 0
  _fail "exit" "esperado exit=$1, obtido exit=$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
  return 1
}

# _canon PATH -> caminho canonico (macOS: /var -> /private/var).
_canon() { (CDPATH='' cd -- "$1" && pwd -P); }

# _mk_pair -> cria $ROOT (raiz da sessao) e $OTHER (alvo irmao) sob TMPDIR_TEST.
_mk_pair() {
  ROOT="$TMPDIR_TEST/session-root"
  OTHER="$TMPDIR_TEST/other-worktree"
  mkdir -p "$ROOT" "$OTHER"
  ROOT=$(_canon "$ROOT")
  OTHER=$(_canon "$OTHER")
}

# _run_in DIR CMD... -> executa com cwd=DIR e CLAUDE_PROJECT_DIR desligada.
_run_in() {
  _ri_dir=$1; shift
  capture sh -c 'cd -- "$1" && shift && unset CLAUDE_PROJECT_DIR && exec "$@"' _ "$_ri_dir" "$@"
}

# ==== resolve ====

scenario_resolve_usa_cwd_sem_claude_project_dir() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" resolve
  _expect_exit 0 || return 1
  assert_stdout_contains "session_root=$ROOT" || return 1
  assert_stdout_contains "source=cwd" || return 1
}

scenario_resolve_claude_project_dir_vence_cwd() {
  _mk_pair
  capture sh -c 'cd -- "$1" && CLAUDE_PROJECT_DIR="$2" exec "$3" resolve' _ "$OTHER" "$ROOT" "$SCRIPT"
  _expect_exit 0 || return 1
  assert_stdout_contains "session_root=$ROOT" || return 1
  assert_stdout_contains "source=claude-project-dir" || return 1
}

scenario_resolve_claude_project_dir_inexistente_cai_em_cwd() {
  _mk_pair
  capture sh -c 'cd -- "$1" && CLAUDE_PROJECT_DIR="$1/nao-existe" exec "$2" resolve' _ "$ROOT" "$SCRIPT"
  _expect_exit 0 || return 1
  assert_stdout_contains "session_root=$ROOT" || return 1
  assert_stdout_contains "source=cwd" || return 1
}

scenario_resolve_recusa_argumentos() {
  capture "$SCRIPT" resolve --foo
  _expect_exit 2 || return 1
}

# ==== check: aligned ====

scenario_check_aligned_mesmo_path_exit0_sem_log() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$ROOT"
  _expect_exit 0 || return 1
  assert_stdout_contains "verdict=aligned" || return 1
  assert_stdout_contains "reason=-" || return 1
  [ ! -e "$ROOT/.claude/enforcement-log.jsonl" ] \
    || { _fail "log" "aligned nao deve gravar enforcement-log"; return 1; }
}

scenario_check_aligned_via_symlink_canonizado() {
  _mk_pair
  ln -s "$ROOT" "$TMPDIR_TEST/link-root"
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$TMPDIR_TEST/link-root"
  _expect_exit 0 || return 1
  assert_stdout_contains "verdict=aligned" || return 1
  assert_stdout_contains "target_project_path=$ROOT" || return 1
}

# ==== check: diverged (fail-closed) ====

scenario_check_diverged_irmao_exit4_reason_cita_raiz() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$OTHER"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
  assert_stdout_contains "session_root=$ROOT" || return 1
  assert_stdout_contains "target_project_path=$OTHER" || return 1
  assert_stdout_contains "operam sob $ROOT" || return 1
  assert_stderr_contains "recusado" || return 1
  assert_stderr_contains "--allow-outside" || return 1
}

scenario_check_diverged_grava_refused_no_log_do_alvo() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$OTHER"
  _expect_exit 4 || return 1
  _log="$OTHER/.claude/enforcement-log.jsonl"
  [ -f "$_log" ] || { _fail "log" "enforcement-log do ALVO nao criado: $_log"; return 1; }
  [ ! -e "$ROOT/.claude/enforcement-log.jsonl" ] \
    || { _fail "log" "log gravado na raiz da sessao, deveria ser no alvo"; return 1; }
  _line=$(tail -n 1 "$_log")
  case "$_line" in
    *'"source":"session-scope"'*'"outcome":"refused"'*"\"session_root\":\"$ROOT\""*"\"target_project_path\":\"$OTHER\""*) ;;
    *) _fail "log" "linha inesperada: $_line"; return 1 ;;
  esac
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$_line" | jq -e . >/dev/null 2>&1 \
      || { _fail "log" "linha nao e JSON valido: $_line"; return 1; }
  fi
}

scenario_check_subdiretorio_da_raiz_nao_e_alinhado() {
  _mk_pair
  mkdir -p "$ROOT/sub/projeto"
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$ROOT/sub/projeto"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
}

scenario_check_raiz_e_subdiretorio_do_alvo_nao_e_alinhado() {
  _mk_pair
  mkdir -p "$OTHER/nested"
  _run_in "$OTHER/nested" "$SCRIPT" check --projeto-alvo-path "$OTHER"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
}

# ==== verdict: comparacao pura (sem log, sem bypass) ====

scenario_verdict_diverged_exit4_sem_log_e_sem_stderr() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" verdict --projeto-alvo-path "$OTHER"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
  assert_stdout_contains "session_root=$ROOT" || return 1
  [ ! -e "$OTHER/.claude/enforcement-log.jsonl" ] \
    || { _fail "log" "verdict e puro: nunca grava enforcement-log"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "verdict nao avisa: $_CAPTURED_STDERR"; return 1; }
}

scenario_verdict_ignora_bypass_por_env() {
  _mk_pair
  capture sh -c 'cd -- "$1" && unset CLAUDE_PROJECT_DIR && CSTK_ALLOW_TARGET_OUTSIDE_SESSION=1 exec "$2" verdict --projeto-alvo-path "$3"' \
    _ "$ROOT" "$SCRIPT" "$OTHER"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
}

scenario_verdict_recusa_allow_outside_exit2() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" verdict --projeto-alvo-path "$OTHER" --allow-outside
  _expect_exit 2 || return 1
}

scenario_verdict_aligned_exit0() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" verdict --projeto-alvo-path "$ROOT"
  _expect_exit 0 || return 1
  assert_stdout_contains "verdict=aligned" || return 1
}

# ==== check: bypass explicito e auditado ====

scenario_check_bypass_flag_exit0_aviso_e_log_bypass_allowed() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$OTHER" --allow-outside
  _expect_exit 0 || return 1
  assert_stdout_contains "verdict=diverged-allowed" || return 1
  assert_stderr_contains "AVISO" || return 1
  assert_stderr_contains "NAO gateiam" || return 1
  _line=$(tail -n 1 "$OTHER/.claude/enforcement-log.jsonl")
  case "$_line" in
    *'"outcome":"bypass-allowed"'*) ;;
    *) _fail "log" "esperado bypass-allowed: $_line"; return 1 ;;
  esac
}

scenario_check_bypass_env_exit0() {
  _mk_pair
  capture sh -c 'cd -- "$1" && unset CLAUDE_PROJECT_DIR && CSTK_ALLOW_TARGET_OUTSIDE_SESSION=1 exec "$2" check --projeto-alvo-path "$3"' \
    _ "$ROOT" "$SCRIPT" "$OTHER"
  _expect_exit 0 || return 1
  assert_stdout_contains "verdict=diverged-allowed" || return 1
  assert_stderr_contains "AVISO" || return 1
}

scenario_check_env_diferente_de_1_nao_e_bypass() {
  _mk_pair
  capture sh -c 'cd -- "$1" && unset CLAUDE_PROJECT_DIR && CSTK_ALLOW_TARGET_OUTSIDE_SESSION=true exec "$2" check --projeto-alvo-path "$3"' \
    _ "$ROOT" "$SCRIPT" "$OTHER"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
}

scenario_check_bypass_nao_se_aplica_quando_alinhado() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$ROOT" --allow-outside
  _expect_exit 0 || return 1
  assert_stdout_contains "verdict=aligned" || return 1
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "alinhado nao deve avisar: $_CAPTURED_STDERR"; return 1; }
}

# ==== check: --quiet, erros de uso ====

scenario_check_quiet_suprime_stdout_mantem_exit_e_log() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$OTHER" --quiet
  _expect_exit 4 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "--quiet deveria suprimir stdout: $_CAPTURED_STDOUT"; return 1; }
  [ -f "$OTHER/.claude/enforcement-log.jsonl" ] || { _fail "log" "--quiet nao pode pular o log"; return 1; }
}

scenario_check_alvo_inexistente_exit1() {
  _mk_pair
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$TMPDIR_TEST/nao-existe"
  _expect_exit 1 || return 1
  assert_stderr_contains "nao existe" || return 1
}

scenario_check_sem_projeto_alvo_path_exit2() {
  capture "$SCRIPT" check
  _expect_exit 2 || return 1
  assert_stderr_contains "obrigatorio" || return 1
}

scenario_check_flag_desconhecida_exit2() {
  _mk_pair
  capture "$SCRIPT" check --projeto-alvo-path "$ROOT" --bogus
  _expect_exit 2 || return 1
}

scenario_check_falha_de_escrita_do_log_nao_muda_veredito() {
  _mk_pair
  mkdir -p "$OTHER/.claude"
  chmod 500 "$OTHER/.claude"
  _run_in "$ROOT" "$SCRIPT" check --projeto-alvo-path "$OTHER"
  chmod 700 "$OTHER/.claude"
  _expect_exit 4 || return 1
  assert_stdout_contains "verdict=diverged" || return 1
}

# ==== mutation test: a comparacao e o que sustenta a guarda ====

scenario_mutation_comparacao_neutralizada_derruba_divergencia() {
  _mk_pair
  _mut="$TMPDIR_TEST/session-scope-mutant.sh"
  sed 's/if \[ "\$_SS_ROOT" = "\$_SS_TARGET" \]; then/if :; then/' "$SCRIPT" >"$_mut"
  grep -q 'if :; then' "$_mut" || { _fail "mutant" "sed nao encontrou a comparacao — teste stale"; return 1; }
  chmod +x "$_mut"
  _run_in "$ROOT" "$_mut" check --projeto-alvo-path "$OTHER"
  # O mutante responde aligned onde o original responde diverged: prova que
  # o cenario de divergencia depende da comparacao real, nao passa por
  # construcao.
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mutant" "mutante deveria passar (exit 0), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "verdict=aligned" || return 1
}

# ==== help / dispatch ====

scenario_help_exit0() {
  capture "$SCRIPT" --help
  _expect_exit 0 || return 1
  assert_stdout_contains "check --projeto-alvo-path PATH" || return 1
  assert_stdout_contains "#189" || return 1
}

scenario_sem_subcomando_exit2() {
  capture "$SCRIPT"
  _expect_exit 2 || return 1
}

scenario_subcomando_desconhecido_exit2() {
  capture "$SCRIPT" bogus
  _expect_exit 2 || return 1
  assert_stderr_contains "subcomando desconhecido" || return 1
}

run_all_scenarios
