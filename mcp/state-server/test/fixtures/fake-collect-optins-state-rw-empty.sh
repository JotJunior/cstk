#!/bin/sh
# Fixture: simula state-rw.sh get/set para `.optin_responses`, comecando
# vazio ("[]") — usado por collect_optins.ts (leitura do cap M6 + append da
# camada 2). `get` sempre devolve "[]"; `set` aceita qualquer --value e
# retorna sucesso (nao ha persistencia real neste fixture).
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
      *) printf 'fake-collect-optins-state-rw-empty: campo desconhecido: %s\n' "$_field" >&2; exit 1 ;;
    esac
    ;;
  set)
    exit 0
    ;;
  *)
    printf 'fake-collect-optins-state-rw-empty: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
