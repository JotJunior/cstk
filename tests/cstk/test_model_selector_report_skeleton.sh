#!/bin/sh
# test_model_selector_report_skeleton.sh
#
# Cobre subtarefas 4.1.1-4.1.4 da feature `model-selector` (Ref:
# docs/specs/model-selector/tasks.md L207-L210, FR-012, FR-010a,
# Decision 5 do research.md). Valida invariantes do esqueleto:
#
#   4.1.1  shebang #!/bin/sh + set -eu  -> validado indiretamente via
#          static-analysis (rodada em outro gate) + behavior abaixo
#          (errexit propaga falha em paths sem leitura).
#   4.1.2  deteccao de jq via `command -v`  -> tag inline auditavel no
#          header markdown emitido (`jq_detectado=<0|1>`).
#   4.1.3  leitura read-only de N state.json  -> sha256 dos inputs
#          identico antes e depois da invocacao + tentativa de execucao
#          em cwd somente-leitura encerra graciosamente (nao explode com
#          erro de "cannot write").
#   4.1.4  exit codes 0/2/3 conforme contrato do header.
#
# Por que invariante:
#   O esqueleto cravado nesta task e o gate de seguranca para as tasks
#   4.2 (jq happy-path) e 4.3 (awk fallback). Se a base ja escrever em
#   inputs ou misturar exit codes, todo o pipeline a jusante herda o
#   bug.
#
# Casos cobertos (cenarios scenario_*):
#   sem args                -> exit 2 + mensagem em stderr
#   arg inexistente         -> exit 2 + mensagem citando o path
#   arg legivel             -> exit 0 + emite header markdown
#   arg sem permissao       -> exit 3 + mensagem citando o path
#   read-only enforcement   -> sha256 imutavel apos invocacao
#   cwd somente-leitura     -> ainda sai com exit 0 (zero escritas)
#   jq flag inline          -> header contem `jq_detectado=<0|1>`

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

REPORT="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/report.sh"
export REPORT

# ----------------------------------------------------------------------
# 4.1.4.a: sem args -> exit 2 + mensagem em stderr
# ----------------------------------------------------------------------
scenario_4_1_4_sem_args_exit_2() {
  capture sh "$REPORT"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "sem_args_exit" "esperado 2, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"pelo menos 1 arquivo"*) ;;
    *)
      _fail "sem_args_msg" \
        "stderr nao cita 'pelo menos 1 arquivo': $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.1.4.b: arg apontando para arquivo inexistente -> exit 2
# ----------------------------------------------------------------------
scenario_4_1_4_arg_inexistente_exit_2() {
  mktemp_test || return 2
  _missing="$TMPDIR_TEST/nao-existe.json"
  capture sh "$REPORT" "$_missing"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "missing_exit" "esperado 2, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"nao encontrado"*) ;;
    *)
      _fail "missing_msg" \
        "stderr nao cita 'nao encontrado': $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.1.4.c: arg legivel -> exit 0 + header markdown emitido
# ----------------------------------------------------------------------
scenario_4_1_4_arg_legivel_exit_0() {
  mktemp_test || return 2
  _state="$TMPDIR_TEST/state.json"
  printf '{"feature":"smoke"}\n' > "$_state"
  capture sh "$REPORT" "$_state"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "legivel_exit" "esperado 0, obtido: $_CAPTURED_EXIT" \
      "stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"# Relatorio agregado model-selector"*) ;;
    *)
      _fail "legivel_header" \
        "stdout nao contem header markdown: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.1.4.d: arg sem permissao -> exit 3
# (chmod 000 — root contorna; pulamos se UID=0 para nao gerar
#  falso-positivo em ambientes containerizados ou CI rodando como root)
# ----------------------------------------------------------------------
scenario_4_1_4_arg_sem_permissao_exit_3() {
  if [ "$(id -u)" = "0" ]; then
    # Skip silencioso: root ignora chmod 000. Retornar PASS porque o
    # cenario nao e validavel sob este uid.
    return 0
  fi
  mktemp_test || return 2
  _locked="$TMPDIR_TEST/locked.json"
  printf '{}\n' > "$_locked"
  chmod 000 "$_locked"
  capture sh "$REPORT" "$_locked"
  _exit="$_CAPTURED_EXIT"
  _stderr="$_CAPTURED_STDERR"
  # Restaurar perms ANTES de assertar (garante cleanup do tmpdir).
  chmod 600 "$_locked"
  if [ "$_exit" != "3" ]; then
    _fail "locked_exit" "esperado 3, obtido: $_exit (stderr=$_stderr)"
    return 1
  fi
  case "$_stderr" in
    *"sem permissao de leitura"*) ;;
    *)
      _fail "locked_msg" \
        "stderr nao cita 'sem permissao de leitura': $_stderr"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.1.3.a: leitura read-only — sha256 imutavel apos invocacao
# (regressao guard contra qualquer reintroducao de `>`, `>>`, `tee`)
# ----------------------------------------------------------------------
scenario_4_1_3_read_only_sha256_imutavel() {
  mktemp_test || return 2
  _a="$TMPDIR_TEST/a.json"
  _b="$TMPDIR_TEST/b.json"
  printf '{"x":1}\n' > "$_a"
  printf '{"y":2}\n' > "$_b"

  _hash_cmd=""
  if command -v shasum >/dev/null 2>&1; then
    _hash_cmd="shasum -a 256"
  elif command -v sha256sum >/dev/null 2>&1; then
    _hash_cmd="sha256sum"
  else
    # Ambiente sem hasher disponivel — registramos como ERROR para
    # nao mascarar mudancas read-only em um ambiente minimalista.
    printf 'harness: nenhum shasum/sha256sum disponivel\n' >&2
    return 2
  fi

  _sum_a_pre=$($_hash_cmd "$_a" | awk '{print $1}')
  _sum_b_pre=$($_hash_cmd "$_b" | awk '{print $1}')

  capture sh "$REPORT" "$_a" "$_b"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "ro_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi

  _sum_a_post=$($_hash_cmd "$_a" | awk '{print $1}')
  _sum_b_post=$($_hash_cmd "$_b" | awk '{print $1}')

  if [ "$_sum_a_pre" != "$_sum_a_post" ]; then
    _fail "ro_mutated_a" \
      "sha256 de $_a mudou: pre=$_sum_a_pre post=$_sum_a_post"
    return 1
  fi
  if [ "$_sum_b_pre" != "$_sum_b_post" ]; then
    _fail "ro_mutated_b" \
      "sha256 de $_b mudou: pre=$_sum_b_pre post=$_sum_b_post"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.1.3.b: invocacao a partir de cwd somente-leitura ainda sai 0
# (garante que report.sh NAO tenta gravar em $PWD — zero escritas
#  laterais). Skip em root pois chmod nao protege root.
# ----------------------------------------------------------------------
scenario_4_1_3_cwd_read_only_exit_0() {
  if [ "$(id -u)" = "0" ]; then
    return 0
  fi
  mktemp_test || return 2
  _ro_dir="$TMPDIR_TEST/ro-cwd"
  mkdir -p "$_ro_dir"
  _state="$TMPDIR_TEST/state.json"
  printf '{"k":"v"}\n' > "$_state"
  chmod 555 "$_ro_dir"

  # Subshell isola o `cd` e captura exit code.
  _out_file="$TMPDIR_TEST/out.txt"
  _err_file="$TMPDIR_TEST/err.txt"
  ( cd "$_ro_dir" && sh "$REPORT" "$_state" ) \
    > "$_out_file" 2> "$_err_file"
  _exit=$?

  chmod 755 "$_ro_dir"  # cleanup para que rm -rf do trap funcione

  if [ "$_exit" != "0" ]; then
    _fail "ro_cwd_exit" \
      "esperado 0 em cwd somente-leitura, obtido: $_exit; err=$(cat "$_err_file")"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.1.2: deteccao de jq via `command -v` emitida em tag inline
# (header contem `jq_detectado=<0|1>` para auditoria do operador)
# ----------------------------------------------------------------------
scenario_4_1_2_jq_flag_inline() {
  mktemp_test || return 2
  _state="$TMPDIR_TEST/state.json"
  printf '{}\n' > "$_state"
  capture sh "$REPORT" "$_state"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "jq_flag_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  # A flag deve ser 0 OU 1; qualquer outra coisa quebra contrato.
  case "$_CAPTURED_STDOUT" in
    *"jq_detectado=0"*|*"jq_detectado=1"*) ;;
    *)
      _fail "jq_flag_inline" \
        "stdout nao contem jq_detectado=<0|1>: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

run_all_scenarios
