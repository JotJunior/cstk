#!/bin/sh
# test__diag.sh — cobre _diag.sh (envelope diagnostico DIAG|severity|code|message|fix).
# Ref: docs/specs/openspec-hygiene/spec.md FR-012..FR-016
#      docs/specs/openspec-hygiene/contracts/diagnostic-envelope.md

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

DIAG_LIB="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_diag.sh"

# Sourcear o helper (nao e executavel)
# shellcheck disable=SC1090
. "$DIAG_LIB"

# ==== emissao dos 4 campos corretos ====

scenario_emite_quatro_campos() {
  _out=$(diag_emit error state-not-found "state.json ausente" "rode state-rw.sh init primeiro" 2>&1)
  _rc=$?
  if [ "$_rc" != "0" ]; then
    _fail "diag_emit" "exit esperado 0, got $_rc"
    return 1
  fi
  case "$_out" in
    "DIAG|error|state-not-found|state.json ausente|rode state-rw.sh init primeiro")
      ;;
    *)
      _fail "diag_emit" "linha DIAG inesperada: $_out"
      return 1
      ;;
  esac
}

# ==== escape de | interno em message/fix ====

scenario_escapa_pipe_interno() {
  _out=$(diag_emit warning some-code "mensagem com | pipe" "fix sem | pipe tambem" 2>&1)
  case "$_out" in
    "DIAG|warning|some-code|mensagem com / pipe|fix sem / pipe tambem")
      ;;
    *)
      _fail "escape_pipe" "escape incorreto: $_out"
      return 1
      ;;
  esac
}

# ==== severity invalida -> exit 1, sem emitir DIAG ====

scenario_severity_invalida_rejeitada() {
  _out=$(diag_emit critical some-code "msg" "fix" 2>&1)
  _rc=$?
  if [ "$_rc" = "0" ]; then
    _fail "severity_invalida" "esperado exit != 0 para severity invalida"
    return 1
  fi
  case "$_out" in
    DIAG\|*)
      _fail "severity_invalida" "nao deveria emitir DIAG| com severity invalida: $_out"
      return 1
      ;;
  esac
}

# ==== fix identico a message -> rejeitado, sem emitir DIAG ====

scenario_fix_igual_message_rejeitado() {
  _out=$(diag_emit error dup-code "mesma coisa" "mesma coisa" 2>&1)
  _rc=$?
  if [ "$_rc" = "0" ]; then
    _fail "fix_igual_message" "esperado exit != 0 quando fix == message"
    return 1
  fi
  case "$_out" in
    DIAG\|*)
      _fail "fix_igual_message" "nao deveria emitir DIAG| quando fix == message: $_out"
      return 1
      ;;
  esac
}

# ==== warning tambem e severity valida ====

scenario_severity_warning_valida() {
  _out=$(diag_emit warning ok-code "aviso" "corrigir depois" 2>&1)
  _rc=$?
  if [ "$_rc" != "0" ]; then
    _fail "severity_warning" "exit esperado 0, got $_rc"
    return 1
  fi
  case "$_out" in
    "DIAG|warning|ok-code|aviso|corrigir depois") ;;
    *)
      _fail "severity_warning" "linha inesperada: $_out"
      return 1
      ;;
  esac
}

# ==== emissao vai para stderr, nao stdout ====

scenario_emite_em_stderr() {
  _stdout=$(diag_emit error x "m" "f" 2>/dev/null)
  if [ -n "$_stdout" ]; then
    _fail "emite_stderr" "stdout deveria estar vazio, got: $_stdout"
    return 1
  fi
  _stderr=$(diag_emit error x "m" "f" 2>&1 >/dev/null)
  case "$_stderr" in
    DIAG\|error\|x\|m\|f) ;;
    *)
      _fail "emite_stderr" "stderr inesperado: $_stderr"
      return 1
      ;;
  esac
}

run_all_scenarios
