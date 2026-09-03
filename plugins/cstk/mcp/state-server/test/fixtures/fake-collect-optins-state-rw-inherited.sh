#!/bin/sh
# Fixture (issue #192): simula state-rw.sh get/set para `.optin_responses` com
# registro `channel: "inherited"` (reabertura, feature-reopen FR-022) para
# atomic_commit — qualquer registro do campo encerra a coleta (reused),
# sem re-perguntar ao operador; o canal nao importa para o reuso.
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
        printf '[{"field":"atomic_commit","channel":"inherited","outcome":"accepted","applied_value":"true","recorded_at":"2026-09-02T00:00:00.000Z","reason":null,"inherited_from":"r01"}]\n'
        ;;
      *) printf 'fake-collect-optins-state-rw-inherited: campo desconhecido: %s\n' "$_field" >&2; exit 1 ;;
    esac
    ;;
  set)
    exit 0
    ;;
  *)
    printf 'fake-collect-optins-state-rw-inherited: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
