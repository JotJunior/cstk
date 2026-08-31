#!/bin/sh
# Fixture: simula state-rw.sh get/set para `.optin_responses`, comecando
# vazio ("[]"), mas GRAVANDO o --value de cada `set` (uma linha por
# chamada) em $FAKE_SET_VALUE_FILE — usado para afirmar sobre o CONTEUDO
# efetivamente persistido (L1, task 9.4.1: reason escrubado ANTES do
# write). Mesmo espirito de fake-collect-optins-delivery-tier-captures-argv.sh.
set -eu
_cmd="${1:-}"
shift || true
case "$_cmd" in
  get)
    _field=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --field) _field="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    case "$_field" in
      ".optin_responses // []") printf '[]\n' ;;
      *) printf 'fake-collect-optins-state-rw-captures-set: campo desconhecido: %s\n' "$_field" >&2; exit 1 ;;
    esac
    ;;
  set)
    _value=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --value) _value="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ -n "${FAKE_SET_VALUE_FILE:-}" ]; then
      printf '%s\n' "$_value" >> "$FAKE_SET_VALUE_FILE"
    fi
    exit 0
    ;;
  *)
    printf 'fake-collect-optins-state-rw-captures-set: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
