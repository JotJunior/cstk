#!/bin/sh
# Fixture: simula state-rw.sh get/set para `.operator_answers`, comecando
# vazio ("[]"), mas GRAVANDO o --value de cada `set` (uma linha por
# chamada) em $FAKE_SET_VALUE_FILE — usado para afirmar sobre o CONTEUDO
# efetivamente persistido (task 2.4.4). Mesmo espirito de
# fake-collect-optins-state-rw-captures-set.sh.
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
      ".operator_answers // []")
        if [ -n "${FAKE_EXISTING_ANSWERS_FILE:-}" ] && [ -f "$FAKE_EXISTING_ANSWERS_FILE" ]; then
          cat "$FAKE_EXISTING_ANSWERS_FILE"
        else
          printf '[]\n'
        fi
        ;;
      *) printf 'fake-ask-operator-state-rw-captures-set: campo desconhecido: %s\n' "$_field" >&2; exit 1 ;;
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
    printf 'fake-ask-operator-state-rw-captures-set: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
