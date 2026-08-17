#!/bin/sh
# Fixture: simula state-rw.sh get/set para `.optin_responses` ja com registro
# para os 2 campos aplicaveis a feature-00c (atomic_commit + roadmap_mode) —
# usado pelo teste do cap M6 (task 3.3.1: 2a coleta recusada, reuso).
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
      ".optin_responses // []")
        printf '[{"field":"atomic_commit","channel":"structured","outcome":"accepted","applied_value":"true","recorded_at":"2026-08-01T00:00:00.000Z","reason":null},{"field":"roadmap_mode","channel":"structured","outcome":"absent","applied_value":"false","recorded_at":"2026-08-01T00:00:01.000Z","reason":null}]\n'
        ;;
      *) printf 'fake-collect-optins-state-rw-preexisting: campo desconhecido: %s\n' "$_field" >&2; exit 1 ;;
    esac
    ;;
  set)
    exit 0
    ;;
  *)
    printf 'fake-collect-optins-state-rw-preexisting: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
