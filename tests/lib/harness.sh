# harness.sh — biblioteca de assercoes e gestao de cenarios para a suite.
#
# Sourced pelos arquivos tests/test_*.sh. Fornece:
#   - mktemp_test / _cleanup_tmpdir        gestao isolada por teste (FR-005)
#   - capture                              captura stdout/stderr/exit
#   - assert_exit                          compara exit code
#   - assert_stdout_contains               substring em stdout capturado
#   - assert_stderr_contains               substring em stderr capturado
#   - assert_stdout_match                  regex (grep -E) sobre stdout
#   - assert_no_side_effect                valida git status limpo (heuristica)
#   - fixture                              copia fixtures/<nome> -> $TMPDIR_TEST
#   - run_all_scenarios                    descobre e executa scenarios
#   - _error                               marca scenario como ERROR (pre-req)
#
# Convencao de exit code de scenario (interpretada pelo runner):
#   0 -> PASS
#   1 -> FAIL (assercao violada — script sob teste comportou-se errado)
#   2 -> ERROR (harness/ambiente impediu avaliar — ex: mktemp ausente)
#
# POSIX sh puro. Sem Bash-isms. Sem deps alem de: mktemp, find, grep, diff,
# printf, cp, rm, cat, git (opcional, usado em assert_no_side_effect).

# NAO usamos 'set -eu' aqui porque o harness e sourced por scripts que ja tem
# suas proprias configuracoes. O harness retorna codigos explicitos em vez de
# abortar a shell do caller.

# ==== Constantes de status ====

_STATUS_PASS=0
_STATUS_FAIL=1
_STATUS_ERROR=2

# ==== Gestao de tmpdir ====

# mktemp_test: cria $TMPDIR_TEST unico e instala trap de limpeza.
# Chamado pelo run_all_scenarios antes de cada scenario.
# Retorno: 0 em sucesso; 2 se mktemp indisponivel (status ERROR).
mktemp_test() {
  TMPDIR_TEST=$(mktemp -d -t 'shell-tests.XXXXXX' 2>/dev/null) || {
    printf 'harness: falha ao criar tmpdir (mktemp ausente ou sem permissao)\n' >&2
    return "$_STATUS_ERROR"
  }
  export TMPDIR_TEST
  trap '_cleanup_tmpdir' EXIT INT TERM
  # Snapshot do git status como baseline para assert_no_side_effect.
  # Se o repo git tiver untracked files normais (desenvolvimento em andamento),
  # eles ja estao na baseline e nao contam como vazamento.
  _snapshot_git_status
  return 0
}

_snapshot_git_status() {
  _root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  (cd "$_root" && git status --porcelain) > "$TMPDIR_TEST/.gs_baseline" 2>/dev/null || :
}

_cleanup_tmpdir() {
  # Invocado via trap em EXIT/INT/TERM. Cobre FR-005 item (c).
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "${TMPDIR_TEST:-}" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ==== Captura de saida ====

# capture: executa comando, guarda stdout/stderr/exit em _CAPTURED_*.
# Uso: capture CMD [ARGS...]
# Variaveis preenchidas: _CAPTURED_CMD, _CAPTURED_STDOUT, _CAPTURED_STDERR,
# _CAPTURED_EXIT.
# Retorno: 0 (captura propria nao falha), 2 se mktemp indisponivel para tmpfiles.
capture() {
  _TMP_OUT=$(mktemp 2>/dev/null) || {
    printf 'harness: capture nao pode criar tmpfile\n' >&2
    return "$_STATUS_ERROR"
  }
  _TMP_ERR=$(mktemp 2>/dev/null) || {
    rm -f "$_TMP_OUT"
    printf 'harness: capture nao pode criar tmpfile\n' >&2
    return "$_STATUS_ERROR"
  }

  # Registra o comando exato para diagnostico em falhas.
  _CAPTURED_CMD="$*"

  # Executa capturando exit code sem alterar errexit do caller. O ' || _X=$?'
  # suprime errexit localmente, independente de set -e estar on ou off no
  # caller — este foi historicamente um ponto sensivel e mexer com set -e
  # aqui quebrou scenarios que dependiam do estado original.
  _CAPTURED_EXIT=0
  "$@" >"$_TMP_OUT" 2>"$_TMP_ERR" || _CAPTURED_EXIT=$?

  _CAPTURED_STDOUT=$(cat "$_TMP_OUT")
  _CAPTURED_STDERR=$(cat "$_TMP_ERR")
  rm -f "$_TMP_OUT" "$_TMP_ERR"
  return 0
}

# ==== Diagnostico de falha ====

# _fail: registra falha com contexto YAML-ish. Usado por assert_*.
# O scenario subshell aborta via return 1 apos chamada.
# Uso interno: _fail "nome_assert" "mensagem descritiva"
_fail() {
  _assert_name="$1"
  _msg="$2"
  printf '  ---\n'
  printf '  assert: %s\n' "$_assert_name"
  printf '  message: %s\n' "$_msg"
  if [ -n "${_CAPTURED_CMD:-}" ]; then
    printf '  command: %s\n' "$_CAPTURED_CMD"
    printf '  exit_code: %s\n' "${_CAPTURED_EXIT:-?}"
    # Truncagem de saida longa: mantem primeiros 20 linhas para legibilidade.
    printf '  stdout: |\n'
    printf '%s\n' "${_CAPTURED_STDOUT:-}" | head -n 20 | sed 's/^/    /'
    printf '  stderr: |\n'
    printf '%s\n' "${_CAPTURED_STDERR:-}" | head -n 20 | sed 's/^/    /'
  fi
  printf '  ---\n'
}

# _error: registra falha de pre-requisito (status ERROR, distinto de FAIL).
# Uso: _error "causa_curta" "mensagem detalhada"
_error() {
  _cause="$1"
  _msg="$2"
  printf '  ---\n'
  printf '  status: ERROR\n'
  printf '  cause: %s\n' "$_cause"
  printf '  message: %s\n' "$_msg"
  printf '  ---\n'
}

# ==== Assercoes ====

# assert_exit EXPECTED CMD [ARGS...]
# Executa CMD, compara exit code observado com EXPECTED.
# Retorno: 0 PASS, 1 FAIL, 2 ERROR (captura falhou).
assert_exit() {
  _expected="$1"
  shift
  capture "$@" || return "$_STATUS_ERROR"
  if [ "$_CAPTURED_EXIT" -eq "$_expected" ]; then
    return "$_STATUS_PASS"
  fi
  _fail "assert_exit" "esperado exit=$_expected, obtido exit=$_CAPTURED_EXIT"
  return "$_STATUS_FAIL"
}

# assert_stdout_contains SUBSTRING
# Requer captura previa (via capture ou assert_exit).
assert_stdout_contains() {
  _needle="$1"
  case "${_CAPTURED_STDOUT:-}" in
    *"$_needle"*)
      return "$_STATUS_PASS"
      ;;
  esac
  _fail "assert_stdout_contains" "stdout nao contem: $_needle"
  return "$_STATUS_FAIL"
}

# assert_stdout_not_contains SUBSTRING
# Inverso de assert_stdout_contains. Requer captura previa.
assert_stdout_not_contains() {
  _needle="$1"
  case "${_CAPTURED_STDOUT:-}" in
    *"$_needle"*)
      _fail "assert_stdout_not_contains" "stdout contem (nao deveria): $_needle"
      return "$_STATUS_FAIL"
      ;;
  esac
  return "$_STATUS_PASS"
}

# assert_stderr_contains SUBSTRING
assert_stderr_contains() {
  _needle="$1"
  case "${_CAPTURED_STDERR:-}" in
    *"$_needle"*)
      return "$_STATUS_PASS"
      ;;
  esac
  _fail "assert_stderr_contains" "stderr nao contem: $_needle"
  return "$_STATUS_FAIL"
}

# assert_stdout_match REGEX
# Usa grep -E (ERE, portavel).
assert_stdout_match() {
  _pattern="$1"
  if printf '%s\n' "${_CAPTURED_STDOUT:-}" | grep -Eq "$_pattern"; then
    return "$_STATUS_PASS"
  fi
  _fail "assert_stdout_match" "stdout nao casa regex: $_pattern"
  return "$_STATUS_FAIL"
}

# assert_no_side_effect
# Compara o git status ATUAL com a baseline capturada por mktemp_test no inicio
# do scenario. Falha se houve alteracao DURANTE o scenario (arquivo criado,
# modificado ou apagado no working tree do repo). Untracked files pre-existentes
# (ex: tests/ em desenvolvimento) ficam na baseline e nao contam como vazamento.
#
# Skip silencioso se fora de repo git.
assert_no_side_effect() {
  _root=$(git rev-parse --show-toplevel 2>/dev/null) || return "$_STATUS_PASS"
  _current=$(cd "$_root" && git status --porcelain 2>/dev/null) || return "$_STATUS_PASS"
  _baseline=$(cat "$TMPDIR_TEST/.gs_baseline" 2>/dev/null || printf '')
  if [ "$_current" = "$_baseline" ]; then
    return "$_STATUS_PASS"
  fi
  # Computa diff legivel em vez de so contar.
  _diff=$(printf '%s\n' "$_current" | grep -vxF "$_baseline" 2>/dev/null | head -5 || printf '')
  _fail "assert_no_side_effect" "git status mudou durante scenario (amostra: $_diff)"
  return "$_STATUS_FAIL"
}

# ==== Fixtures ====

# fixture NAME
# Copia o conteudo de $TESTS_ROOT/fixtures/NAME/. para $TMPDIR_TEST/
# Retorno: 0 sucesso, 2 ERROR (fixture ausente ou TESTS_ROOT nao definido).
fixture() {
  _name="$1"
  if [ -z "${TESTS_ROOT:-}" ]; then
    _error "fixture_no_tests_root" "variavel TESTS_ROOT nao definida"
    return "$_STATUS_ERROR"
  fi
  if [ -z "${TMPDIR_TEST:-}" ] || [ ! -d "${TMPDIR_TEST:-}" ]; then
    _error "fixture_no_tmpdir" "TMPDIR_TEST nao inicializado — chame mktemp_test antes"
    return "$_STATUS_ERROR"
  fi
  _src="$TESTS_ROOT/fixtures/$_name"
  if [ ! -d "$_src" ]; then
    _error "fixture_missing" "fixture '$_name' nao encontrada em $_src"
    return "$_STATUS_ERROR"
  fi
  # O trailing /. em _src copia o conteudo sem criar subpasta extra.
  cp -R "$_src"/. "$TMPDIR_TEST"/
  return "$_STATUS_PASS"
}

# ==== Descoberta e execucao de scenarios ====

# run_all_scenarios
# Descobre funcoes no shell atual cujo nome comece com 'scenario_'.
# Executa cada uma em subshell com $TMPDIR_TEST proprio e contabiliza resultado.
# Emite uma linha por scenario: 'ok N - file :: name' ou 'not ok N - file :: name'.
# Exit code final: 0 se todos PASS; 1 se qualquer FAIL; 2 se qualquer ERROR.
# ERROR tem precedencia sobre FAIL no sumario final.
run_all_scenarios() {
  _file=$(basename "${0:-unknown}")
  _scenarios=$(_list_scenarios)
  if [ -z "$_scenarios" ]; then
    printf '# %s: nenhum scenario definido\n' "$_file"
    return "$_STATUS_PASS"
  fi

  _idx=0
  _any_fail=0
  _any_error=0

  # IFS=newline para iterar nomes de funcoes.
  _OLD_IFS="$IFS"
  IFS='
'
  for _name in $_scenarios; do
    _idx=$((_idx + 1))
    # Subshell: garante que mktemp_test/trap de um scenario nao contamina proximo.
    # Restaura IFS DENTRO da subshell para que scenarios possam usar word
    # splitting normalmente (o IFS=newline do loop acima nao vaza para dentro).
    (
      IFS="$_OLD_IFS"
      mktemp_test || exit "$_STATUS_ERROR"
      "$_name"
    )
    _status=$?
    case "$_status" in
      0) printf 'ok %d - %s :: %s\n' "$_idx" "$_file" "$_name" ;;
      1) printf 'not ok %d - %s :: %s\n' "$_idx" "$_file" "$_name"; _any_fail=1 ;;
      2) printf 'not ok %d - %s :: %s # ERROR\n' "$_idx" "$_file" "$_name"; _any_error=1 ;;
      *) printf 'not ok %d - %s :: %s # unexpected exit %d\n' "$_idx" "$_file" "$_name" "$_status"; _any_error=1 ;;
    esac
  done
  IFS="$_OLD_IFS"

  if [ "$_any_error" -eq 1 ]; then
    return "$_STATUS_ERROR"
  fi
  if [ "$_any_fail" -eq 1 ]; then
    return "$_STATUS_FAIL"
  fi
  return "$_STATUS_PASS"
}

# _list_scenarios: imprime (uma por linha) os nomes de funcoes 'scenario_*'
# definidas estaticamente no arquivo $0 (o test file em execucao).
#
# Abordagem: grep no SOURCE do test file. POSIX puro — nao depende de
# 'typeset', 'declare' ou outras extensoes. A restricao e que scenarios
# precisam ser definidos com a sintaxe canonica 'scenario_NAME() {' no
# nivel top do arquivo (sem aninhamento dentro de outras funcoes), o que
# e a convencao natural para test files.
#
# Fallback: se a variavel _SCENARIOS estiver definida (lista separada por
# espacos), e usada em vez do grep. Util para testes que geram scenarios
# dinamicamente.
_list_scenarios() {
  if [ -n "${_SCENARIOS:-}" ]; then
    printf '%s\n' "$_SCENARIOS" | tr ' ' '\n' | sort -u | grep -v '^$'
    return 0
  fi
  if [ -r "${0:-}" ]; then
    # Grep por definicoes de funcao no padrao 'scenario_NAME ()' ou
    # 'scenario_NAME()'. Regex ERE portavel via grep -E.
    grep -E '^scenario_[A-Za-z0-9_]+ *\(\)' "$0" \
      | sed 's/ *(.*//' \
      | sort -u
    return 0
  fi
}

# run_single_scenario NAME FILE
# Util para self-tests do proprio harness (ex: test_harness.sh quer rodar
# um scenario especifico fora do run_all_scenarios para inspecionar status).
# Emite o mesmo formato de linha. Retorna o exit code do scenario.
run_single_scenario() {
  _name="$1"
  _file="${2:-$(basename "${0:-unknown}")}"
  (
    mktemp_test || exit "$_STATUS_ERROR"
    "$_name"
  )
  _status=$?
  case "$_status" in
    0) printf 'ok 1 - %s :: %s\n' "$_file" "$_name" ;;
    1) printf 'not ok 1 - %s :: %s\n' "$_file" "$_name" ;;
    2) printf 'not ok 1 - %s :: %s # ERROR\n' "$_file" "$_name" ;;
  esac
  return "$_status"
}
